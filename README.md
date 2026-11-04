<p align="center">
  <img src="docs/images/theft4-logo.png" alt="Theft4" width="640">
</p>

<p align="center">
  <a href="https://github.com/flyingsquirrel0419/Theft4/actions/workflows/ios-build.yml"><img src="https://github.com/flyingsquirrel0419/Theft4/actions/workflows/ios-build.yml/badge.svg?branch=main" alt="iOS build"></a>
  <a href="https://github.com/flyingsquirrel0419/Theft4/actions/workflows/repo-checks.yml"><img src="https://github.com/flyingsquirrel0419/Theft4/actions/workflows/repo-checks.yml/badge.svg?branch=main" alt="Repo checks"></a>
  <a href="https://github.com/flyingsquirrel0419/Theft4/releases/latest"><img src="https://img.shields.io/github/v/release/flyingsquirrel0419/Theft4?label=release" alt="Latest release"></a>
</p>

# Theft4 (fork)

This is a fork of [KoreanSeats1/Theft4](https://github.com/KoreanSeats1/Theft4). Theft4
is an ahead-of-time (AOT) recompilation of the Xbox 360 version of Grand Theft Auto IV
for ARM64 iOS and iPadOS. It does not need a JIT: the PowerPC game code is translated
to C++ ahead of time and compiled into the app.

The fork tracks upstream and adds:

- **A fix for the crash on the first mission.** The game crashed with
  `InvalidFunctionTrap`/SIGABRT while loading *The Cousins Bellic*. The cause was a
  missing `game/update/` folder: Title Update 8 ships the `water_e2` shader that this
  mission needs, and without it the game made an uninitialized render-state call.
  **Check Game Files** now names any TU8 file that is missing or has the wrong size.
- **Crash diagnostics in the field.** A fatal trap writes the registers and the guest
  call chain to `startup/fatal-report.log`, and the log export includes that file.
  Release builds keep no other log.
- **A redesigned launcher.** A floating tab bar in portrait and a navigation rail in
  landscape and on iPad. Settings are grouped into cards, a status pill is always
  visible, and the launcher tells you why an action can't run instead of silently
  doing nothing. *(work in progress on `redesign/launcher-and-fixes`)*
- **Audio fixes.** Sound stops in the background, including under LiveContainer, and
  survives route changes such as plugging in headphones or connecting AirPods, and
  interruptions such as calls or Siri. A **Game volume** setting adds make-up gain with
  a soft limiter, so the game is no longer too quiet on headphones.
- **CI that builds the IPA.** Each push builds an unsigned IPA on GitHub Actions,
  launcher screenshots come from the iOS Simulator, and pushing a tag publishes a
  release.

## Download

Get the unsigned IPA from **[Releases](https://github.com/flyingsquirrel0419/Theft4/releases/latest)**
and install it with a sideloading tool: LiveContainer, SideStore, AltStore or your
own signing. The IPA contains no game data.

## Game files

You need your own legally obtained Xbox 360 copy: the USA retail base game and
**Title Update 8**. Copy the prepared files into the app's `game` folder:

```
game/
├── default.xex          # base or TU8-patched executable (+ default.xexp if not pre-patched)
├── common.rpf  xbox360.rpf  audio.rpf
├── common/  xbox360/  audio/
└── update/              # REQUIRED – contents of the TU8 package (update.img, shaders/, text/, …)
```

If `update/` is missing, the game crashes as soon as the first mission loads. After
copying the files, open **System → Verify Game Files**.

**LiveContainer:** the app's `Documents` folder is inside LiveContainer's data
folder, not under a "Theft4" entry in Files. Look for it under
*Files → On My iPhone → LiveContainer → Data → Application → …*, or use the
share sheet that appears after **Export Saves**.

The full walkthrough is in [docs/IOS_SIDELOAD_INSTALL.md](docs/IOS_SIDELOAD_INSTALL.md).

## In game

- **Tap with three fingers** to open the game menu (toggle touch controls, or quit).
- Graphics, mods and sound settings apply the next time the game launches. The
  recompiled runtime starts once per app session, so to change them, quit and
  reopen the app.

## Building

| Workflow | What it does |
| --- | --- |
| [`iOS · Build IPA`](.github/workflows/ios-build.yml) | Builds the pinned MoltenVK, the offline Metal shader libraries and the unsigned IPA (macOS 26 runner, about 2.5 h). |
| [`iOS · Launcher screenshots`](.github/workflows/ios-launcher-screenshots.yml) | Builds the standalone launcher preview for the Simulator and uploads screenshots of every page. |
| [`iOS · Release`](.github/workflows/ios-release.yml) | Runs when a `v*` tag is pushed: builds the IPA and publishes a GitHub release. Tags containing `-` become pre-releases. |
| [`Repo · Setup checks`](.github/workflows/repo-checks.yml) | Runs the setup-script and release-guard regression tests. |

To build locally on a Mac, see [docs/IOS_RELEASE_BUILD.md](docs/IOS_RELEASE_BUILD.md)
and `tools/build_ios_release.sh`. The CI variant is `tools/ci_build_ios_ipa.sh`.

## Credits

All the real work is upstream:

- [Theft4](https://github.com/KoreanSeats1/Theft4). See its original README in
  [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md), and consider
  [supporting the upstream developer](https://www.paypal.com/donate/?hosted_button_id=XSBF9HXAS89EL).
- [LibertyRecomp](https://github.com/OZORDI/LibertyRecomp)
- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk)

This repository contains no game files, ISOs, title updates or Rockstar Games code.
Grand Theft Auto IV is a trademark of Take-Two Interactive. This project is not
affiliated with or endorsed by Rockstar Games or Take-Two. For licenses, see
[COPYING](COPYING) and [docs/ATTRIBUTION.md](docs/ATTRIBUTION.md).
