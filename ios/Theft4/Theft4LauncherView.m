#import "Theft4LauncherView.h"
#ifdef THEFT4_BC_TEXTURE_COMPATIBILITY
#import "Theft4TextureSources.h"
#endif
#import "Theft4CityView.h"
#include "theft4_output_policy.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#import <QuartzCore/QuartzCore.h>

// Launcher 2 ("Night Shift"): a full-bleed city backdrop, grouped settings
// cards, a floating tab bar in portrait and a navigation rail in landscape.

#ifdef THEFT4_DIRECT_METAL_DEFAULT
static NSString *const kOptimizedDistanceDescription = @"Optimized draws world objects to 0.70× distance and keeps the game's LOD transitions.";
static NSString *const kOptimizedDistanceMetrics = @"0.70× world distance";
#else
static NSString *const kOptimizedDistanceDescription = @"Optimized draws to 0.70× distance and culls far local light volumes.";
static NSString *const kOptimizedDistanceMetrics = @"0.70× world distance · far local lights reduced";
#endif

static UIColor *Ink(unsigned rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                           green:((rgb >> 8) & 255) / 255.0
                            blue:(rgb & 255) / 255.0 alpha:1];
}

// Palette.
static UIColor *Background(void) { return Ink(0x07080C); }
static UIColor *Surface(void) { return [Ink(0x14161E) colorWithAlphaComponent:.90]; }
static UIColor *Hairline(void) { return [UIColor colorWithWhite:1 alpha:.08]; }
static UIColor *TextPrimary(void) { return Ink(0xF5F3EF); }
static UIColor *TextSecondary(void) { return Ink(0xA2A7B3); }
static UIColor *TextTertiary(void) { return Ink(0x6D7383); }
static UIColor *Accent(void) { return Ink(0xFF4D7D); }
static UIColor *AccentSoft(void) { return [Ink(0xFF4D7D) colorWithAlphaComponent:.16]; }
static UIColor *Cyan(void) { return Ink(0x48D7FF); }

static UIFont *Scaled(UIFont *font, UIFontTextStyle style) {
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:font];
}

static UILabel *Text(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = Scaled([UIFont systemFontOfSize:size weight:weight], UIFontTextStyleBody);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    return label;
}

static UILabel *Mono(NSString *text, CGFloat size, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = Scaled([UIFont monospacedSystemFontOfSize:size weight:UIFontWeightMedium],
                        UIFontTextStyleFootnote);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    return label;
}

// Small, letter-spaced section heading shown above a card.
static UILabel *SectionHeading(NSString *text) {
    UILabel *label = [UILabel new];
    label.attributedText = [[NSAttributedString alloc] initWithString:text.uppercaseString attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightBold],
        NSKernAttributeName: @1.4,
        NSForegroundColorAttributeName: TextTertiary()}];
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    return label;
}

static UILabel *Footnote(NSString *text) {
    UILabel *label = Text(text, 12, UIFontWeightRegular, TextTertiary());
    return label;
}

static UIStackView *Column(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    return stack;
}

typedef NS_ENUM(NSInteger, Theft4ButtonStyle) {
    Theft4ButtonStylePrimary,
    Theft4ButtonStyleSecondary,
    Theft4ButtonStyleDestructive,
};

static UIButton *Action(NSString *title, NSString *symbol, Theft4ButtonStyle style) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = style == Theft4ButtonStylePrimary
        ? [UIButtonConfiguration filledButtonConfiguration]
        : [UIButtonConfiguration tintedButtonConfiguration];
    config.title = title;
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.baseBackgroundColor = style == Theft4ButtonStylePrimary ? Accent()
        : style == Theft4ButtonStyleDestructive ? Ink(0xFF5A4E) : TextPrimary();
    config.baseForegroundColor = style == Theft4ButtonStylePrimary ? UIColor.whiteColor
        : style == Theft4ButtonStyleDestructive ? Ink(0xFF8A80) : TextPrimary();
    if (symbol) {
        config.image = [UIImage systemImageNamed:symbol];
        config.imagePadding = 10;
        config.preferredSymbolConfigurationForImage =
            [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    }
    config.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
    const CGFloat size = style == Theft4ButtonStylePrimary ? 17 : 15;
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = Scaled([UIFont systemFontOfSize:size weight:UIFontWeightSemibold],
                                              UIFontTextStyleBody);
        return updated;
    };
    button.configuration = config;
    // Dim the whole control while disabled so a locked action is recognizable.
    button.configurationUpdateHandler = ^(UIButton *b) {
        b.alpha = b.enabled ? 1 : .42;
    };
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:
        style == Theft4ButtonStylePrimary ? 58 : 48].active = YES;
    return button;
}

static UISwitch *Toggle(NSString *identifier, UIColor *tint) {
    UISwitch *toggle = [UISwitch new];
    toggle.onTintColor = tint;
    toggle.accessibilityIdentifier = identifier;
    return toggle;
}

static UISegmentedControl *ChoiceControl(NSArray<NSString *> *items, NSString *identifier,
                                         NSString *label, NSString *hint) {
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
    control.selectedSegmentTintColor = Accent();
    control.backgroundColor = [UIColor colorWithWhite:1 alpha:.06];
    const BOOL phone = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
    if (phone) {
        for (NSUInteger i = 0; i < control.numberOfSegments; ++i) {
            if ([[control titleForSegmentAtIndex:i] isEqualToString:@"Optimized"])
                [control setTitle:@"Opt." forSegmentAtIndex:i];
        }
    }
    UIFont *font = Scaled([UIFont systemFontOfSize:phone ? 12 : 13 weight:UIFontWeightSemibold],
                          UIFontTextStyleFootnote);
    [control setTitleTextAttributes:@{NSFontAttributeName: font,
                                      NSForegroundColorAttributeName: TextSecondary()}
                           forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSFontAttributeName: font,
                                      NSForegroundColorAttributeName: UIColor.whiteColor}
                           forState:UIControlStateSelected];
    [control setTitleTextAttributes:@{NSFontAttributeName: font,
                                      NSForegroundColorAttributeName: [TextTertiary() colorWithAlphaComponent:.5]}
                           forState:UIControlStateDisabled];
    control.accessibilityIdentifier = [@"settings." stringByAppendingString:identifier];
    control.accessibilityLabel = label;
    control.accessibilityHint = hint;
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return control;
}

// A grouped card: rows separated by hairlines.
static UIView *Card(NSArray<UIView *> *rows) {
    UIView *card = [UIView new];
    card.backgroundColor = Surface();
    card.layer.cornerRadius = 18;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1;
    card.layer.borderColor = Hairline().CGColor;
    NSMutableArray<UIView *> *items = [NSMutableArray new];
    for (NSUInteger i = 0; i < rows.count; ++i) {
        if (i) {
            UIView *rule = [UIView new];
            rule.backgroundColor = Hairline();
            [rule.heightAnchor constraintEqualToConstant:1].active = YES;
            [items addObject:rule];
        }
        [items addObject:rows[i]];
    }
    UIStackView *stack = Column(items, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]]];
    return card;
}

static UIStackView *Section(NSString *heading, NSArray<UIView *> *rows, NSString *footnote) {
    NSMutableArray<UIView *> *items = [NSMutableArray new];
    if (heading) {
        UIView *inset = [UIView new];
        UILabel *label = SectionHeading(heading);
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [inset addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:inset.topAnchor],
            [label.bottomAnchor constraintEqualToAnchor:inset.bottomAnchor],
            [label.leadingAnchor constraintEqualToAnchor:inset.leadingAnchor constant:6],
            [label.trailingAnchor constraintEqualToAnchor:inset.trailingAnchor constant:-6]]];
        [items addObject:inset];
    }
    [items addObject:Card(rows)];
    if (footnote.length) {
        UIView *inset = [UIView new];
        UILabel *label = Footnote(footnote);
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [inset addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:inset.topAnchor],
            [label.bottomAnchor constraintEqualToAnchor:inset.bottomAnchor],
            [label.leadingAnchor constraintEqualToAnchor:inset.leadingAnchor constant:6],
            [label.trailingAnchor constraintEqualToAnchor:inset.trailingAnchor constant:-6]]];
        [items addObject:inset];
    }
    return Column(items, 8);
}

@implementation Theft4LauncherView {
    Theft4CityView *_city;
    UIView *_atmosphere;
    CAGradientLayer *_shade, *_floor;
    CAEmitterLayer *_rain;
    UILabel *_wordmark, *_edition, *_configuration, *_resolutionSummary;
    UILabel *_shadowMetrics, *_distanceMetrics, *_modelMetrics, *_reflectionMetrics, *_aaMetrics;
    UILabel *_sharpeningMetrics, *_audioMetrics;
    UIView *_statusPill, *_statusDot;
    UIScrollView *_scroll;
    UIStackView *_content;
    UIStackView *_play, *_graphics, *_interfacePage, *_system, *_mods;
    NSArray<UIView *> *_pages;
    NSArray<UIView *> *_lockBanners;
    UIView *_tabBar;
    UIVisualEffectView *_tabBarMaterial;
    UIStackView *_tabStack;
    NSArray<UIButton *> *_tabs;
    UILabel *_notice;
    NSUInteger _noticeGeneration;
    NSInteger _selectedTab;
    BOOL _active, _retired, _railMode, _layoutConfigured;
}

#pragma mark - Construction

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = Background();
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self buildBackdrop];
    [self buildChrome];
    [self buildPages];
    [self buildTabs];

    [self selectTab:_tabs[0]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(motionChanged:)
        name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [self setActive:YES];
    return self;
}

- (void)buildBackdrop {
    _city = [Theft4CityView new];
    [self addSubview:_city];

    _atmosphere = [UIView new];
    _atmosphere.userInteractionEnabled = NO;
    [self addSubview:_atmosphere];
    _shade = [CAGradientLayer layer];
    _floor = [CAGradientLayer layer];
    [_atmosphere.layer addSublayer:_shade];
    [_atmosphere.layer addSublayer:_floor];
    _floor.colors = @[(id)[Background() colorWithAlphaComponent:0].CGColor,
                      (id)[Background() colorWithAlphaComponent:.92].CGColor];
    _floor.startPoint = CGPointMake(.5, 0);
    _floor.endPoint = CGPointMake(.5, 1);

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(2, 22)];
    UIImage *drop = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        [[UIColor colorWithWhite:1 alpha:.5] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 1, 22) cornerRadius:.5] fill];
    }];
    CAEmitterCell *rain = [CAEmitterCell emitterCell];
    rain.contents = (id)drop.CGImage;
    rain.birthRate = 22;
    rain.lifetime = 5;
    rain.velocity = 190;
    rain.velocityRange = 60;
    rain.emissionLongitude = M_PI_2 + .12;
    rain.scale = .7;
    rain.scaleRange = .4;
    rain.color = [Cyan() colorWithAlphaComponent:.10].CGColor;
    _rain = [CAEmitterLayer layer];
    _rain.emitterShape = kCAEmitterLayerLine;
    _rain.emitterCells = @[rain];
    [_atmosphere.layer addSublayer:_rain];
}

- (void)buildChrome {
    _wordmark = [UILabel new];
    _wordmark.accessibilityLabel = @"Theft four";
    _wordmark.adjustsFontSizeToFitWidth = YES;
    _wordmark.minimumScaleFactor = .6;
    [self addSubview:_wordmark];

    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = info[@"Theft4ReleaseName"] ?: @"0.3";
    NSString *build = info[@"CFBundleVersion"] ?: @"0";
    _edition = Mono([NSString stringWithFormat:@"v%@ (%@)", version, build], 11, TextTertiary());
    _edition.numberOfLines = 1;
    _edition.textAlignment = NSTextAlignmentRight;
    [self addSubview:_edition];

    _statusPill = [UIView new];
    _statusPill.backgroundColor = [Ink(0x14161E) colorWithAlphaComponent:.82];
    _statusPill.layer.cornerRadius = 14;
    _statusPill.layer.cornerCurve = kCACornerCurveContinuous;
    _statusPill.layer.borderWidth = 1;
    _statusPill.layer.borderColor = Hairline().CGColor;
    [self addSubview:_statusPill];
    _statusDot = [UIView new];
    _statusDot.backgroundColor = Ink(0x4ADE80);
    _statusDot.layer.cornerRadius = 4;
    [_statusPill addSubview:_statusDot];
    _statusLabel = Text(@"Core ready", 13, UIFontWeightMedium, TextPrimary());
    _statusLabel.numberOfLines = 3;
    _statusLabel.adjustsFontSizeToFitWidth = YES;
    _statusLabel.minimumScaleFactor = .75;
    _statusLabel.accessibilityIdentifier = @"core.status";
    [_statusPill addSubview:_statusLabel];
    [_statusLabel addObserver:self forKeyPath:@"text" options:0 context:NULL];

    _notice = Text(@"", 14, UIFontWeightSemibold, UIColor.whiteColor);
    _notice.textAlignment = NSTextAlignmentCenter;
    _notice.backgroundColor = [Ink(0x262A36) colorWithAlphaComponent:.96];
    _notice.layer.cornerRadius = 16;
    _notice.layer.masksToBounds = YES;
    _notice.alpha = 0;
    _notice.accessibilityIdentifier = @"launcher.notice";
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (object == _statusLabel) {
        [self updateStatusTone];
        [self setNeedsLayout];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)updateStatusTone {
    NSString *text = _statusLabel.text.lowercaseString ?: @"";
    UIColor *tone = Ink(0x4ADE80);
    for (NSString *word in @[@"fail", @"error", @"cannot", @"missing", @"invalid", @"not "]) {
        if ([text containsString:word]) { tone = Ink(0xFF6B6B); break; }
    }
    if ([tone isEqual:Ink(0x4ADE80)]) {
        for (NSString *word in @[@"copy", @"select", @"verify", @"prepar", @"loading", @"checking", @"waiting"]) {
            if ([text containsString:word]) { tone = Ink(0xFBBF24); break; }
        }
    }
    _statusDot.backgroundColor = tone;
}

- (UIView *)toggleRow:(NSString *)title detail:(NSString *)detail toggle:(UISwitch *)toggle {
    UILabel *label = Text(title, 16, UIFontWeightSemibold, TextPrimary());
    UIStackView *text = detail.length
        ? Column(@[label, Text(detail, 13, UIFontWeightRegular, TextSecondary())], 3)
        : Column(@[label], 0);
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[text, toggle]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 14;
    toggle.accessibilityLabel = title;
    toggle.accessibilityHint = detail;
    [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [toggle setContentCompressionResistancePriority:UILayoutPriorityRequired
                                            forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

- (UIView *)choiceRow:(NSString *)title detail:(NSString *)detail
              control:(UIControl *)control metrics:(UILabel *)metrics {
    UILabel *label = Text(title, 16, UIFontWeightSemibold, TextPrimary());
    NSMutableArray<UIView *> *items = [NSMutableArray arrayWithObject:label];
    if (metrics) {
        metrics.textColor = Accent();
        UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[label]];
        [items removeAllObjects];
        [items addObject:head];
    }
    [items addObject:control];
    if (metrics) [items addObject:metrics];
    if (detail.length) [items addObject:Text(detail, 13, UIFontWeightRegular, TextSecondary())];
    return Column(items, 8);
}

- (UIView *)lockBanner {
    UILabel *label = Text(@"Applies to the next fresh launch. Quit the game and reopen Theft4 to change these settings.",
                          13, UIFontWeightMedium, Ink(0xFBBF24));
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.tintColor = Ink(0xFBBF24);
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    row.spacing = 10;
    row.alignment = UIStackViewAlignmentCenter;
    row.layoutMargins = UIEdgeInsetsMake(12, 14, 12, 14);
    row.layoutMarginsRelativeArrangement = YES;
    row.backgroundColor = [Ink(0xFBBF24) colorWithAlphaComponent:.12];
    row.layer.cornerRadius = 14;
    row.layer.borderWidth = 1;
    row.layer.borderColor = [Ink(0xFBBF24) colorWithAlphaComponent:.35].CGColor;
    row.hidden = YES;
    return row;
}

- (UIView *)pageHeader:(NSString *)title subtitle:(NSString *)subtitle {
    UILabel *heading = Text(title, 30, UIFontWeightHeavy, TextPrimary());
    heading.accessibilityTraits = UIAccessibilityTraitHeader;
    return Column(@[heading, Text(subtitle, 15, UIFontWeightRegular, TextSecondary())], 4);
}

- (void)buildPages {
    const BOOL lab = [NSBundle.mainBundle.infoDictionary[@"Theft4LabBuild"] boolValue];
    NSString *displayName = NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: @"Theft4";

    // ---- Play ----
    UILabel *tagline = SectionHeading(@"Liberty City · After Dark");
    tagline.textColor = Accent();
    UILabel *headline = Text(@"One more night\nin Liberty City.", 34, UIFontWeightHeavy, TextPrimary());
    UILabel *intro = Text(@"Cross the river. Take the long way home. Continue or begin a new story inside the game.",
                          15, UIFontWeightRegular, TextSecondary());
    _startButton = Action(@"Play", @"play.fill", Theft4ButtonStylePrimary);
    {
        UIButtonConfiguration *config = _startButton.configuration;
        config.subtitle = @"Enter Liberty City";
        config.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
        config.imagePlacement = NSDirectionalRectEdgeTrailing;
        config.contentInsets = NSDirectionalEdgeInsetsMake(16, 20, 16, 20);
        config.subtitleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            updated[NSForegroundColorAttributeName] = [UIColor colorWithWhite:1 alpha:.8];
            return updated;
        };
        _startButton.configuration = config;
        _startButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    }
    _startButton.accessibilityIdentifier = @"game.start";
    _startButton.layer.shadowColor = Accent().CGColor;
    _startButton.layer.shadowOpacity = .45;
    _startButton.layer.shadowRadius = 18;
    _startButton.layer.shadowOffset = CGSizeMake(0, 6);
    _configuration = Mono(@"", 12, TextSecondary());
    UILabel *setupTitle = Text(@"Current setup", 15, UIFontWeightSemibold, TextPrimary());
    UIView *setupCard = Card(@[Column(@[setupTitle, _configuration], 4),
        Text(@"Your saves stay with this app. Change graphics, sound and mods in the other tabs before you press Play.",
             13, UIFontWeightRegular, TextSecondary())]);
    _play = Column(@[Column(@[tagline, headline, intro], 8), _startButton, setupCard], 22);
    [_play setCustomSpacing:28 afterView:_play.arrangedSubviews.firstObject];

    // ---- Graphics ----
    _showCPUUsage = Toggle(@"settings.showCPUUsage", Accent());
    _showFrameTime = Toggle(@"settings.showFrameTime", Accent());
    _showFPS = Toggle(@"settings.showFPS", Accent());
    _showControls = Toggle(@"settings.showTouchControls", Accent());
    _anisotropicFiltering = Toggle(@"settings.anisotropicFiltering", Accent());
    _enhancedOutput = Toggle(@"settings.enhancedOutput1080p", Accent());
    _fsrBoost = Toggle(@"settings.fsrBoost", Accent());
    _motionBlur = Toggle(@"settings.motionBlur", Accent());
    _depthOfField = Toggle(@"settings.depthOfField", Accent());

    NSMutableArray<UIView *> *graphics = [NSMutableArray arrayWithObject:
        [self pageHeader:@"Graphics" subtitle:@"Image and world quality"]];
    UIView *graphicsLock = [self lockBanner];
    [graphics addObject:graphicsLock];

    if (lab) {
        _lowPowerButton = Action(@"Auto Optimize", @"wand.and.stars", Theft4ButtonStyleSecondary);
        _lowPowerButton.accessibilityIdentifier = @"settings.autoOptimize";
        _lowPowerButton.accessibilityLabel = @"Auto Optimize for this device";
        _originalPresetButton = Action(@"Original 360", @"gamecontroller", Theft4ButtonStyleSecondary);
        _originalPresetButton.accessibilityIdentifier = @"settings.originalPreset";
        _originalPresetButton.accessibilityLabel = @"Original Xbox 360 settings";
        _frameSpeedButton = Action(@"Frame Speed", @"bolt.fill", Theft4ButtonStyleSecondary);
        _frameSpeedButton.accessibilityIdentifier = @"settings.frameSpeed";
        _restoreGraphicsButton = Action(@"Restore Previous", @"arrow.uturn.backward", Theft4ButtonStyleSecondary);
        _restoreGraphicsButton.accessibilityIdentifier = @"settings.restorePreviousGraphics";
        UIStackView *presetsTop = [[UIStackView alloc] initWithArrangedSubviews:@[_lowPowerButton, _originalPresetButton]];
        UIStackView *presetsBottom = [[UIStackView alloc] initWithArrangedSubviews:@[_frameSpeedButton, _restoreGraphicsButton]];
        for (UIStackView *row in @[presetsTop, presetsBottom]) {
            row.distribution = UIStackViewDistributionFillEqually;
            row.spacing = 10;
        }
        [graphics addObject:Section(@"Presets", @[Column(@[presetsTop, presetsBottom], 10)],
            @"Auto Optimize picks a starting profile for this device. Original restores the Xbox 360 look. Frame Speed keeps your resolution and trims the heavy effects. You can adjust each setting afterward.")];

        _renderResolution = ChoiceControl(@[@"540p", @"720p", @"900p", @"1080p", @"Native"], @"renderResolution",
            @"Render resolution", @"The internal scene resolution. Applies at the next game launch.");
        _renderResolution.selectedSegmentIndex = 1;
        _fsrUpscaling = Toggle(@"settings.fsrUpscaling", Accent());
        _resolutionSummary = Mono(@"", 12, Accent());
        _resolutionSummary.accessibilityIdentifier = @"settings.resolutionSummary";
    }
    NSMutableArray<UIView *> *resolutionRows = [NSMutableArray new];
    if (_renderResolution) {
        [resolutionRows addObject:[self choiceRow:@"Internal resolution"
            detail:@"Centered 16:9 unless Native Aspect Ratio is on. Native uses physical pixels and disables FSR."
            control:_renderResolution metrics:_resolutionSummary]];
        const char *profile = getenv("THEFT4_DEVICE_PROFILE") ?: "";
        const BOOL fixed1080 = strcmp(profile, "a19") == 0 || strcmp(profile, "iphone-6gb") == 0 ||
                               strcmp(profile, "legacy-ipad") == 0;
        [resolutionRows addObject:[self toggleRow:@"FSR upscaling" detail:fixed1080
            ? @"This device uses a fixed 1080p output. Lower internal resolutions use FSR 1."
            : @"Off bypasses FSR 1 and keeps the selected scene resolution." toggle:_fsrUpscaling]];
    } else {
        [resolutionRows addObject:[self toggleRow:@"1080p enhanced output"
            detail:@"FSR 1 upscale plus sharpening." toggle:_enhancedOutput]];
        [resolutionRows addObject:[self toggleRow:@"Experimental FSR boost"
            detail:@"Native-pixel 16:9 output while keeping the 720p scene." toggle:_fsrBoost]];
    }
#ifdef THEFT4_DIRECT_METAL_DEFAULT
    _sharpening = [UISlider new];
    _sharpening.minimumValue = 0;
    _sharpening.maximumValue = 100;
    _sharpening.minimumTrackTintColor = Accent();
    _sharpening.accessibilityIdentifier = @"settings.sharpening";
    _sharpening.accessibilityLabel = @"Sharpening strength";
    _sharpening.accessibilityHint = @"Zero disables sharpening. Changes apply on the next game launch.";
    [_sharpening.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    [_sharpening addTarget:self action:@selector(refreshConfigurationSummary)
          forControlEvents:UIControlEventValueChanged];
    _sharpeningMetrics = Mono(@"OFF · 0%", 12, Accent());
    [resolutionRows addObject:[self choiceRow:@"Sharpening"
        detail:@"Fine-detail contrast. Higher values add GPU work and can emphasize texture noise."
        control:_sharpening metrics:_sharpeningMetrics]];
#endif
    [graphics addObject:Section(@"Resolution", resolutionRows, nil)];

    _shadowQuality = ChoiceControl(@[@"Optimized", @"Original", @"Enhanced", @"Ultra"], @"shadowQuality",
        @"Dynamic shadows", @"Optimized is pending validation of distant shadow cache reuse.");
    [_shadowQuality setEnabled:NO forSegmentAtIndex:0];
    _drawDistance = ChoiceControl(@[@"Optimized", @"Original", @"2×", @"3×"], @"drawDistance",
        @"Draw distance", @"Optimized reduces world distance and distant local illumination.");
    _modelDetail = ChoiceControl(@[@"Lower", @"Original", @"Highest"], @"modelDetail",
        @"Model detail", @"Lower selects simpler resident meshes sooner without changing draw distance.");
    _reflectionQuality = ChoiceControl(@[@"Original", @"1080p", @"Full"], @"reflectionQuality",
        @"Reflection resolution", @"Set the renderer's native reflection target preset.");
    _antiAliasing = ChoiceControl(@[@"Off", @"FXAA", @"SMAA"], @"antiAliasing",
        @"Anti-aliasing", @"Select the native renderer's edge smoothing mode.");
    _shadowMetrics = Mono(@"", 12, Accent());
    _distanceMetrics = Mono(@"", 12, Accent());
    _modelMetrics = Mono(@"", 12, Accent());
    _reflectionMetrics = Mono(@"", 12, Accent());
    _aaMetrics = Mono(@"", 12, Accent());
    for (UISegmentedControl *choice in @[_shadowQuality, _drawDistance, _modelDetail,
                                         _reflectionQuality, _antiAliasing]) {
        [choice addTarget:self action:@selector(refreshConfigurationSummary)
         forControlEvents:UIControlEventValueChanged];
    }
    [graphics addObject:Section(@"World", @[
        [self choiceRow:@"Dynamic shadows" detail:@"Optimized stays locked until distant shadow cache reuse is verified."
                control:_shadowQuality metrics:_shadowMetrics],
        [self choiceRow:@"Draw distance" detail:kOptimizedDistanceDescription
                control:_drawDistance metrics:_distanceMetrics],
        [self choiceRow:@"Model detail" detail:@"Lower switches to simpler resident meshes sooner. Highest prefers the best resident mesh."
                control:_modelDetail metrics:_modelMetrics],
        [self choiceRow:@"Reflections" detail:@"Mirror and water targets and the environment cubemap. Full is capped at 1440p."
                control:_reflectionQuality metrics:_reflectionMetrics],
    ], @"Extended distance and Ultra shadows can reduce frame rate in dense areas.")];
    [graphics addObject:Section(@"Image", @[
        [self choiceRow:@"Anti-aliasing" detail:nil control:_antiAliasing metrics:_aaMetrics],
        [self toggleRow:@"Texture filtering 4×" detail:@"Cleaner roads and surfaces at an angle." toggle:_anisotropicFiltering],
        [self toggleRow:@"Motion blur" detail:@"The original movement blur." toggle:_motionBlur],
        [self toggleRow:@"Depth of field" detail:@"Distance-based focus blur." toggle:_depthOfField],
    ], @"Graphics changes apply on the next game launch.")];
    _graphics = Column(graphics, 22);

    // ---- Interface & sound ----
    _audioVolume = ChoiceControl(@[@"Original", @"Boost", @"Max"], @"audioVolume",
        @"Game volume", @"Raises the game's mix for headphones and the speaker.");
    _audioVolume.selectedSegmentIndex = 1;
    [_audioVolume addTarget:self action:@selector(refreshConfigurationSummary)
           forControlEvents:UIControlEventValueChanged];
    _audioMetrics = Mono(@"", 12, Accent());
    UIView *interfaceLock = [self lockBanner];
    _interfacePage = Column(@[
        [self pageHeader:@"Interface" subtitle:@"HUD, controls and sound"],
        Section(@"Overlays", @[
            [self toggleRow:@"Frame counter" detail:@"Unique game frames, top-right." toggle:_showFPS],
            [self toggleRow:@"Frame-time graph"
                     detail:@"Frame delivery against the 33.3 ms target. Hold the graph to mark a spike or save a capture."
                     toggle:_showFrameTime],
            [self toggleRow:@"CPU / thread graph" detail:@"Device-core and game-thread activity, once per second."
                     toggle:_showCPUUsage],
        ], nil),
        Section(@"Controls", @[
            [self toggleRow:@"Touch controls" detail:@"Physical controllers keep working when the overlay is hidden."
                     toggle:_showControls],
        ], @"A connected controller can move through this launcher: D-pad or left stick to navigate, A to select. In game, tap with three fingers for the game menu."),
        interfaceLock,
        Section(@"Sound", @[
            [self choiceRow:@"Game volume"
                     detail:@"The 5.1 to stereo downmix is quiet on headphones. Boost adds make-up gain with a soft limiter so loud scenes do not distort."
                    control:_audioVolume metrics:_audioMetrics],
        ], @"Applies on the next game launch. Game audio pauses while Theft4 is in the background."),
    ], 22);

    // ---- System ----
    _prepareButton = Action(@"Verify Game Files", @"checkmark.shield", Theft4ButtonStyleSecondary);
    _prepareButton.accessibilityIdentifier = @"game.prepare";
    _restartButton = Action(@"Restart Core Probe", @"arrow.clockwise", Theft4ButtonStyleSecondary);
    _restartButton.accessibilityIdentifier = @"core.restart";
    _skipIntro = Toggle(@"settings.skipIntro", Cyan());
    _performanceCapture = Toggle(@"settings.performanceCapture", Accent());
    _downloadLogButton = Action(@"Export Latest Log Capture", @"square.and.arrow.down", Theft4ButtonStyleSecondary);
    _downloadLogButton.accessibilityIdentifier = @"diagnostics.downloadLatestCapture";
    _exportSavesButton = Action(@"Export Saves to Files", @"square.and.arrow.up", Theft4ButtonStyleSecondary);
    _exportSavesButton.accessibilityIdentifier = @"saves.export";
    _importSavesButton = Action(@"Import Saves from Files", @"tray.and.arrow.down", Theft4ButtonStyleSecondary);
    _importSavesButton.accessibilityIdentifier = @"saves.import";
    _detailLabel = Mono(@"Waiting for runtime information…", 12, TextSecondary());
    _detailLabel.accessibilityIdentifier = @"core.details";

    NSMutableArray<UIView *> *system = [NSMutableArray arrayWithObject:
        [self pageHeader:@"System" subtitle:@"Game files, saves and diagnostics"]];
    // Restart is hidden in retail builds; keep it in the same row as Verify so
    // hiding it does not leave an empty, divider-framed slot.
    [system addObject:Section(@"Game files", @[Column(@[_prepareButton, _restartButton], 10), _detailLabel],
        [NSString stringWithFormat:@"%@ creates a game folder in its Files folder (On My iPhone/iPad → %@; under LiveContainer, inside LiveContainer's app data). Copy the prepared game folder's contents, including update/, into game, then verify.",
            displayName, displayName])];
#ifdef THEFT4_BC_TEXTURE_COMPATIBILITY
    _astcConversion = Toggle(@"settings.astcConversion", Cyan());
    _deleteTextureCacheButton = Action(@"Delete Prepared Texture Cache", @"trash", Theft4ButtonStyleDestructive);
    _deleteTextureCacheButton.accessibilityIdentifier = @"settings.deleteTextureCache";
    BOOL showTextureCompatibility = Theft4DeviceNeedsBCTexturePreparation();
#ifdef THEFT4_ASTC_EXPERIMENT
    showTextureCompatibility = YES;
#endif
    if (showTextureCompatibility) {
        [system addObject:Section(@"Textures", @[
            [self toggleRow:@"ASTC texture compatibility"
                     detail:@"One-time setup for this GPU. Saves compressed ASTC copies so later launches skip texture conversion."
                     toggle:_astcConversion],
            _deleteTextureCacheButton,
        ], @"Deleting the cache keeps your game files and saves. Devices that need ASTC must prepare textures again before Play.")];
    }
#endif
    [system addObject:Section(@"Startup", @[
        [self toggleRow:@"Skip intro videos" detail:@"Skip the opening credits and logos. Loading still completes normally."
                 toggle:_skipIntro],
    ], nil)];
    [system addObject:Section(@"Save transfer", @[_exportSavesButton, _importSavesButton],
        @"Exports go to Files → Theft4 → Save Exports. Import only while the game is closed; current saves are backed up first.")];
    [system addObject:Section(@"Diagnostics", @[
        [self toggleRow:@"Long performance capture"
                 detail:@"Off each time the app opens. Records up to 5 minutes of timing during play; saves when the app goes to the background."
                 toggle:_performanceCapture],
        _downloadLogButton,
    ], @"Exports the latest capture, lifecycle log and crash report to Files → Theft4 → Diagnostics.")];
    _system = Column(system, 22);

    // ---- Mods ----
    _customTimeCycle = Toggle(@"mods.customTimeCycle", Cyan());
    _nativeAspect = Toggle(@"mods.nativeAspect", Cyan());
    [_nativeAspect addTarget:self action:@selector(refreshConfigurationSummary)
            forControlEvents:UIControlEventValueChanged];
    _godMode = Toggle(@"mods.godMode", Cyan());
    _unlimitedAmmo = Toggle(@"mods.unlimitedAmmo", Cyan());

    NSString *previewPath = [NSBundle.mainBundle pathForResource:@"preview" ofType:@"jpg"
                                                     inDirectory:@"Mods/CustomTimeCycle"];
    UIImageView *preview = [[UIImageView alloc] initWithImage:
        previewPath ? [UIImage imageWithContentsOfFile:previewPath] : nil];
    preview.contentMode = UIViewContentModeScaleAspectFill;
    preview.backgroundColor = UIColor.blackColor;
    preview.layer.cornerRadius = 12;
    preview.layer.cornerCurve = kCACornerCurveContinuous;
    preview.clipsToBounds = YES;
    preview.isAccessibilityElement = YES;
    preview.accessibilityLabel = @"Custom Time Cycle example: a bright Liberty City street with a clear blue sky.";
    preview.accessibilityIdentifier = @"mods.customTimeCycle.preview";
    [preview.widthAnchor constraintEqualToConstant:120].active = YES;
    [preview.heightAnchor constraintEqualToConstant:90].active = YES;
    NSString *metadataPath = [NSBundle.mainBundle pathForResource:@"metadata" ofType:@"plist"
                                                      inDirectory:@"Mods/CustomTimeCycle"];
    NSDictionary *metadata = metadataPath ? [NSDictionary dictionaryWithContentsOfFile:metadataPath] : nil;
    NSString *developer = [metadata[@"Developer"] isKindOfClass:NSString.class]
        ? [metadata[@"Developer"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    UILabel *credit = Text(developer.length
        ? [NSString stringWithFormat:@"Time cycle by %@. Thank you!", developer]
        : @"Developer credit coming soon.", 13, UIFontWeightMedium, TextPrimary());
    credit.accessibilityIdentifier = @"mods.customTimeCycle.developerCredit";
    UIStackView *example = [[UIStackView alloc] initWithArrangedSubviews:@[preview,
        Column(@[SectionHeading(@"Lighting preview"),
                 Text(@"Appearance varies with weather, time of day and your graphics settings.",
                      13, UIFontWeightRegular, TextSecondary()), credit], 5)]];
    example.spacing = 14;
    example.alignment = UIStackViewAlignmentCenter;

    UIView *modsLock = [self lockBanner];
    _mods = Column(@[
        [self pageHeader:@"Mods" subtitle:@"Make Liberty City your own"],
        modsLock,
        Section(@"Atmosphere", @[
            [self toggleRow:@"Custom time cycle"
                     detail:@"Bundled lighting, sky, fog and weather replacement. Off uses the original game file."
                     toggle:_customTimeCycle],
            example,
        ], nil),
        Section(@"View", @[
            [self toggleRow:@"Native aspect ratio"
                     detail:@"Fill your screen with extra scenery without stretching or cropping. The HUD keeps its proportions."
                     toggle:_nativeAspect],
        ], @"The view follows the window shape when you press Play. Extra scenery can cost performance; videos keep their original shape."),
        Section(@"Gameplay", @[
            [self toggleRow:@"God mode"
                     detail:@"No player damage or death from bullets, explosions, fire, collisions or drowning."
                     toggle:_godMode],
            [self toggleRow:@"Unlimited ammo"
                     detail:@"Reserve ammo stays full. Magazines still empty and you reload normally. No weapons granted."
                     toggle:_unlimitedAmmo],
        ], @"Choose before Play. Replenished ammo can be saved; turning the mod off restores normal consumption."),
    ], 22);

    _lockBanners = @[graphicsLock, interfaceLock, modsLock];
    _pages = @[_play, _graphics, _interfacePage, _system, _mods];

    _scroll = [UIScrollView new];
    _scroll.showsVerticalScrollIndicator = YES;
    _scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _scroll.alwaysBounceVertical = YES;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self addSubview:_scroll];
    _content = Column(_pages, 0);
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_content];
    [NSLayoutConstraint activateConstraints:@[
        [_content.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [_content.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [_content.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_content.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_content.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
    ]];
}

- (void)buildTabs {
    _tabBar = [UIView new];
    _tabBar.backgroundColor = [Ink(0x12141B) colorWithAlphaComponent:.55];
    // Blur the content scrolling underneath so labels never show through.
    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    material.layer.cornerRadius = 26;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.clipsToBounds = YES;
    material.userInteractionEnabled = NO;
    _tabBarMaterial = material;
    _tabBar.layer.cornerRadius = 26;
    _tabBar.layer.cornerCurve = kCACornerCurveContinuous;
    _tabBar.layer.borderWidth = 1;
    _tabBar.layer.borderColor = Hairline().CGColor;
    _tabBar.layer.shadowColor = UIColor.blackColor.CGColor;
    _tabBar.layer.shadowOpacity = .5;
    _tabBar.layer.shadowRadius = 20;
    _tabBar.layer.shadowOffset = CGSizeMake(0, 8);
    [self addSubview:_tabBar];
    _tabBarMaterial.frame = _tabBar.bounds;
    [_tabBar addSubview:_tabBarMaterial];

    NSArray<NSString *> *names = @[@"Play", @"Graphics", @"Interface", @"System", @"Mods"];
    NSArray<NSString *> *symbols = @[@"play.fill", @"slider.horizontal.3", @"speaker.wave.2",
                                     @"externaldrive", @"puzzlepiece.extension"];
    NSMutableArray<UIButton *> *tabs = [NSMutableArray new];
    for (NSInteger i = 0; i < (NSInteger)names.count; ++i) {
        UIButton *tab = [UIButton buttonWithType:UIButtonTypeSystem];
        tab.tag = i;
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = names[i];
        config.image = [UIImage systemImageNamed:symbols[i]];
        config.imagePlacement = NSDirectionalRectEdgeTop;
        config.imagePadding = 4;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.preferredSymbolConfigurationForImage =
            [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
        config.contentInsets = NSDirectionalEdgeInsetsMake(6, 2, 6, 2);
        config.titleLineBreakMode = NSLineBreakByClipping;
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
            return updated;
        };
        tab.configuration = config;
        tab.accessibilityLabel = names[i];
        tab.accessibilityIdentifier = [@"launcher.tab." stringByAppendingFormat:@"%ld", (long)i];
        [tab addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
        [tabs addObject:tab];
    }
    _tabs = tabs;
    _tabStack = [[UIStackView alloc] initWithArrangedSubviews:tabs];
    _tabStack.distribution = UIStackViewDistributionFillEqually;
    _tabStack.spacing = 2;
    [_tabBar addSubview:_tabStack];

    [self addSubview:_notice];
}

#pragma mark - Navigation

- (void)updateTabAppearance {
    for (UIButton *tab in _tabs) {
        const BOOL selected = tab.tag == _selectedTab;
        const BOOL focused = tab.isFocused;
        UIButtonConfiguration *config = tab.configuration;
        config.baseForegroundColor = selected ? UIColor.whiteColor : TextTertiary();
        config.background.backgroundColor = selected ? AccentSoft()
            : focused ? [UIColor colorWithWhite:1 alpha:.10] : UIColor.clearColor;
        config.background.strokeColor = focused ? Accent() : UIColor.clearColor;
        config.background.strokeWidth = focused ? 1.5 : 0;
        if (selected) config.baseForegroundColor = Accent();
        tab.configuration = config;
        tab.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
}

- (void)selectTab:(UIButton *)sender {
    _selectedTab = sender.tag;
    for (NSUInteger i = 0; i < _pages.count; ++i) _pages[i].hidden = (NSInteger)i != sender.tag;
    [self updateTabAppearance];
    [_scroll setContentOffset:CGPointMake(0, -_scroll.contentInset.top) animated:NO];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _pages[sender.tag]);
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{ [self updateTabAppearance]; } completion:nil];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return _startButton.enabled && !_startButton.hidden && _selectedTab == 0
        ? @[_startButton] : @[_tabs[_selectedTab]];
}

#pragma mark - Feedback

- (void)showNotice:(NSString *)message {
    if (!message.length) return;
    _notice.text = [NSString stringWithFormat:@"  %@  ", message];
    const NSUInteger generation = ++_noticeGeneration;
    [self bringSubviewToFront:_notice];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [UIView animateWithDuration:.18 animations:^{ self->_notice.alpha = 1; }];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self->_noticeGeneration) return;
        [UIView animateWithDuration:.3 animations:^{ self->_notice.alpha = 0; }];
    });
}

- (void)setSessionLocked:(BOOL)locked {
    for (UIView *banner in _lockBanners) banner.hidden = !locked;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    const UIEdgeInsets safe = self.safeAreaInsets;
    const BOOL phone = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
    const BOOL railMode = w > h || w >= 700;
    const BOOL wideRail = !phone && w >= 900;

    if (!_layoutConfigured || railMode != _railMode) {
        _layoutConfigured = YES;
        _railMode = railMode;
        _tabStack.axis = railMode ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
        _tabStack.distribution = UIStackViewDistributionFillEqually;
        _tabStack.spacing = railMode ? 6 : 2;
        for (UIButton *tab in _tabs) {
            UIButtonConfiguration *config = tab.configuration;
            config.imagePlacement = railMode && wideRail ? NSDirectionalRectEdgeLeading : NSDirectionalRectEdgeTop;
            config.imagePadding = railMode && wideRail ? 12 : 4;
            config.contentInsets = railMode && wideRail ? NSDirectionalEdgeInsetsMake(12, 16, 12, 16)
                                                        : NSDirectionalEdgeInsetsMake(6, 2, 6, 2);
            const CGFloat titleSize = railMode && wideRail ? 15 : 10;
            config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
                NSMutableDictionary *updated = [attributes mutableCopy];
                updated[NSFontAttributeName] = [UIFont systemFontOfSize:titleSize weight:UIFontWeightSemibold];
                return updated;
            };
            tab.configuration = config;
            tab.contentHorizontalAlignment = railMode && wideRail
                ? UIControlContentHorizontalAlignmentLeading : UIControlContentHorizontalAlignmentCenter;
        }
        [self updateTabAppearance];
    }

    // Backdrop: overscan so an orbit never exposes the scene edge.
    _city.frame = railMode ? CGRectMake(w * .18, -h * .08, w * .95, h * 1.16)
                           : CGRectMake(-w * .25, -h * .04, w * 1.5, h * .62);
    _atmosphere.frame = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shade.frame = self.bounds;
    if (railMode) {
        _shade.colors = @[(id)Background().CGColor,
                          (id)[Background() colorWithAlphaComponent:.90].CGColor,
                          (id)[Background() colorWithAlphaComponent:.25].CGColor,
                          (id)[Background() colorWithAlphaComponent:.05].CGColor];
        _shade.locations = @[@0, @.42, @.78, @1];
        _shade.startPoint = CGPointMake(0, .5);
        _shade.endPoint = CGPointMake(1, .5);
    } else {
        _shade.colors = @[(id)[Background() colorWithAlphaComponent:.25].CGColor,
                          (id)[Background() colorWithAlphaComponent:.55].CGColor,
                          (id)Background().CGColor];
        _shade.locations = @[@0, @.30, @.55];
        _shade.startPoint = CGPointMake(.5, 0);
        _shade.endPoint = CGPointMake(.5, 1);
    }
    _floor.frame = CGRectMake(0, h * .7, w, h * .3);
    _rain.frame = self.bounds;
    _rain.emitterPosition = CGPointMake(w * .66, -24);
    _rain.emitterSize = CGSizeMake(w * .8, 1);
    [CATransaction commit];

    const CGFloat side = MAX(16, MAX(safe.left, safe.right) + (railMode ? 4 : 0));
    const CGFloat top = MAX(16, safe.top + 6);
    const CGFloat bottom = MAX(12, safe.bottom);

    // Navigation.
    CGFloat contentLeft = side, contentBottom;
    if (railMode) {
        const CGFloat railWidth = wideRail ? 210 : 76;
        const CGFloat railHeight = MIN(h - top - bottom, wideRail ? 5 * 52 + 4 * 6 + 20 : 5 * 56 + 4 * 6 + 16);
        _tabBar.frame = CGRectMake(MAX(12, safe.left), top + (h - top - bottom - railHeight) / 2,
                                   railWidth, railHeight);
        _tabStack.frame = CGRectInset(_tabBar.bounds, 8, 8);
        contentLeft = CGRectGetMaxX(_tabBar.frame) + 20;
        contentBottom = h - bottom;
    } else {
        const CGFloat barHeight = 64;
        _tabBar.frame = CGRectMake(side, h - bottom - barHeight - (safe.bottom > 0 ? 0 : 6),
                                   w - 2 * side, barHeight);
        _tabStack.frame = CGRectInset(_tabBar.bounds, 6, 6);
        contentBottom = h;
    }
    _tabBar.layer.cornerRadius = railMode ? 24 : 26;
    _tabBarMaterial.frame = _tabBar.bounds;
    _tabBarMaterial.layer.cornerRadius = _tabBar.layer.cornerRadius;

    // Header: wordmark, version and the runtime status pill.
    const CGFloat right = MAX(16, safe.right + 4);
    const CGFloat maxContent = railMode ? 680 : 720;
    const CGFloat contentWidth = MIN(w - contentLeft - right, maxContent);
    const CGFloat wordSize = railMode ? 26 : 30;
    NSMutableAttributedString *word = [[NSMutableAttributedString alloc] initWithString:@"THEFT" attributes:@{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:wordSize]
            ?: [UIFont systemFontOfSize:wordSize weight:UIFontWeightBlack],
        NSForegroundColorAttributeName: TextPrimary(), NSKernAttributeName: @1}];
    [word appendAttributedString:[[NSAttributedString alloc] initWithString:@"4" attributes:@{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:wordSize]
            ?: [UIFont systemFontOfSize:wordSize weight:UIFontWeightBlack],
        NSForegroundColorAttributeName: Accent()}]];
    _wordmark.attributedText = word;
    [_wordmark sizeToFit];
    const CGFloat headerHeight = 36;
    _wordmark.frame = CGRectMake(contentLeft, top, MIN(_wordmark.bounds.size.width, 140), headerHeight);
    _edition.hidden = !railMode && w < 360;
    [_edition sizeToFit];
    const CGFloat editionWidth = _edition.bounds.size.width;

    CGFloat statusTop, statusLeft, statusWidth;
    if (railMode) {
        statusLeft = CGRectGetMaxX(_wordmark.frame) + 16;
        statusWidth = MAX(120, MIN(contentLeft + contentWidth, w - right) - statusLeft - editionWidth - 12);
        statusTop = top;
    } else {
        statusLeft = contentLeft;
        statusWidth = contentWidth;
        statusTop = top + headerHeight + 8;
    }
    _edition.frame = railMode
        ? CGRectMake(statusLeft + statusWidth + 12, top, editionWidth, headerHeight)
        : CGRectMake(w - right - editionWidth, top, editionWidth, headerHeight);
    const CGFloat labelWidth = statusWidth - 36;
    CGSize fit = [_statusLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
    const CGFloat maxLabel = railMode ? 34 : 52;
    const CGFloat labelHeight = MIN(MAX(18, ceil(fit.height)), maxLabel);
    const CGFloat pillHeight = MAX(railMode ? headerHeight : 40, labelHeight + 14);
    _statusPill.frame = CGRectMake(statusLeft, statusTop, statusWidth, pillHeight);
    _statusPill.layer.cornerRadius = MIN(pillHeight / 2, 16);
    _statusDot.frame = CGRectMake(14, (pillHeight - 8) / 2, 8, 8);
    _statusLabel.frame = CGRectMake(30, (pillHeight - labelHeight) / 2, labelWidth, labelHeight);

    // Content.
    const CGFloat scrollTop = CGRectGetMaxY(_statusPill.frame) + 14;
    _scroll.frame = CGRectMake(contentLeft, scrollTop, contentWidth, MAX(80, contentBottom - scrollTop));
    const CGFloat bottomInset = railMode ? 24 : (h - CGRectGetMinY(_tabBar.frame)) + 16;
    _scroll.contentInset = UIEdgeInsetsMake(4, 0, bottomInset, 0);
    _scroll.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);

    // Notice toast sits above the tab bar (portrait) or at the bottom (rail).
    CGSize noticeSize = [_notice sizeThatFits:CGSizeMake(MIN(contentWidth, 460), CGFLOAT_MAX)];
    noticeSize.width = MIN(MAX(noticeSize.width + 24, 160), MIN(contentWidth, 480));
    noticeSize.height = MAX(40, [_notice sizeThatFits:CGSizeMake(noticeSize.width - 24, CGFLOAT_MAX)].height + 20);
    const CGFloat noticeBottom = railMode ? h - bottom - 8 : CGRectGetMinY(_tabBar.frame) - 12;
    _notice.frame = CGRectMake(contentLeft + (contentWidth - noticeSize.width) / 2,
                               noticeBottom - noticeSize.height, noticeSize.width, noticeSize.height);

    [self refreshConfigurationSummary];
}

#pragma mark - Summary

- (uint32_t)renderHeight {
    NSInteger index = _renderResolution.selectedSegmentIndex;
    return index == 0 ? 540 : index == 2 ? 900 : index == 3 ? 1080 :
        index == 4 ? THEFT4_LAB_NATIVE_16_9 : 720;
}

- (void)refreshConfigurationSummary {
    if (_sharpening) {
        const NSInteger strength = (NSInteger)lroundf(_sharpening.value);
        _sharpeningMetrics.text = strength ? [NSString stringWithFormat:@"%ld%%", (long)strength] : @"Off · 0%";
        _sharpening.accessibilityValue = [NSString stringWithFormat:@"%ld percent", (long)strength];
    }
    NSArray<NSString *> *shadowMetrics = @[
        @"128 base · 1024² cache · 0.75× range",
        @"256 base · 2048² cache · 1× range",
        @"512 base · 4096² cache · 1× range",
        @"1024 base · up to 8192² cache · 1.5× range"];
    NSArray<NSString *> *distanceMetrics = @[
        kOptimizedDistanceMetrics,
        @"1× world distance · 13,000 drawables",
        @"2× world distance · 17,000 drawables",
        @"3× world distance · 20,000 drawables"];
    NSArray<NSString *> *reflectionMetrics = @[
        @"320 × 180 mirror/water · 256² environment",
        @"1920 × 1080 mirror/water · 1024² environment",
        @"2560 × 1440 mirror/water · 2048² environment"];
    _shadowMetrics.text = shadowMetrics[MAX(0, MIN(3, _shadowQuality.selectedSegmentIndex))];
    _distanceMetrics.text = distanceMetrics[MAX(0, MIN(3, _drawDistance.selectedSegmentIndex))];
    _modelMetrics.text = _modelDetail.selectedSegmentIndex == 0
        ? @"Earlier switch to simpler meshes · 1.75× selector"
        : _modelDetail.selectedSegmentIndex == 2 ? @"Highest resident mesh at any distance"
                                                 : @"Title-controlled model LOD";
    _reflectionMetrics.text = reflectionMetrics[MAX(0, MIN(2, _reflectionQuality.selectedSegmentIndex))];
    _aaMetrics.text = @[@"No edge filter", @"FXAA · single lightweight pass",
                        @"SMAA 1× · high preset"][MAX(0, MIN(2, _antiAliasing.selectedSegmentIndex))];
    _audioMetrics.text = @[@"1.0× · console stereo downmix", @"2.0× (+6 dB) · soft limiter",
                           @"2.8× (+9 dB) · soft limiter"][MAX(0, MIN(2, _audioVolume.selectedSegmentIndex))];

    NSString *shadow = @[@"Optimized", @"Original", @"Enhanced", @"Ultra"]
        [MAX(0, MIN(3, _shadowQuality.selectedSegmentIndex))];
    NSString *distance = @[@"Optimized", @"Original", @"2×", @"3×"]
        [MAX(0, MIN(3, _drawDistance.selectedSegmentIndex))];
    NSString *resolution = @"720p";
    if (_renderResolution) {
        const BOOL native = _renderResolution.selectedSegmentIndex == 4;
        _fsrUpscaling.enabled = !native && _renderResolution.enabled;
        if (native) _fsrUpscaling.on = NO;
        UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
        const char *deviceProfile = getenv("THEFT4_DEVICE_PROFILE") ?: "";
        const BOOL fixed1080Output = strcmp(deviceProfile, "a19") == 0 ||
            strcmp(deviceProfile, "iphone-6gb") == 0 || strcmp(deviceProfile, "legacy-ipad") == 0;
        const uint32_t fullWidth = (uint32_t)floor(self.bounds.size.width * screen.nativeScale);
        const uint32_t fullHeight = (uint32_t)floor(self.bounds.size.height * screen.nativeScale);
        uint32_t units = MIN(fullWidth / 16, fullHeight / 9);
        if (!units) units = 1;
        const uint32_t nativeWidth = _nativeAspect.on ? fullWidth : units * 16;
        const uint32_t nativeHeight = _nativeAspect.on ? fullHeight : units * 9;
        const theft4_output_policy output = _nativeAspect.on
            ? theft4_output_policy_for_native_aspect_lab(self.renderHeight,
                _fsrUpscaling.on, nativeWidth, nativeHeight, fixed1080Output)
            : fixed1080Output && !native
            ? theft4_output_policy_for_fixed_1080_lab_selected_aspect(
                self.renderHeight, _fsrUpscaling.on, nativeWidth, nativeHeight)
            : theft4_output_policy_for_lab(self.renderHeight, _fsrUpscaling.on, nativeWidth, nativeHeight);
        _resolutionSummary.text = [NSString stringWithFormat:@"%u × %u → %u × %u · %@ · %@",
            output.render_width, output.render_height, output.output_width, output.output_height,
            output.fsr1 ? @"FSR on" : @"FSR off", output.native_aspect ? @"native aspect" : @"16:9"];
        resolution = native ? @"Native pixels" : [NSString stringWithFormat:@"%up", self.renderHeight];
    }
    _configuration.text = [NSString stringWithFormat:@"%@ · %@ shadows · %@ distance\nSound: %@",
        resolution, shadow, distance,
        @[@"Original", @"Boost", @"Max"][MAX(0, MIN(2, _audioVolume.selectedSegmentIndex))]];
}

#pragma mark - Lifecycle

- (void)motionChanged:(NSNotification *)note { (void)note; [self setActive:_active]; }

- (void)setActive:(BOOL)active {
    _active = active;
    [_city setActive:active];
    _rain.birthRate = active && !_retired && !UIAccessibilityIsReduceMotionEnabled() ? 1 : 0;
    _rain.hidden = !active || _retired || UIAccessibilityIsReduceMotionEnabled();
}

- (void)retireScene {
    if (_retired) return;
    _retired = YES;
    [_city retire];
    [_city removeFromSuperview];
    _city = nil;
    _rain.emitterCells = nil;
    [_rain removeFromSuperlayer];
    _rain = nil;
}

- (void)dealloc {
    [_statusLabel removeObserver:self forKeyPath:@"text"];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self retireScene];
}
@end
