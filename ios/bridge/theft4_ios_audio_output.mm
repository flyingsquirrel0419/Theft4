#include "theft4_ios_audio_output.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>

#include <rex/audio/conversion.h>
#include <rex/audio/handoff_trace.h>
#include <rex/logging.h>

namespace {

constexpr uint32_t kSampleRate = 48000;
constexpr uint32_t kChannels = 2;
constexpr uint32_t kGuestFramesPerBlock = 256;
constexpr uint32_t kRingFrames = 16384;
// XeniOS requires a minimum of 32 queued Xbox mixer blocks on iOS. Match that
// proven depth here: draw-heavy GTA IV scenes can occupy the GPU submission
// and guest threads for much longer than the old eight-block (43 ms) window.
constexpr uint32_t kPrerollBlocks = 32;
constexpr uint32_t kPrerollFrames = kGuestFramesPerBlock * kPrerollBlocks;
constexpr uint32_t kRecoveryBlocks = 8;
// The 5.1 -> stereo downmix is normalized so coincident full-scale channels
// cannot overflow, which leaves typical game mixes ~7-10 dB below the console's
// stereo output. That is barely audible on headphones (iOS also caps headphone
// level). Apply make-up gain and a soft knee limiter instead of hard clipping.
constexpr float kDefaultOutputGain = 2.0f;
constexpr float kLimiterKnee = 0.80f;

}  // namespace

struct theft4_ios_audio_output {
  AudioUnit unit = nullptr;
  std::array<float, kRingFrames * kChannels> ring{};
  std::atomic<uint64_t> read_frame{0};
  std::atomic<uint64_t> write_frame{0};
  std::atomic<uint64_t> underrun_frames{0};
  std::atomic<uint64_t> rebuffer_events{0};
  std::atomic<uint64_t> recovery_silence_frames{0};
  std::atomic<uint64_t> startup_silence_frames{0};
  std::atomic<uint64_t> rendered_frames{0};
  std::atomic<uint64_t> dropped_blocks{0};
  std::atomic<uint64_t> submitted_blocks{0};
  std::atomic<uint64_t> requested_blocks{kPrerollBlocks};
  std::atomic<uint64_t> clipped_samples{0};
  std::atomic<uint64_t> nonfinite_samples{0};
  std::atomic<bool> playback_ready{false};
  std::atomic<bool> unit_running{false};
  float output_gain = kDefaultOutputGain;
  uint32_t recovery_frames = kGuestFramesPerBlock * kRecoveryBlocks;
  bool playback_started = false;  // AudioUnit callback thread only.
  uint32_t fade_in_frames = 0;    // AudioUnit callback thread only.
  uint64_t logged_underrun_frames = 0;
  uint64_t logged_rebuffer_events = 0;
  uint64_t logged_dropped_blocks = 0;
  std::mutex producer_mutex;
};

namespace {

void ClearAudioBuffers(AudioBufferList* buffers) {
  for (UInt32 index = 0; index < buffers->mNumberBuffers; ++index) {
    if (buffers->mBuffers[index].mData) {
      std::memset(buffers->mBuffers[index].mData, 0,
                  buffers->mBuffers[index].mDataByteSize);
    }
  }
}

float SanitizeSample(float sample, uint64_t* clipped, uint64_t* nonfinite) {
  if (!std::isfinite(sample)) {
    ++*nonfinite;
    return 0.0f;
  }
  if (sample > 1.0f) {
    ++*clipped;
    return 1.0f;
  }
  if (sample < -1.0f) {
    ++*clipped;
    return -1.0f;
  }
  return sample;
}

float SoftLimit(float sample) {
  const float magnitude = std::fabs(sample);
  if (magnitude <= kLimiterKnee) return sample;
  constexpr float headroom = 1.0f - kLimiterKnee;
  const float limited =
      kLimiterKnee + headroom * std::tanh((magnitude - kLimiterKnee) / headroom);
  return std::copysign(limited, sample);
}

OSStatus RenderAudio(void* context, AudioUnitRenderActionFlags*,
                     const AudioTimeStamp*, UInt32, UInt32 frame_count,
                     AudioBufferList* buffers) {
  auto* output = static_cast<theft4_ios_audio_output*>(context);
  if (!output || !buffers) return noErr;

  const uint64_t read = output->read_frame.load(std::memory_order_relaxed);
  const uint64_t write = output->write_frame.load(std::memory_order_acquire);
  const uint64_t queued_frames = write - read;

  bool playback_ready =
      output->playback_ready.load(std::memory_order_relaxed);
  rex::audio::handoff::Record("ios-render", 0,
                              {frame_count, queued_frames, playback_ready,
                               output->read_frame.load(std::memory_order_relaxed), write});
  if (!playback_ready) {
    // Bluetooth/AirPlay routes can request hardware blocks larger than the
    // recovery threshold. Restarting below one full block would underrun on
    // the very next callback and flap between silence and playback forever.
    const uint32_t restart_frames = std::max<uint32_t>(
        output->playback_started ? output->recovery_frames : kPrerollFrames,
        std::min<uint32_t>(frame_count, kRingFrames / 2));
    if (queued_frames < restart_frames) {
      auto& silence = output->playback_started ? output->recovery_silence_frames
                                               : output->startup_silence_frames;
      silence.fetch_add(frame_count, std::memory_order_relaxed);
      ClearAudioBuffers(buffers);
      return noErr;
    }
    output->playback_ready.store(true, std::memory_order_relaxed);
    if (output->playback_started) output->fade_in_frames = 128;
    output->playback_started = true;
    rex::audio::handoff::Record("ios-restart", 0,
                                {queued_frames, restart_frames});
    playback_ready = true;
  }

  // Never consume a partial hardware block. Doing so creates a discontinuity
  // followed by silence (the audible crackle). Hold the queued samples and
  // rebuild the reliability preroll instead.
  if (playback_ready && queued_frames < frame_count) {
    output->playback_ready.store(false, std::memory_order_relaxed);
    output->underrun_frames.fetch_add(frame_count, std::memory_order_relaxed);
    output->recovery_silence_frames.fetch_add(frame_count, std::memory_order_relaxed);
    output->rebuffer_events.fetch_add(1, std::memory_order_relaxed);
    rex::audio::handoff::Record("ios-underrun", 0,
                                {frame_count, queued_frames, read, write});
    ClearAudioBuffers(buffers);
    return noErr;
  }

  const uint32_t available = frame_count;
  uint64_t clipped = 0;
  uint64_t nonfinite = 0;

  if (buffers->mNumberBuffers == 1 && buffers->mBuffers[0].mData) {
    auto* destination = static_cast<float*>(buffers->mBuffers[0].mData);
    for (uint32_t frame = 0; frame < available; ++frame) {
      const size_t source = ((read + frame) % kRingFrames) * kChannels;
      destination[frame * 2] =
          SanitizeSample(output->ring[source], &clipped, &nonfinite);
      destination[frame * 2 + 1] =
          SanitizeSample(output->ring[source + 1], &clipped, &nonfinite);
      if (output->fade_in_frames) {
        const float gain = float(129 - output->fade_in_frames) / 128.0f;
        destination[frame * 2] *= gain;
        destination[frame * 2 + 1] *= gain;
        --output->fade_in_frames;
      }
    }
    std::fill(destination + available * 2,
              destination + frame_count * 2, 0.0f);
  } else if (buffers->mNumberBuffers >= 2 &&
             buffers->mBuffers[0].mData && buffers->mBuffers[1].mData) {
    auto* left = static_cast<float*>(buffers->mBuffers[0].mData);
    auto* right = static_cast<float*>(buffers->mBuffers[1].mData);
    for (uint32_t frame = 0; frame < available; ++frame) {
      const size_t source = ((read + frame) % kRingFrames) * kChannels;
      left[frame] = SanitizeSample(output->ring[source], &clipped, &nonfinite);
      right[frame] =
          SanitizeSample(output->ring[source + 1], &clipped, &nonfinite);
      if (output->fade_in_frames) {
        const float gain = float(129 - output->fade_in_frames) / 128.0f;
        left[frame] *= gain;
        right[frame] *= gain;
        --output->fade_in_frames;
      }
    }
    std::fill(left + available, left + frame_count, 0.0f);
    std::fill(right + available, right + frame_count, 0.0f);
  } else {
    ClearAudioBuffers(buffers);
  }

  const uint64_t read_after = read + available;
  output->read_frame.store(read_after, std::memory_order_release);
  output->rendered_frames.fetch_add(available, std::memory_order_relaxed);
  output->requested_blocks.store(
      read_after / kGuestFramesPerBlock + kPrerollBlocks,
      std::memory_order_release);
  if (clipped) {
    output->clipped_samples.fetch_add(clipped, std::memory_order_relaxed);
  }
  if (nonfinite) {
    output->nonfinite_samples.fetch_add(nonfinite,
                                        std::memory_order_relaxed);
  }
  return noErr;
}

bool ConfigureAudioSession() {
  AVAudioSession* session = AVAudioSession.sharedInstance;
  NSError* error = nil;
  if (![session setCategory:AVAudioSessionCategoryPlayback
                       mode:AVAudioSessionModeDefault
                    options:0
                      error:&error]) {
    REXLOG_ERROR("Theft4 audio session category failed: {}",
                 error.localizedDescription.UTF8String ?: "unknown error");
    return false;
  }
  [session setPreferredSampleRate:kSampleRate error:&error];
  error = nil;
  [session setPreferredIOBufferDuration:
               (static_cast<double>(kGuestFramesPerBlock) / kSampleRate)
                               error:&error];
  error = nil;
  if (![session setActive:YES error:&error]) {
    REXLOG_ERROR("Theft4 audio session activation failed: {}",
                 error.localizedDescription.UTF8String ?: "unknown error");
    return false;
  }
  REXLOG_INFO("Theft4 AudioSession actual rate={} Hz io_buffer={} ms output_latency={} ms",
              session.sampleRate, session.IOBufferDuration * 1000.0,
              session.outputLatency * 1000.0);
  return true;
}

// Lifecycle state shared by the app (main thread) and session notifications.
std::mutex g_lifecycle_mutex;
theft4_ios_audio_output* g_output = nullptr;  // Guarded by g_lifecycle_mutex.
bool g_app_active = true;                     // Guarded by g_lifecycle_mutex.
bool g_interrupted = false;                   // Guarded by g_lifecycle_mutex.
NSArray<id>* g_observers = nil;               // Guarded by g_lifecycle_mutex.

void StopUnitLocked(theft4_ios_audio_output* output) {
  if (!output || !output->unit ||
      !output->unit_running.exchange(false, std::memory_order_acq_rel)) {
    return;
  }
  AudioOutputUnitStop(output->unit);
  // Rebuild the recovery preroll on restart; queued samples are kept.
  output->playback_ready.store(false, std::memory_order_relaxed);
}

void StartUnitLocked(theft4_ios_audio_output* output) {
  if (!output || !output->unit || !g_app_active || g_interrupted ||
      output->unit_running.load(std::memory_order_acquire)) {
    return;
  }
  NSError* error = nil;
  if (![AVAudioSession.sharedInstance setActive:YES error:&error]) {
    REXLOG_WARN("Theft4 audio session reactivation failed: {}",
                error.localizedDescription.UTF8String ?: "unknown error");
  }
  const OSStatus status = AudioOutputUnitStart(output->unit);
  if (status == noErr) {
    output->unit_running.store(true, std::memory_order_release);
  } else {
    REXLOG_WARN("Theft4 AudioUnit restart failed with status {}", int32_t(status));
  }
}

void ApplyLifecycleLocked() {
  if (!g_output) return;
  if (g_app_active && !g_interrupted) {
    StartUnitLocked(g_output);
  } else {
    StopUnitLocked(g_output);
    if (!g_app_active) {
      // Let other apps' audio resume while Theft4 is in the background.
      [AVAudioSession.sharedInstance
            setActive:NO
          withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                error:nil];
    }
  }
}

void InstallSessionObserversLocked() {
  if (g_observers) return;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  NSOperationQueue* queue = NSOperationQueue.mainQueue;
  id interruption = [center
      addObserverForName:AVAudioSessionInterruptionNotification
                  object:nil
                   queue:queue
              usingBlock:^(NSNotification* note) {
                const auto type = static_cast<AVAudioSessionInterruptionType>(
                    [note.userInfo[AVAudioSessionInterruptionTypeKey]
                        unsignedIntegerValue]);
                std::lock_guard lock(g_lifecycle_mutex);
                if (type == AVAudioSessionInterruptionTypeBegan) {
                  g_interrupted = true;
                  // iOS has already stopped the unit; record it.
                  if (g_output) {
                    g_output->unit_running.store(false, std::memory_order_release);
                    g_output->playback_ready.store(false, std::memory_order_relaxed);
                  }
                } else {
                  g_interrupted = false;
                }
                REXLOG_INFO("Theft4 audio interruption {}",
                            g_interrupted ? "began" : "ended");
                ApplyLifecycleLocked();
              }];
  id route = [center
      addObserverForName:AVAudioSessionRouteChangeNotification
                  object:nil
                   queue:queue
              usingBlock:^(NSNotification* note) {
                const auto reason = static_cast<AVAudioSessionRouteChangeReason>(
                    [note.userInfo[AVAudioSessionRouteChangeReasonKey]
                        unsignedIntegerValue]);
                AVAudioSession* session = AVAudioSession.sharedInstance;
                AVAudioSessionPortDescription* port =
                    session.currentRoute.outputs.firstObject;
                REXLOG_INFO(
                    "Theft4 audio route changed (reason {}): {} rate={} Hz "
                    "io_buffer={} ms latency={} ms",
                    int(reason), port.portType.UTF8String ?: "none",
                    session.sampleRate, session.IOBufferDuration * 1000.0,
                    session.outputLatency * 1000.0);
                std::lock_guard lock(g_lifecycle_mutex);
                if (!g_output || !g_app_active || g_interrupted) return;
                // Headphones and Bluetooth routes renegotiate the hardware
                // format; a RemoteIO unit can be left stopped by the switch.
                // Re-prime and restart so the new route receives audio.
                if (g_output->unit) {
                  Boolean running = false;
                  UInt32 size = sizeof(running);
                  if (AudioUnitGetProperty(g_output->unit,
                                           kAudioOutputUnitProperty_IsRunning,
                                           kAudioUnitScope_Global, 0, &running,
                                           &size) == noErr &&
                      !running) {
                    g_output->unit_running.store(false, std::memory_order_release);
                  }
                }
                g_output->playback_ready.store(false, std::memory_order_relaxed);
                StartUnitLocked(g_output);
              }];
  id reset = [center
      addObserverForName:AVAudioSessionMediaServicesWereResetNotification
                  object:nil
                   queue:queue
              usingBlock:^(NSNotification*) {
                std::lock_guard lock(g_lifecycle_mutex);
                REXLOG_WARN("Theft4 audio media services were reset");
                if (!g_output) return;
                ConfigureAudioSession();
                g_output->unit_running.store(false, std::memory_order_release);
                g_output->playback_ready.store(false, std::memory_order_relaxed);
                ApplyLifecycleLocked();
              }];
  g_observers = @[ interruption, route, reset ];
}
}  // namespace

extern "C" void theft4_ios_audio_set_app_active(bool active) {
  std::lock_guard lock(g_lifecycle_mutex);
  if (g_app_active == active) return;
  g_app_active = active;
  REXLOG_INFO("Theft4 audio app {}", active ? "foreground" : "background");
  ApplyLifecycleLocked();
}

theft4_ios_audio_output* theft4_ios_audio_output_create() {
  if (!ConfigureAudioSession()) return nullptr;

  auto* output = new theft4_ios_audio_output();
  if (const char* setting = std::getenv("THEFT4_AUDIO_RECOVERY_BLOCKS")) {
    char* end = nullptr;
    const unsigned long blocks = std::strtoul(setting, &end, 10);
    if (end && !*end && blocks >= 1 && blocks <= kPrerollBlocks) {
      output->recovery_frames =
          static_cast<uint32_t>(blocks) * kGuestFramesPerBlock;
    } else {
      REXLOG_WARN(
          "Ignoring invalid THEFT4_AUDIO_RECOVERY_BLOCKS={} (expected 1..{})",
          setting, kPrerollBlocks);
    }
  }
  if (const char* setting = std::getenv("THEFT4_AUDIO_GAIN")) {
    char* end = nullptr;
    const float gain = std::strtof(setting, &end);
    if (end && !*end && std::isfinite(gain) && gain >= 0.25f && gain <= 4.0f) {
      output->output_gain = gain;
    } else {
      REXLOG_WARN("Ignoring invalid THEFT4_AUDIO_GAIN={} (expected 0.25..4)",
                  setting);
    }
  }
  AudioComponentDescription description{};
  description.componentType = kAudioUnitType_Output;
  description.componentSubType = kAudioUnitSubType_RemoteIO;
  description.componentManufacturer = kAudioUnitManufacturer_Apple;
  AudioComponent component = AudioComponentFindNext(nullptr, &description);
  if (!component ||
      AudioComponentInstanceNew(component, &output->unit) != noErr) {
    REXLOG_ERROR("Theft4 AudioUnit creation failed");
    delete output;
    return nullptr;
  }

  AudioStreamBasicDescription format{};
  format.mSampleRate = kSampleRate;
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
  format.mBytesPerPacket = sizeof(float) * kChannels;
  format.mFramesPerPacket = 1;
  format.mBytesPerFrame = sizeof(float) * kChannels;
  format.mChannelsPerFrame = kChannels;
  format.mBitsPerChannel = sizeof(float) * 8;
  AURenderCallbackStruct callback{RenderAudio, output};

  OSStatus status = AudioUnitSetProperty(
      output->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
      0, &format, sizeof(format));
  if (status == noErr) {
    status = AudioUnitSetProperty(
        output->unit, kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input, 0, &callback, sizeof(callback));
  }
  if (status == noErr) status = AudioUnitInitialize(output->unit);
  if (status != noErr) {
    REXLOG_ERROR("Theft4 AudioUnit initialization failed with status {}",
                 int32_t(status));
    AudioComponentInstanceDispose(output->unit);
    delete output;
    return nullptr;
  }

  {
    std::lock_guard lock(g_lifecycle_mutex);
    g_output = output;
    InstallSessionObserversLocked();
    StartUnitLocked(output);
    if (g_app_active && !g_interrupted &&
        !output->unit_running.load(std::memory_order_acquire)) {
      g_output = nullptr;
      AudioUnitUninitialize(output->unit);
      AudioComponentInstanceDispose(output->unit);
      delete output;
      REXLOG_ERROR("Theft4 AudioUnit failed to start");
      return nullptr;
    }
  }

  REXLOG_INFO(
      "Theft4 native iOS audio output started: 48 kHz stereo, {}-frame ring, "
      "{}-frame initial preroll, {}-frame recovery threshold, gain {:.2f}",
      kRingFrames, kPrerollFrames, output->recovery_frames, output->output_gain);
  return output;
}

void theft4_ios_audio_output_destroy(theft4_ios_audio_output* output) {
  if (!output) return;
  {
    std::lock_guard lock(g_lifecycle_mutex);
    if (g_output == output) g_output = nullptr;
    output->unit_running.store(false, std::memory_order_release);
  }
  if (output->unit) {
    AudioOutputUnitStop(output->unit);
    AudioUnitUninitialize(output->unit);
    AudioComponentInstanceDispose(output->unit);
  }
  delete output;
}

bool theft4_ios_audio_output_submit(theft4_ios_audio_output* output,
                                    const float* guest_samples,
                                    size_t guest_frame_count) {
  if (!output || !guest_samples ||
      guest_frame_count != kGuestFramesPerBlock) {
    return false;
  }

  std::array<float, kGuestFramesPerBlock * kChannels> stereo{};
  rex::audio::conversion::sequential_6_BE_to_interleaved_2_LE(
      stereo.data(), guest_samples, guest_frame_count);
  const float gain = output->output_gain;
  for (float& sample : stereo) {
    sample = std::isfinite(sample) ? SoftLimit(sample * gain) : sample;
  }

  std::lock_guard lock(output->producer_mutex);
  const uint64_t read = output->read_frame.load(std::memory_order_acquire);
  const uint64_t write = output->write_frame.load(std::memory_order_relaxed);
  if (write - read + guest_frame_count > kRingFrames) {
    output->dropped_blocks.fetch_add(1, std::memory_order_relaxed);
    return false;
  }
  for (size_t frame = 0; frame < guest_frame_count; ++frame) {
    const size_t destination = ((write + frame) % kRingFrames) * kChannels;
    output->ring[destination] = stereo[frame * 2];
    output->ring[destination + 1] = stereo[frame * 2 + 1];
  }
  output->write_frame.store(write + guest_frame_count,
                            std::memory_order_release);

  const uint64_t submitted =
      output->submitted_blocks.fetch_add(1, std::memory_order_relaxed) + 1;
  const uint64_t underruns =
      output->underrun_frames.load(std::memory_order_relaxed);
  const uint64_t rebuffers =
      output->rebuffer_events.load(std::memory_order_relaxed);
  const uint64_t dropped =
      output->dropped_blocks.load(std::memory_order_relaxed);
  const bool counters_changed =
      underruns != output->logged_underrun_frames ||
      rebuffers != output->logged_rebuffer_events ||
      dropped != output->logged_dropped_blocks;
  if (submitted <= 4 || submitted % 1024 == 0 ||
      counters_changed) {
    float peak = 0.0f;
    for (float sample : stereo) peak = std::max(peak, std::abs(sample));
    REXLOG_INFO(
        "[Theft4Audio] blocks={} peak={:.6f} queued_frames={} "
        "requested={} underrun_frames={} rebuffers={} dropped={} "
        "clipped={} nonfinite={} rendered_frames={} recovery_silence_frames={} "
        "startup_silence_frames={}",
        submitted, peak, write + guest_frame_count - read,
        output->requested_blocks.load(std::memory_order_relaxed), underruns,
        rebuffers, dropped,
        output->clipped_samples.load(std::memory_order_relaxed),
        output->nonfinite_samples.load(std::memory_order_relaxed),
        output->rendered_frames.load(std::memory_order_relaxed),
        output->recovery_silence_frames.load(std::memory_order_relaxed),
        output->startup_silence_frames.load(std::memory_order_relaxed));
    output->logged_underrun_frames = underruns;
    output->logged_rebuffer_events = rebuffers;
    output->logged_dropped_blocks = dropped;
  }
  return true;
}

uint64_t theft4_ios_audio_output_requested_blocks(
    const theft4_ios_audio_output* output) {
  return output ? output->requested_blocks.load(std::memory_order_acquire) : 0;
}
