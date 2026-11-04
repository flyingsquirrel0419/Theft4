#import "Theft4LauncherView.h"
#ifdef THEFT4_BC_TEXTURE_COMPATIBILITY
#import "Theft4TextureSources.h"
#endif
#include "theft4_output_policy.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// The launcher follows the iOS Human Interface Guidelines: a system tab bar
// for the five top-level sections, inset grouped lists for settings, system
// colors and Dynamic Type, and the system appearance (light or dark).

#ifdef THEFT4_DIRECT_METAL_DEFAULT
static NSString *const kOptimizedDistanceDescription = @"Optimized draws world objects to 0.70× distance and keeps the game's LOD transitions.";
static NSString *const kOptimizedDistanceMetrics = @"0.70× world distance";
#else
static NSString *const kOptimizedDistanceDescription = @"Optimized draws to 0.70× distance and culls far local light volumes.";
static NSString *const kOptimizedDistanceMetrics = @"0.70× world distance · far local lights reduced";
#endif

static UILabel *Label(UIFontTextStyle style, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

static UIStackView *Stack(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    return stack;
}

// Liberty City amber: one key color for tabs, actions and selection. The light
// variant is dark enough for 4.5:1 contrast as text on white.
static UIColor *BrandTint(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:1.00 green:0.66 blue:0.20 alpha:1]
            : [UIColor colorWithRed:0.72 green:0.36 blue:0.00 alpha:1];
    }];
}

// A Settings-style icon: a white SF Symbol on a colored rounded square.
static UIImage *IconTile(NSString *symbol, UIColor *color) {
    const CGFloat side = 30;
    UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
        imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *tile = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        [color setFill];
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:7.5];
        [shape fill];
        if (glyph) {
            CGSize size = glyph.size;
            const CGFloat scale = MIN(1, MIN(19 / size.width, 19 / size.height));
            size = CGSizeMake(size.width * scale, size.height * scale);
            [glyph drawInRect:CGRectMake((side - size.width) / 2, (side - size.height) / 2, size.width, size.height)];
        }
    }];
    return [tile imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// Row title -> icon. Rows without an entry show no icon.
static UIImage *RowIcon(NSString *title) {
    static NSDictionary<NSString *, NSArray *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @{
            @"Resolution": @[@"aspectratio.fill", UIColor.systemBlueColor],
            @"Internal Resolution": @[@"aspectratio.fill", UIColor.systemBlueColor],
            @"FSR Upscaling": @[@"sparkles", UIColor.systemPurpleColor],
            @"1080p Enhanced Output": @[@"sparkles", UIColor.systemPurpleColor],
            @"FSR Boost": @[@"bolt.fill", UIColor.systemPurpleColor],
            @"Sharpening": @[@"wand.and.rays", UIColor.systemTealColor],
            @"Shadows": @[@"shadow", UIColor.systemIndigoColor],
            @"Draw Distance": @[@"mountain.2.fill", UIColor.systemGreenColor],
            @"Model Detail": @[@"cube.fill", UIColor.systemOrangeColor],
            @"Reflections": @[@"drop.fill", UIColor.systemCyanColor],
            @"Anti-Aliasing": @[@"square.grid.3x3.fill", UIColor.systemPinkColor],
            @"Texture Filtering": @[@"road.lanes", UIColor.systemBrownColor],
            @"Motion Blur": @[@"wind", UIColor.systemBlueColor],
            @"Depth of Field": @[@"camera.aperture", UIColor.systemPurpleColor],
            @"Touch Controls": @[@"hand.tap.fill", UIColor.systemBlueColor],
            @"Game Volume": @[@"speaker.wave.3.fill", UIColor.systemPinkColor],
            @"Frame Rate": @[@"speedometer", UIColor.systemGreenColor],
            @"Frame Time Graph": @[@"waveform.path.ecg", UIColor.systemOrangeColor],
            @"CPU Usage": @[@"cpu", UIColor.systemGrayColor],
            @"ASTC Textures": @[@"square.stack.3d.up.fill", UIColor.systemTealColor],
            @"Skip Intro Videos": @[@"forward.fill", UIColor.systemIndigoColor],
            @"Performance Capture": @[@"record.circle", UIColor.systemRedColor],
            @"Custom Time Cycle": @[@"sun.horizon.fill", UIColor.systemOrangeColor],
            @"Native Aspect Ratio": @[@"arrow.left.and.right", UIColor.systemBlueColor],
            @"God Mode": @[@"shield.fill", UIColor.systemRedColor],
            @"Unlimited Ammo": @[@"infinity", UIColor.systemGrayColor],
        };
    });
    NSArray *entry = icons[title];
    return entry ? IconTile(entry[0], entry[1]) : nil;
}

// The bundled time-cycle capture is letterboxed with an FPS counter above and
// the minimap bottom-left; keep only the street scene.
static UIImage *LibertyCityArtwork(void) {
    NSString *path = [NSBundle.mainBundle pathForResource:@"preview" ofType:@"jpg"
                                              inDirectory:@"Mods/CustomTimeCycle"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source.CGImage) return source;
    const CGFloat w = CGImageGetWidth(source.CGImage), h = CGImageGetHeight(source.CGImage);
    CGImageRef cropped = CGImageCreateWithImageInRect(source.CGImage,
        CGRectMake(floor(w * .18), floor(h * .135), floor(w * .82), floor(h * .72)));
    if (!cropped) return source;
    UIImage *image = [UIImage imageWithCGImage:cropped];
    CGImageRelease(cropped);
    return image;
}

// The Play hero: Liberty City artwork with a scrim so white text stays legible.
@interface Theft4HeroView : UIView
@end
@implementation Theft4HeroView {
    CAGradientLayer *_scrim;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _scrim = [CAGradientLayer layer];
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor,
                      (id)[UIColor colorWithWhite:0 alpha:.45].CGColor,
                      (id)[UIColor colorWithWhite:0 alpha:.85].CGColor];
    _scrim.locations = @[@0, @.35, @1];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (_scrim.superlayer != self.layer) [self.layer insertSublayer:_scrim atIndex:1];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = self.bounds;
    [CATransaction commit];
}
@end

static UITableViewCell *PlainCell(void) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// Pins a view to a cell's content margins so it follows the list's insets.
static void Embed(UITableViewCell *cell, UIView *view, CGFloat vertical) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:view];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:vertical],
        [view.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-vertical],
        [view.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor]]];
}

static UISwitch *Toggle(NSString *identifier) {
    UISwitch *toggle = [UISwitch new];
    toggle.accessibilityIdentifier = identifier;
    return toggle;
}

static UISegmentedControl *Choice(NSArray<NSString *> *items, NSString *identifier,
                                  NSString *label, NSString *hint) {
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:items];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        for (NSUInteger i = 0; i < control.numberOfSegments; ++i) {
            if ([[control titleForSegmentAtIndex:i] isEqualToString:@"Optimized"])
                [control setTitle:@"Opt." forSegmentAtIndex:i];
        }
    }
    control.accessibilityIdentifier = [@"settings." stringByAppendingString:identifier];
    control.accessibilityLabel = label;
    control.accessibilityHint = hint;
    return control;
}

// A list action: tinted text that spans the row, like actions in Settings.
static UIButton *RowAction(NSString *title, NSString *identifier, BOOL destructive) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.title = title;
    config.contentInsets = NSDirectionalEdgeInsetsMake(11, 0, 11, 0);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        return updated;
    };
    if (destructive) config.baseForegroundColor = UIColor.systemRedColor;
    button.configuration = config;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    button.accessibilityIdentifier = identifier;
    return button;
}

@interface Theft4ListSection : NSObject
@property(nonatomic, copy) NSString *header;
@property(nonatomic, copy) NSString *footer;
@property(nonatomic, copy) NSArray<UITableViewCell *> *cells;
@property(nonatomic) BOOL lockNotice;
@end
@implementation Theft4ListSection
@end

static Theft4ListSection *Group(NSString *header, NSArray<UITableViewCell *> *cells, NSString *footer) {
    Theft4ListSection *section = [Theft4ListSection new];
    section.header = header;
    section.footer = footer;
    section.cells = cells;
    return section;
}

@interface Theft4LauncherView () <UITableViewDataSource, UITableViewDelegate, UITabBarDelegate>
@end

@implementation Theft4LauncherView {
    UITableView *_table;
    UITabBar *_tabBar;
    UILabel *_pageTitle, *_pageSubtitle;
    UIView *_pageHeader;
    UIImageView *_statusIcon;
    UILabel *_resolutionSummary, *_shadowMetrics, *_distanceMetrics, *_modelMetrics;
    UILabel *_reflectionMetrics, *_aaMetrics, *_sharpeningMetrics, *_audioMetrics;
    UITableViewCell *_setupResolution, *_setupShadows, *_setupDistance, *_setupSound;
    NSArray<NSArray<Theft4ListSection *> *> *_pages;
    NSArray<NSString *> *_titles, *_subtitles;
    NSArray<Theft4ListSection *> *_visible;
    NSMapTable<UITableViewCell *, UIView *> *_owners;
    Theft4ListSection *_lockSection;
    UIView *_notice;
    UILabel *_noticeLabel;
    NSUInteger _noticeGeneration;
    NSInteger _selectedPage;
    BOOL _locked;
}

#pragma mark - Construction

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tintColor = BrandTint();
    _owners = [NSMapTable weakToWeakObjectsMapTable];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.cellLayoutMarginsFollowReadableWidth = YES;
    _table.estimatedRowHeight = 52;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.sectionHeaderTopPadding = 0;
    _table.allowsSelection = NO;
    [self addSubview:_table];

    [self buildStatus];
    [self buildPages];
    [self buildHeader];
    [self buildTabBar];
    [self buildNotice];

    for (UIView *view in @[_statusLabel, _detailLabel])
        [view addObserver:self forKeyPath:@"text" options:0 context:NULL];
    for (UIView *view in [self hideableControls])
        [view addObserver:self forKeyPath:@"hidden" options:0 context:NULL];

    [self selectPage:0];
    return self;
}

- (NSArray<UIView *> *)hideableControls {
    NSMutableArray<UIView *> *controls = [NSMutableArray arrayWithObjects:_startButton, _restartButton, nil];
    if (_restoreGraphicsButton) [controls addObject:_restoreGraphicsButton];
    return controls;
}

- (void)buildStatus {
    _statusLabel = Label(UIFontTextStyleBody, UIColor.labelColor);
    _statusLabel.text = @"Ready";
    _statusLabel.accessibilityIdentifier = @"core.status";
    _statusIcon = [UIImageView new];
    _statusIcon.contentMode = UIViewContentModeScaleAspectFit;
    _statusIcon.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleBody scale:UIImageSymbolScaleLarge];
    [_statusIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_statusIcon setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                 forAxis:UILayoutConstraintAxisHorizontal];
    [self updateStatusIcon];

    _detailLabel = Label(UIFontTextStyleFootnote, UIColor.secondaryLabelColor);
    _detailLabel.text = @"Waiting for runtime information…";
    _detailLabel.accessibilityIdentifier = @"core.details";
}

- (void)buildHeader {
    _pageTitle = Label(UIFontTextStyleLargeTitle, UIColor.labelColor);
    UIFontDescriptor *bold = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleLargeTitle]
        fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    _pageTitle.font = [UIFont fontWithDescriptor:bold size:0];
    _pageTitle.accessibilityTraits = UIAccessibilityTraitHeader;
    _pageSubtitle = Label(UIFontTextStyleSubheadline, UIColor.secondaryLabelColor);
    UIStackView *stack = Stack(@[_pageTitle, _pageSubtitle], 2);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    _pageHeader = [UIView new];
    [_pageHeader addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:_pageHeader.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:_pageHeader.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:_pageHeader.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:_pageHeader.layoutMarginsGuide.trailingAnchor]]];
    _table.tableHeaderView = _pageHeader;
}

- (void)buildTabBar {
    _tabBar = [UITabBar new];
    _tabBar.delegate = self;
    NSArray<NSString *> *symbols = @[@"play.fill", @"sparkles.tv.fill", @"gamecontroller.fill",
                                     @"gearshape.fill", @"puzzlepiece.extension.fill"];
    NSMutableArray<UITabBarItem *> *items = [NSMutableArray new];
    for (NSUInteger i = 0; i < _titles.count; ++i) {
        UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:_titles[i]
            image:[UIImage systemImageNamed:symbols[i]] tag:(NSInteger)i];
        item.accessibilityIdentifier = [NSString stringWithFormat:@"launcher.tab.%lu", (unsigned long)i];
        [items addObject:item];
    }
    _tabBar.items = items;
    [self addSubview:_tabBar];
}

- (void)buildNotice {
    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    material.layer.cornerRadius = 22;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.clipsToBounds = YES;
    _noticeLabel = Label(UIFontTextStyleSubheadline, UIColor.labelColor);
    _noticeLabel.textAlignment = NSTextAlignmentCenter;
    _noticeLabel.accessibilityIdentifier = @"launcher.notice";
    _noticeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [material.contentView addSubview:_noticeLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_noticeLabel.topAnchor constraintEqualToAnchor:material.contentView.topAnchor constant:12],
        [_noticeLabel.bottomAnchor constraintEqualToAnchor:material.contentView.bottomAnchor constant:-12],
        [_noticeLabel.leadingAnchor constraintEqualToAnchor:material.contentView.leadingAnchor constant:18],
        [_noticeLabel.trailingAnchor constraintEqualToAnchor:material.contentView.trailingAnchor constant:-18]]];
    _notice = material;
    _notice.alpha = 0;
    _notice.userInteractionEnabled = NO;
    [self addSubview:_notice];
}

#pragma mark - Rows

- (UITableViewCell *)toggle:(UISwitch *)toggle title:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = PlainCell();
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title;
    content.image = RowIcon(title);
    content.secondaryText = detail;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    content.textToSecondaryTextVerticalPadding = 3;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11, 0, 11, 0);
    cell.contentConfiguration = content;
    cell.accessoryView = toggle;
    toggle.accessibilityLabel = title;
    toggle.accessibilityHint = detail;
    return cell;
}

- (UITableViewCell *)choice:(UIControl *)control title:(NSString *)title
                     detail:(NSString *)detail metrics:(UILabel *)metrics {
    NSMutableArray<UIView *> *views = [NSMutableArray new];
    UILabel *heading = Label(UIFontTextStyleBody, UIColor.labelColor);
    heading.text = title;
    UIImage *icon = RowIcon(title);
    if (icon) {
        UIImageView *tile = [[UIImageView alloc] initWithImage:icon];
        [tile setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[tile, heading]];
        row.spacing = 16;
        row.alignment = UIStackViewAlignmentCenter;
        [views addObject:row];
    } else {
        [views addObject:heading];
    }
    [views addObject:control];
    if (metrics) [views addObject:metrics];
    if (detail.length) {
        UILabel *note = Label(UIFontTextStyleFootnote, UIColor.secondaryLabelColor);
        note.text = detail;
        [views addObject:note];
    }
    UIStackView *stack = Stack(views, 8);
    [stack setCustomSpacing:10 afterView:views.firstObject];
    UITableViewCell *cell = PlainCell();
    Embed(cell, stack, 12);
    return cell;
}

- (UILabel *)metrics {
    UILabel *label = Label(UIFontTextStyleFootnote, UIColor.secondaryLabelColor);
    label.font = [UIFont monospacedDigitSystemFontOfSize:label.font.pointSize weight:UIFontWeightRegular];
    return label;
}

- (UITableViewCell *)action:(UIButton *)button {
    UITableViewCell *cell = PlainCell();
    Embed(cell, button, 0);
    [_owners setObject:button forKey:cell];
    return cell;
}

- (UITableViewCell *)value:(NSString *)title {
    UITableViewCell *cell = PlainCell();
    UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
    content.text = title;
    content.image = RowIcon(title);
    cell.contentConfiguration = content;
    return cell;
}

- (void)setSetupValue:(NSString *)value cell:(UITableViewCell *)cell {
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    if ([content.secondaryText isEqualToString:value]) return;
    content.secondaryText = value;
    cell.contentConfiguration = content;
}

- (UITableViewCell *)labelCell:(UILabel *)label {
    UITableViewCell *cell = PlainCell();
    Embed(cell, label, 12);
    return cell;
}

- (UITableViewCell *)heroWithButton:(UIButton *)button {
    Theft4HeroView *hero = [Theft4HeroView new];
    hero.backgroundColor = [UIColor colorWithRed:.10 green:.12 blue:.18 alpha:1];
    hero.layer.cornerRadius = 26;
    hero.layer.cornerCurve = kCACornerCurveContinuous;
    hero.clipsToBounds = YES;

    UIImageView *art = [[UIImageView alloc] initWithImage:LibertyCityArtwork()];
    art.contentMode = UIViewContentModeScaleAspectFill;
    art.translatesAutoresizingMaskIntoConstraints = NO;
    [hero insertSubview:art atIndex:0];

    UILabel *eyebrow = Label(UIFontTextStyleFootnote, [UIColor colorWithWhite:1 alpha:.78]);
    UIFontDescriptor *semibold = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleFootnote]
        fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute:
            @{UIFontWeightTrait: @(UIFontWeightSemibold)}}];
    eyebrow.font = [UIFont fontWithDescriptor:semibold size:0];
    eyebrow.text = @"GRAND THEFT AUTO IV";
    UILabel *title = Label(UIFontTextStyleTitle1, UIColor.whiteColor);
    UIFontDescriptor *bold = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleTitle1]
        fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    title.font = [UIFont fontWithDescriptor:bold size:0];
    title.text = @"Liberty City";
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    UILabel *subtitle = Label(UIFontTextStyleSubheadline, [UIColor colorWithWhite:1 alpha:.85]);
    subtitle.text = @"The Xbox 360 game, recompiled to run natively.";

    UIStackView *text = Stack(@[eyebrow, title, subtitle], 2);
    UIStackView *overlay = Stack(@[text, button], 16);
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:overlay];

    NSLayoutConstraint *aspect = [hero.heightAnchor constraintEqualToAnchor:hero.widthAnchor multiplier:.72];
    aspect.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        aspect,
        [hero.heightAnchor constraintLessThanOrEqualToConstant:360],
        [hero.heightAnchor constraintGreaterThanOrEqualToConstant:250],
        [art.topAnchor constraintEqualToAnchor:hero.topAnchor],
        [art.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor],
        [art.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [art.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:20],
        [overlay.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],
        [overlay.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-20],
        [overlay.topAnchor constraintGreaterThanOrEqualToAnchor:hero.topAnchor constant:20]]];

    UITableViewCell *cell = PlainCell();
    cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:hero];
    [NSLayoutConstraint activateConstraints:@[
        [hero.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor]]];
    return cell;
}

#pragma mark - Pages

- (void)buildPages {
    const BOOL lab = [NSBundle.mainBundle.infoDictionary[@"Theft4LabBuild"] boolValue];
    NSString *displayName = NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: @"Theft4";
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = [NSString stringWithFormat:@"Version %@ (%@)",
        info[@"Theft4ReleaseName"] ?: @"0.3", info[@"CFBundleVersion"] ?: @"0"];

    _titles = @[@"Play", @"Graphics", @"Interface", @"System", @"Mods"];
    _subtitles = @[version, @"Applies the next time the game starts.",
                   @"Overlays, controls and sound.", @"Game files, saves and diagnostics.",
                   @"Optional changes to Liberty City."];

    // ---- Play ----
    UIStackView *status = [[UIStackView alloc] initWithArrangedSubviews:@[_statusIcon, _statusLabel]];
    status.spacing = 12;
    status.alignment = UIStackViewAlignmentCenter;
    UITableViewCell *statusCell = PlainCell();
    Embed(statusCell, status, 13);

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *play = [UIButtonConfiguration filledButtonConfiguration];
    play.title = @"Play";
    play.baseBackgroundColor = BrandTint();
    play.baseForegroundColor = UIColor.whiteColor;
    play.image = [UIImage systemImageNamed:@"play.fill"];
    play.imagePadding = 8;
    play.buttonSize = UIButtonConfigurationSizeLarge;
    play.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    play.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    play.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        UIFontDescriptor *descriptor = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleHeadline]
            fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
        updated[NSFontAttributeName] = [UIFont fontWithDescriptor:descriptor size:0];
        return updated;
    };
    _startButton.configuration = play;
    _startButton.accessibilityIdentifier = @"game.start";
    _startButton.accessibilityHint = @"Starts Grand Theft Auto IV. Continue or start a story from the game's menu.";
    UITableViewCell *playCell = [self heroWithButton:_startButton];

    _setupResolution = [self value:@"Resolution"];
    _setupShadows = [self value:@"Shadows"];
    _setupDistance = [self value:@"Draw Distance"];
    _setupSound = [self value:@"Game Volume"];

    NSArray<Theft4ListSection *> *playPage = @[
        Group(nil, @[playCell], @"Saves stay with this app. To continue or start a new story, use the game's own menu."),
        Group(@"Status", @[statusCell], nil),
        Group(@"Current Setup", @[_setupResolution, _setupShadows, _setupDistance, _setupSound],
              @"Change these in Graphics and Interface before you press Play."),
    ];

    // ---- Graphics ----
    _showCPUUsage = Toggle(@"settings.showCPUUsage");
    _showFrameTime = Toggle(@"settings.showFrameTime");
    _showFPS = Toggle(@"settings.showFPS");
    _showControls = Toggle(@"settings.showTouchControls");
    _anisotropicFiltering = Toggle(@"settings.anisotropicFiltering");
    _enhancedOutput = Toggle(@"settings.enhancedOutput1080p");
    _fsrBoost = Toggle(@"settings.fsrBoost");
    _motionBlur = Toggle(@"settings.motionBlur");
    _depthOfField = Toggle(@"settings.depthOfField");

    NSMutableArray<Theft4ListSection *> *graphics = [NSMutableArray new];
    if (lab) {
        _lowPowerButton = RowAction(@"Optimize for This Device", @"settings.autoOptimize", NO);
        _originalPresetButton = RowAction(@"Original Xbox 360 Settings", @"settings.originalPreset", NO);
        _frameSpeedButton = RowAction(@"Favor Frame Rate", @"settings.frameSpeed", NO);
        _restoreGraphicsButton = RowAction(@"Restore Previous Settings", @"settings.restorePreviousGraphics", NO);
        [graphics addObject:Group(@"Presets", @[[self action:_lowPowerButton], [self action:_originalPresetButton],
                                                [self action:_frameSpeedButton], [self action:_restoreGraphicsButton]],
            @"A preset sets every option below. You can adjust each one afterward.")];

        _renderResolution = Choice(@[@"540p", @"720p", @"900p", @"1080p", @"Native"], @"renderResolution",
            @"Render resolution", @"The internal scene resolution. Applies at the next game launch.");
        _renderResolution.selectedSegmentIndex = 1;
        _fsrUpscaling = Toggle(@"settings.fsrUpscaling");
        _resolutionSummary = [self metrics];
        _resolutionSummary.accessibilityIdentifier = @"settings.resolutionSummary";
    }
    NSMutableArray<UITableViewCell *> *resolution = [NSMutableArray new];
    if (_renderResolution) {
        [resolution addObject:[self choice:_renderResolution title:@"Internal Resolution"
            detail:@"Native uses physical pixels and turns off FSR." metrics:_resolutionSummary]];
        const char *profile = getenv("THEFT4_DEVICE_PROFILE") ?: "";
        const BOOL fixed1080 = strcmp(profile, "a19") == 0 || strcmp(profile, "iphone-6gb") == 0 ||
                               strcmp(profile, "legacy-ipad") == 0;
        [resolution addObject:[self toggle:_fsrUpscaling title:@"FSR Upscaling" detail:fixed1080
            ? @"This device outputs 1080p. Lower resolutions are upscaled with FSR 1."
            : @"When off, the selected resolution is shown without upscaling."]];
    } else {
        [resolution addObject:[self toggle:_enhancedOutput title:@"1080p Enhanced Output"
            detail:@"FSR 1 upscaling with sharpening."]];
        [resolution addObject:[self toggle:_fsrBoost title:@"FSR Boost"
            detail:@"Experimental. Native-pixel 16:9 output from the 720p scene."]];
    }
#ifdef THEFT4_DIRECT_METAL_DEFAULT
    _sharpening = [UISlider new];
    _sharpening.minimumValue = 0;
    _sharpening.maximumValue = 100;
    _sharpening.accessibilityIdentifier = @"settings.sharpening";
    _sharpening.accessibilityLabel = @"Sharpening";
    _sharpening.accessibilityHint = @"Zero turns sharpening off. Applies at the next game launch.";
    [_sharpening addTarget:self action:@selector(refreshConfigurationSummary)
          forControlEvents:UIControlEventValueChanged];
    _sharpeningMetrics = [self metrics];
    [resolution addObject:[self choice:_sharpening title:@"Sharpening"
        detail:@"Higher values add GPU work and can make texture noise more visible." metrics:_sharpeningMetrics]];
#endif
    [graphics addObject:Group(@"Resolution", resolution, nil)];

    _shadowQuality = Choice(@[@"Optimized", @"Original", @"Enhanced", @"Ultra"], @"shadowQuality",
        @"Shadows", @"Optimized is unavailable until distant shadow caching is verified.");
    [_shadowQuality setEnabled:NO forSegmentAtIndex:0];
    _drawDistance = Choice(@[@"Optimized", @"Original", @"2×", @"3×"], @"drawDistance",
        @"Draw distance", kOptimizedDistanceDescription);
    _modelDetail = Choice(@[@"Lower", @"Original", @"Highest"], @"modelDetail",
        @"Model detail", @"Lower switches to simpler meshes sooner.");
    _reflectionQuality = Choice(@[@"Original", @"1080p", @"Full"], @"reflectionQuality",
        @"Reflections", @"Resolution of mirror, water and environment reflections.");
    _antiAliasing = Choice(@[@"Off", @"FXAA", @"SMAA"], @"antiAliasing",
        @"Anti-aliasing", @"Edge smoothing.");
    _shadowMetrics = [self metrics];
    _distanceMetrics = [self metrics];
    _modelMetrics = [self metrics];
    _reflectionMetrics = [self metrics];
    _aaMetrics = [self metrics];
    for (UISegmentedControl *choice in @[_shadowQuality, _drawDistance, _modelDetail,
                                         _reflectionQuality, _antiAliasing]) {
        [choice addTarget:self action:@selector(refreshConfigurationSummary)
         forControlEvents:UIControlEventValueChanged];
    }
    [graphics addObject:Group(@"World", @[
        [self choice:_shadowQuality title:@"Shadows" detail:nil metrics:_shadowMetrics],
        [self choice:_drawDistance title:@"Draw Distance" detail:nil metrics:_distanceMetrics],
        [self choice:_modelDetail title:@"Model Detail" detail:nil metrics:_modelMetrics],
        [self choice:_reflectionQuality title:@"Reflections" detail:nil metrics:_reflectionMetrics],
    ], @"Ultra shadows and extended draw distance can lower the frame rate in busy areas.")];
    [graphics addObject:Group(@"Image", @[
        [self choice:_antiAliasing title:@"Anti-Aliasing" detail:nil metrics:_aaMetrics],
        [self toggle:_anisotropicFiltering title:@"Texture Filtering" detail:@"4× anisotropic. Sharper roads at an angle."],
        [self toggle:_motionBlur title:@"Motion Blur" detail:nil],
        [self toggle:_depthOfField title:@"Depth of Field" detail:nil],
    ], nil)];

    // ---- Interface ----
    _audioVolume = Choice(@[@"Original", @"Boost", @"Max"], @"audioVolume",
        @"Game volume", @"Raises the game's mix for headphones and the speaker.");
    _audioVolume.selectedSegmentIndex = 1;
    [_audioVolume addTarget:self action:@selector(refreshConfigurationSummary)
           forControlEvents:UIControlEventValueChanged];
    _audioMetrics = [self metrics];
    NSArray<Theft4ListSection *> *interfacePage = @[
        Group(@"Controls", @[
            [self toggle:_showControls title:@"Touch Controls" detail:@"A connected controller works even when these are hidden."],
        ], @"In the game, tap with three fingers to open the game menu."),
        Group(@"Sound", @[
            [self choice:_audioVolume title:@"Game Volume" detail:nil metrics:_audioMetrics],
        ], @"Boost and Max make the game louder, especially on headphones, without clipping loud scenes. Sound stops while Theft4 is in the background."),
        Group(@"Overlays", @[
            [self toggle:_showFPS title:@"Frame Rate" detail:nil],
            [self toggle:_showFrameTime title:@"Frame Time Graph" detail:@"Touch and hold the graph to mark a spike or save a capture."],
            [self toggle:_showCPUUsage title:@"CPU Usage" detail:nil],
        ], nil),
    ];

    // ---- System ----
    _prepareButton = RowAction(@"Verify Game Files", @"game.prepare", NO);
    _restartButton = RowAction(@"Restart Core", @"core.restart", NO);
    _skipIntro = Toggle(@"settings.skipIntro");
    _performanceCapture = Toggle(@"settings.performanceCapture");
    _downloadLogButton = RowAction(@"Export Latest Log", @"diagnostics.downloadLatestCapture", NO);
    _exportSavesButton = RowAction(@"Export Saves", @"saves.export", NO);
    _importSavesButton = RowAction(@"Import Saves", @"saves.import", NO);

    NSMutableArray<Theft4ListSection *> *system = [NSMutableArray new];
    [system addObject:Group(@"Game Files", @[[self action:_prepareButton], [self action:_restartButton],
                                             [self labelCell:_detailLabel]],
        [NSString stringWithFormat:@"Copy your game files, including the update folder, into the game folder in %@'s Documents. Under LiveContainer, that folder is inside LiveContainer's data.",
            displayName])];
#ifdef THEFT4_BC_TEXTURE_COMPATIBILITY
    _astcConversion = Toggle(@"settings.astcConversion");
    _deleteTextureCacheButton = RowAction(@"Delete Texture Cache", @"settings.deleteTextureCache", YES);
    BOOL showTextureCompatibility = Theft4DeviceNeedsBCTexturePreparation();
#ifdef THEFT4_ASTC_EXPERIMENT
    showTextureCompatibility = YES;
#endif
    if (showTextureCompatibility) {
        [system addObject:Group(@"Textures", @[
            [self toggle:_astcConversion title:@"ASTC Textures"
                  detail:@"Converts textures once for this GPU so later launches start faster."],
            [self action:_deleteTextureCacheButton],
        ], @"Deleting the cache keeps your game files and saves. Textures are converted again before the next Play.")];
    }
#endif
    [system addObject:Group(@"Startup", @[
        [self toggle:_skipIntro title:@"Skip Intro Videos" detail:nil],
    ], nil)];
    [system addObject:Group(@"Saves", @[[self action:_exportSavesButton], [self action:_importSavesButton]],
        @"Import only while the game is closed. Your current saves are backed up first.")];
    [system addObject:Group(@"Diagnostics", @[
        [self toggle:_performanceCapture title:@"Performance Capture"
              detail:@"Records up to 5 minutes of timing. Turns off each time the app opens."],
        [self action:_downloadLogButton],
    ], @"Exports the latest capture, log and crash report to Theft4 › Diagnostics in Files.")];

    // ---- Mods ----
    _customTimeCycle = Toggle(@"mods.customTimeCycle");
    _nativeAspect = Toggle(@"mods.nativeAspect");
    [_nativeAspect addTarget:self action:@selector(refreshConfigurationSummary)
            forControlEvents:UIControlEventValueChanged];
    _godMode = Toggle(@"mods.godMode");
    _unlimitedAmmo = Toggle(@"mods.unlimitedAmmo");

    UIImageView *preview = [[UIImageView alloc] initWithImage:LibertyCityArtwork()];
    preview.contentMode = UIViewContentModeScaleAspectFill;
    preview.backgroundColor = UIColor.tertiarySystemFillColor;
    preview.layer.cornerRadius = 10;
    preview.layer.cornerCurve = kCACornerCurveContinuous;
    preview.clipsToBounds = YES;
    preview.isAccessibilityElement = YES;
    preview.accessibilityLabel = @"Custom time cycle example: a bright Liberty City street under a clear blue sky.";
    preview.accessibilityIdentifier = @"mods.customTimeCycle.preview";
    [preview.widthAnchor constraintEqualToConstant:96].active = YES;
    [preview.heightAnchor constraintEqualToConstant:72].active = YES;
    NSString *metadataPath = [NSBundle.mainBundle pathForResource:@"metadata" ofType:@"plist"
                                                      inDirectory:@"Mods/CustomTimeCycle"];
    NSDictionary *metadata = metadataPath ? [NSDictionary dictionaryWithContentsOfFile:metadataPath] : nil;
    NSString *developer = [metadata[@"Developer"] isKindOfClass:NSString.class]
        ? [metadata[@"Developer"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    UILabel *caption = Label(UIFontTextStyleFootnote, UIColor.secondaryLabelColor);
    caption.text = @"Looks vary with weather, time of day and graphics settings.";
    UILabel *credit = Label(UIFontTextStyleFootnote, UIColor.labelColor);
    credit.text = developer.length ? [NSString stringWithFormat:@"Time cycle by %@.", developer]
                                   : @"Bundled time cycle.";
    credit.accessibilityIdentifier = @"mods.customTimeCycle.developerCredit";
    UIStackView *example = [[UIStackView alloc] initWithArrangedSubviews:@[preview, Stack(@[credit, caption], 3)]];
    example.spacing = 14;
    example.alignment = UIStackViewAlignmentCenter;
    UITableViewCell *exampleCell = PlainCell();
    Embed(exampleCell, example, 12);

    NSArray<Theft4ListSection *> *mods = @[
        Group(@"Atmosphere", @[
            [self toggle:_customTimeCycle title:@"Custom Time Cycle"
                  detail:@"Replaces lighting, sky, fog and weather. Off uses the original."],
            exampleCell,
        ], nil),
        Group(@"View", @[
            [self toggle:_nativeAspect title:@"Native Aspect Ratio"
                  detail:@"Fills the screen with more of the scene instead of 16:9. The HUD keeps its proportions."],
        ], @"Showing more of the scene can lower performance. Videos stay 16:9."),
        Group(@"Gameplay", @[
            [self toggle:_godMode title:@"God Mode" detail:@"No damage or death from any source."],
            [self toggle:_unlimitedAmmo title:@"Unlimited Ammo"
                  detail:@"Reserve ammo stays full. You still reload."],
        ], @"Turning Unlimited Ammo off restores normal ammo use. Ammo it refilled can still be saved."),
    ];

    _lockSection = [Theft4ListSection new];
    _lockSection.lockNotice = YES;
    UITableViewCell *lockCell = PlainCell();
    UIListContentConfiguration *lock = [UIListContentConfiguration subtitleCellConfiguration];
    lock.image = [UIImage systemImageNamed:@"lock.fill"];
    lock.imageProperties.tintColor = UIColor.secondaryLabelColor;
    lock.text = @"Locked While the Game Is Running";
    lock.secondaryText = @"These settings take effect when the game starts. To change them, quit Theft4 and open it again.";
    lock.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    lock.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    lock.textToSecondaryTextVerticalPadding = 3;
    lock.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11, 0, 11, 0);
    lockCell.contentConfiguration = lock;
    _lockSection.cells = @[lockCell];

    _pages = @[playPage, graphics, interfacePage, system, mods];
}

#pragma mark - Navigation

- (void)selectPage:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_pages.count) return;
    _selectedPage = index;
    _tabBar.selectedItem = _tabBar.items[(NSUInteger)index];
    _pageTitle.text = index == 0
        ? (NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: @"Theft4") : _titles[(NSUInteger)index];
    _pageSubtitle.text = _subtitles[(NSUInteger)index];
    [self reloadPage];
    [self sizeHeader];
    [_table setContentOffset:CGPointMake(0, -_table.adjustedContentInset.top) animated:NO];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _pageTitle);
}

- (void)reloadPage {
    NSMutableArray<Theft4ListSection *> *visible = [NSMutableArray new];
    if (_locked && _selectedPage != 0 && _selectedPage != 3) [visible addObject:_lockSection];
    for (Theft4ListSection *section in _pages[(NSUInteger)_selectedPage]) {
        NSMutableArray<UITableViewCell *> *cells = [NSMutableArray new];
        for (UITableViewCell *cell in section.cells) {
            UIView *owner = [_owners objectForKey:cell];
            if (!owner.hidden) [cells addObject:cell];
        }
        if (!cells.count) continue;
        Theft4ListSection *shown = Group(section.header, cells, section.footer);
        [visible addObject:shown];
    }
    _visible = visible;
    [_table reloadData];
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    (void)tabBar;
    [self selectPage:item.tag];
}

- (void)revealControl:(UIView *)control {
    for (NSUInteger s = 0; s < _visible.count; ++s) {
        for (NSUInteger r = 0; r < _visible[s].cells.count; ++r) {
            if ([control isDescendantOfView:_visible[s].cells[r]]) {
                [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s]
                              atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                return;
            }
        }
    }
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return _startButton.enabled && !_startButton.hidden && _selectedPage == 0
        ? @[_startButton] : @[_table];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_visible.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)_visible[(NSUInteger)section].cells.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return _visible[(NSUInteger)indexPath.section].cells[(NSUInteger)indexPath.row];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return _visible[(NSUInteger)section].header;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return _visible[(NSUInteger)section].footer;
}

#pragma mark - Status

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"text"]) {
        if (object == _statusLabel) [self updateStatusIcon];
        [self resizeRows];
        return;
    }
    if ([keyPath isEqualToString:@"hidden"]) {
        [self reloadPage];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)resizeRows {
    if (!_table.window) return;
    [UIView performWithoutAnimation:^{
        [self->_table beginUpdates];
        [self->_table endUpdates];
    }];
}

- (void)updateStatusIcon {
    NSString *text = _statusLabel.text.lowercaseString ?: @"";
    NSString *symbol = @"checkmark.circle.fill";
    UIColor *tint = UIColor.systemGreenColor;
    for (NSString *word in @[@"copy", @"select", @"verify", @"prepar", @"loading", @"checking", @"waiting"]) {
        if ([text containsString:word]) { symbol = @"clock.fill"; tint = UIColor.systemOrangeColor; break; }
    }
    for (NSString *word in @[@"fail", @"error", @"cannot", @"missing", @"invalid", @"not "]) {
        if ([text containsString:word]) {
            symbol = @"exclamationmark.triangle.fill"; tint = UIColor.systemRedColor; break;
        }
    }
    if ([text containsString:@"preview"]) { symbol = @"info.circle.fill"; tint = UIColor.systemBlueColor; }
    _statusIcon.image = [UIImage systemImageNamed:symbol];
    _statusIcon.tintColor = tint;
}

#pragma mark - Feedback

- (void)showNotice:(NSString *)message {
    if (!message.length) return;
    _noticeLabel.text = message;
    const NSUInteger generation = ++_noticeGeneration;
    [self bringSubviewToFront:_notice];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [UIView animateWithDuration:.2 animations:^{ self->_notice.alpha = 1; }];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self->_noticeGeneration) return;
        [UIView animateWithDuration:.3 animations:^{ self->_notice.alpha = 0; }];
    });
}

- (void)setSessionLocked:(BOOL)locked {
    if (_locked == locked) return;
    _locked = locked;
    [self reloadPage];
}

#pragma mark - Layout

- (void)sizeHeader {
    const CGFloat width = _table.bounds.size.width;
    if (width <= 0) return;
    _pageHeader.layoutMargins = UIEdgeInsetsMake(0, _table.layoutMargins.left, 0, _table.layoutMargins.right);
    if (_table.cellLayoutMarginsFollowReadableWidth) {
        const CGRect readable = _table.readableContentGuide.layoutFrame;
        if (readable.size.width > 0)
            _pageHeader.layoutMargins = UIEdgeInsetsMake(0, CGRectGetMinX(readable) + 4,
                                                         0, width - CGRectGetMaxX(readable) + 4);
    }
    const CGSize size = [_pageHeader systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(_pageHeader.frame.size.height - size.height) > .5 || fabs(_pageHeader.frame.size.width - width) > .5) {
        _pageHeader.frame = CGRectMake(0, 0, width, size.height);
        _table.tableHeaderView = _pageHeader;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    const CGRect bounds = self.bounds;
    const CGSize bar = [_tabBar sizeThatFits:bounds.size];
    _tabBar.frame = CGRectMake(0, bounds.size.height - bar.height, bounds.size.width, bar.height);
    _table.frame = bounds;
    const CGFloat overlap = MAX(0, bar.height - self.safeAreaInsets.bottom);
    if (fabs(_table.contentInset.bottom - overlap) > .5) {
        _table.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
        _table.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, overlap, 0);
    }
    [self sizeHeader];

    const CGFloat maxWidth = MIN(bounds.size.width - 32, 480);
    const CGSize text = [_noticeLabel sizeThatFits:CGSizeMake(maxWidth - 36, CGFLOAT_MAX)];
    const CGFloat width = MIN(maxWidth, ceil(text.width) + 36);
    const CGFloat height = ceil(text.height) + 24;
    // Like a system banner: just below the status bar, clear of the floating tab bar.
    _notice.frame = CGRectMake((bounds.size.width - width) / 2, self.safeAreaInsets.top + 8, width, height);
    _notice.layer.cornerRadius = MIN(22, height / 2);

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
        _sharpeningMetrics.text = strength ? [NSString stringWithFormat:@"%ld%%", (long)strength] : @"Off";
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
        @"320 × 180 mirror and water · 256² environment",
        @"1920 × 1080 mirror and water · 1024² environment",
        @"2560 × 1440 mirror and water · 2048² environment"];
    _shadowMetrics.text = shadowMetrics[MAX(0, MIN(3, _shadowQuality.selectedSegmentIndex))];
    _distanceMetrics.text = distanceMetrics[MAX(0, MIN(3, _drawDistance.selectedSegmentIndex))];
    _modelMetrics.text = _modelDetail.selectedSegmentIndex == 0
        ? @"Simpler meshes sooner · 1.75× selector"
        : _modelDetail.selectedSegmentIndex == 2 ? @"Best resident mesh at any distance"
                                                 : @"The game's own model detail";
    _reflectionMetrics.text = reflectionMetrics[MAX(0, MIN(2, _reflectionQuality.selectedSegmentIndex))];
    _aaMetrics.text = @[@"No edge smoothing", @"FXAA · one lightweight pass",
                        @"SMAA 1× · high preset"][MAX(0, MIN(2, _antiAliasing.selectedSegmentIndex))];
    _audioMetrics.text = @[@"1.0× · the console's stereo mix", @"2.0× (+6 dB) · soft limiter",
                           @"2.8× (+9 dB) · soft limiter"][MAX(0, MIN(2, _audioVolume.selectedSegmentIndex))];

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
            output.fsr1 ? @"FSR" : @"No FSR", output.native_aspect ? @"Native aspect" : @"16:9"];
        resolution = native ? @"Native" : [NSString stringWithFormat:@"%up", self.renderHeight];
    }
    [self setSetupValue:resolution cell:_setupResolution];
    [self setSetupValue:@[@"Optimized", @"Original", @"Enhanced", @"Ultra"]
        [MAX(0, MIN(3, _shadowQuality.selectedSegmentIndex))] cell:_setupShadows];
    [self setSetupValue:@[@"Optimized", @"Original", @"2×", @"3×"]
        [MAX(0, MIN(3, _drawDistance.selectedSegmentIndex))] cell:_setupDistance];
    [self setSetupValue:@[@"Original", @"Boost", @"Max"]
        [MAX(0, MIN(2, _audioVolume.selectedSegmentIndex))] cell:_setupSound];
}

#pragma mark - Lifecycle

// The launcher has no animated scene, so there is no GPU work to pause.
- (void)setActive:(BOOL)active { (void)active; }
- (void)retireScene {}

- (void)dealloc {
    for (UIView *view in @[_statusLabel, _detailLabel]) [view removeObserver:self forKeyPath:@"text"];
    for (UIView *view in [self hideableControls]) [view removeObserver:self forKeyPath:@"hidden"];
}
@end
