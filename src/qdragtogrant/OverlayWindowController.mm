#import "qdragtogrant/OverlayWindowController.h"
#import "qdragtogrant/AppDragSourceView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

static const CGFloat kQDragToGrantBaseHeight = 109;
static const CGFloat kQDragToGrantDriftExtraHeight = 38;
static const CGFloat kQDragToGrantWidth = 530;
static const NSTimeInterval kQDragToGrantLaunchDuration = 0.72;
static const double kQDragToGrantLaunchResponse = 0.72;
static const double kQDragToGrantLaunchDamping = 1.0;
static const CGFloat kQDragToGrantInitialAlpha = 0.9;

static NSSize QDragToGrantWindowSizeFor(BOOL drift) {
    return NSMakeSize(kQDragToGrantWidth, kQDragToGrantBaseHeight + (drift ? kQDragToGrantDriftExtraHeight : 0));
}

#pragma mark - Passive Panel

@interface QDragToGrantPassiveOverlayPanel : NSPanel
@end

@implementation QDragToGrantPassiveOverlayPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

#pragma mark - Content View

@interface QDragToGrantOverlayContentView : NSView {
    void (^_onBack)(void);
    void (^_onReset)(void);
    void (^_onDrop)(void);
    BOOL _driftDetected;
    NSString* _displayName;
    NSString* _panelTitle;
    NSVisualEffectView* _materialView;
    NSView* _tintView;
}
- (instancetype)initWithDisplayName:(NSString*)displayName
                          bundleURL:(NSURL*)bundleURL
                               icon:(NSImage*)icon
                         panelTitle:(NSString*)panelTitle
                      driftDetected:(BOOL)driftDetected
                             onBack:(void (^)(void))onBack
                            onReset:(void (^)(void))onReset
                             onDrop:(void (^)(void))onDrop;

- (void)showSuccessState:(BOOL)needsRestart;
@end

@implementation QDragToGrantOverlayContentView

- (instancetype)initWithDisplayName:(NSString*)displayName
                          bundleURL:(NSURL*)bundleURL
                               icon:(NSImage*)icon
                         panelTitle:(NSString*)panelTitle
                      driftDetected:(BOOL)driftDetected
                             onBack:(void (^)(void))onBack
                            onReset:(void (^)(void))onReset
                             onDrop:(void (^)(void))onDrop {
    NSSize size = QDragToGrantWindowSizeFor(driftDetected);
    self = [super initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    if (!self) return nil;
    _onBack = [onBack copy];
    _onReset = [onReset copy];
    _onDrop = [onDrop copy];
    _driftDetected = driftDetected;
    _displayName = [displayName copy];
    _panelTitle = [panelTitle copy];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setupWithDisplayName:displayName bundleURL:bundleURL icon:icon panelTitle:panelTitle];
    return self;
}

- (void)setupWithDisplayName:(NSString*)displayName
                   bundleURL:(NSURL*)bundleURL
                        icon:(NSImage*)icon
                  panelTitle:(NSString*)panelTitle {
    NSSize size = QDragToGrantWindowSizeFor(_driftDetected);
    NSVisualEffectView* materialView = [[NSVisualEffectView alloc] init];
    materialView.translatesAutoresizingMaskIntoConstraints = NO;
    materialView.material = NSVisualEffectMaterialPopover;
    materialView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    materialView.state = NSVisualEffectStateActive;
    materialView.wantsLayer = YES;
    materialView.layer.cornerRadius = 18;
    materialView.layer.masksToBounds = YES;
    materialView.layer.borderWidth = 0.5;
    materialView.layer.borderColor = [[NSColor separatorColor] colorWithAlphaComponent:0.18].CGColor;
    [self addSubview:materialView];
    _materialView = materialView;

    NSView* tintView = [[NSView alloc] init];
    tintView.translatesAutoresizingMaskIntoConstraints = NO;
    tintView.wantsLayer = YES;
    tintView.layer.backgroundColor = [[NSColor windowBackgroundColor] colorWithAlphaComponent:0.78].CGColor;
    [materialView addSubview:tintView];
    _tintView = tintView;

    NSView* backChrome = [[NSView alloc] init];
    backChrome.translatesAutoresizingMaskIntoConstraints = NO;
    backChrome.wantsLayer = YES;
    backChrome.layer.backgroundColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.95].CGColor;
    backChrome.layer.cornerRadius = 16;
    [materialView addSubview:backChrome];

    NSButton* backButton = [[NSButton alloc] init];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    backButton.bordered = NO;
    if (@available(macOS 11.0, *)) {
        backButton.image = [NSImage imageWithSystemSymbolName:@"chevron.left"
                                     accessibilityDescription:@"Back"];
    }
    backButton.contentTintColor = [[NSColor labelColor] colorWithAlphaComponent:0.72];
    backButton.target = self;
    backButton.action = @selector(backPressed);
    NSButtonCell* cell = (NSButtonCell*)backButton.cell;
    cell.imagePosition = NSImageOnly;
    [backChrome addSubview:backButton];

    NSImageView* arrowView = [[NSImageView alloc] init];
    arrowView.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 11.0, *)) {
        arrowView.image = [NSImage imageWithSystemSymbolName:@"arrow.up"
                                    accessibilityDescription:nil];
        arrowView.symbolConfiguration =
            [NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightBold];
    }
    arrowView.contentTintColor = [NSColor colorWithCalibratedRed:0.15 green:0.54 blue:0.98 alpha:1];
    [materialView addSubview:arrowView];

    NSString* titleString = [NSString stringWithFormat:@"Drag %@ to the list above to allow %@",
                             displayName, panelTitle];
    NSDictionary* attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [[NSColor labelColor] colorWithAlphaComponent:0.82],
    };
    NSAttributedString* attrTitle = [[NSAttributedString alloc] initWithString:titleString
                                                                    attributes:attrs];
    NSTextField* titleLabel = [NSTextField labelWithAttributedString:attrTitle];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.maximumNumberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [materialView addSubview:titleLabel];

    void (^dropForward)(void) = nil;
    if (_onDrop) {
        __weak typeof(self) weakSelf = self;
        dropForward = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_onDrop) strongSelf->_onDrop();
        };
    }
    QDragToGrantAppDragSourceView* dragSource =
        [[QDragToGrantAppDragSourceView alloc] initWithDisplayName:displayName
                                                    bundleURL:bundleURL
                                                         icon:icon
                                                       onDrop:dropForward];
    [materialView addSubview:dragSource];

    NSMutableArray<NSLayoutConstraint*>* constraints = [NSMutableArray arrayWithArray:@[
        [self.widthAnchor constraintEqualToConstant:size.width],
        [self.heightAnchor constraintEqualToConstant:size.height],

        [materialView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [materialView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [materialView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [materialView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [tintView.leadingAnchor constraintEqualToAnchor:materialView.leadingAnchor],
        [tintView.trailingAnchor constraintEqualToAnchor:materialView.trailingAnchor],
        [tintView.topAnchor constraintEqualToAnchor:materialView.topAnchor],
        [tintView.bottomAnchor constraintEqualToAnchor:materialView.bottomAnchor],

        [backChrome.leadingAnchor constraintEqualToAnchor:materialView.leadingAnchor constant:18],
        [backChrome.topAnchor constraintEqualToAnchor:materialView.topAnchor constant:52],
        [backChrome.widthAnchor constraintEqualToConstant:32],
        [backChrome.heightAnchor constraintEqualToConstant:32],

        [backButton.centerXAnchor constraintEqualToAnchor:backChrome.centerXAnchor],
        [backButton.centerYAnchor constraintEqualToAnchor:backChrome.centerYAnchor],
        [backButton.widthAnchor constraintEqualToConstant:14],
        [backButton.heightAnchor constraintEqualToConstant:14],

        [arrowView.leadingAnchor constraintEqualToAnchor:materialView.leadingAnchor constant:35],
        [arrowView.topAnchor constraintEqualToAnchor:materialView.topAnchor constant:10],
        [arrowView.widthAnchor constraintEqualToConstant:28],
        [arrowView.heightAnchor constraintEqualToConstant:28],

        [titleLabel.leadingAnchor constraintEqualToAnchor:arrowView.trailingAnchor constant:10],
        [titleLabel.centerYAnchor constraintEqualToAnchor:arrowView.centerYAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:materialView.trailingAnchor constant:-22],

        [dragSource.leadingAnchor constraintEqualToAnchor:materialView.leadingAnchor constant:64],
        [dragSource.trailingAnchor constraintEqualToAnchor:materialView.trailingAnchor constant:-21],
        [dragSource.topAnchor constraintEqualToAnchor:materialView.topAnchor constant:47],
        [dragSource.heightAnchor constraintEqualToConstant:43],
    ]];

    if (_driftDetected) {
        NSDictionary* footAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.85],
        };
        NSAttributedString* footText = [[NSAttributedString alloc]
            initWithString:@"Already in the list but not working? The signature changed since you granted access."
                attributes:footAttrs];
        NSTextField* footLabel = [NSTextField labelWithAttributedString:footText];
        footLabel.translatesAutoresizingMaskIntoConstraints = NO;
        footLabel.maximumNumberOfLines = 1;
        footLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [materialView addSubview:footLabel];

        NSButton* resetButton = [[NSButton alloc] init];
        resetButton.translatesAutoresizingMaskIntoConstraints = NO;
        resetButton.bezelStyle = NSBezelStyleRounded;
        resetButton.controlSize = NSControlSizeSmall;
        resetButton.title = @"Reset & Re-add";
        resetButton.target = self;
        resetButton.action = @selector(resetPressed);
        [materialView addSubview:resetButton];

        [constraints addObjectsFromArray:@[
            [footLabel.leadingAnchor constraintEqualToAnchor:materialView.leadingAnchor constant:22],
            [footLabel.topAnchor constraintEqualToAnchor:dragSource.bottomAnchor constant:11],
            [footLabel.trailingAnchor constraintLessThanOrEqualToAnchor:resetButton.leadingAnchor constant:-12],

            [resetButton.trailingAnchor constraintEqualToAnchor:materialView.trailingAnchor constant:-18],
            [resetButton.centerYAnchor constraintEqualToAnchor:footLabel.centerYAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)resetPressed {
    if (_onReset) _onReset();
}

- (void)backPressed {
    if (_onBack) _onBack();
}

- (void)showSuccessState:(BOOL)needsRestart {
    if (!_materialView) return;

    // Hide every subview of the material view except the blurred tint.
    for (NSView* sub in [_materialView.subviews copy]) {
        if (sub != _tintView) sub.hidden = YES;
    }

    NSView* successView = [[NSView alloc] init];
    successView.translatesAutoresizingMaskIntoConstraints = NO;
    successView.wantsLayer = YES;
    [_materialView addSubview:successView];

    NSImageView* check = [[NSImageView alloc] init];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 11.0, *)) {
        check.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
                                accessibilityDescription:@"Granted"];
        check.symbolConfiguration =
            [NSImageSymbolConfiguration configurationWithPointSize:34 weight:NSFontWeightSemibold];
    }
    check.contentTintColor = [NSColor colorWithCalibratedRed:0.20 green:0.74 blue:0.36 alpha:1];
    [successView addSubview:check];

    NSString* primaryStr;
    if (needsRestart) {
        primaryStr = [NSString stringWithFormat:@"%@ enabled — restart %@ to take effect",
                                                _panelTitle, _displayName];
    } else {
        primaryStr = [NSString stringWithFormat:@"%@ access granted", _panelTitle];
    }
    NSDictionary* primaryAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
    NSAttributedString* primaryAttr = [[NSAttributedString alloc] initWithString:primaryStr
                                                                      attributes:primaryAttrs];
    NSTextField* primaryLabel = [NSTextField labelWithAttributedString:primaryAttr];
    primaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    primaryLabel.maximumNumberOfLines = 2;
    primaryLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [successView addSubview:primaryLabel];

    [NSLayoutConstraint activateConstraints:@[
        [successView.leadingAnchor constraintEqualToAnchor:_materialView.leadingAnchor],
        [successView.trailingAnchor constraintEqualToAnchor:_materialView.trailingAnchor],
        [successView.topAnchor constraintEqualToAnchor:_materialView.topAnchor],
        [successView.bottomAnchor constraintEqualToAnchor:_materialView.bottomAnchor],

        [check.leadingAnchor constraintEqualToAnchor:successView.leadingAnchor constant:24],
        [check.centerYAnchor constraintEqualToAnchor:successView.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:38],
        [check.heightAnchor constraintEqualToConstant:38],

        [primaryLabel.leadingAnchor constraintEqualToAnchor:check.trailingAnchor constant:14],
        [primaryLabel.trailingAnchor constraintEqualToAnchor:successView.trailingAnchor constant:-22],
        [primaryLabel.centerYAnchor constraintEqualToAnchor:successView.centerYAnchor],
    ]];
}

@end

#pragma mark - Window Controller

@interface QDragToGrantOverlayWindowController () {
    void (^_onBack)(void);
    void (^_onReset)(void);
    BOOL _driftDetected;
    NSSize _windowSize;
    CADisplayLink* _launchDisplayLink;
    NSTimer* _launchFallbackTimer;
    CFTimeInterval _launchStartTime;
    NSRect _launchFromFrame;
    NSRect _launchToFrame;
    BOOL _isAnimatingLaunch;
}
@end

@implementation QDragToGrantOverlayWindowController

- (instancetype)initWithDisplayName:(NSString*)displayName
                          bundleURL:(NSURL*)bundleURL
                               icon:(NSImage*)icon
                         panelTitle:(NSString*)panelTitle
                      driftDetected:(BOOL)driftDetected
                             onBack:(void (^)(void))onBack
                            onReset:(void (^)(void))onReset
                             onDrop:(void (^_Nullable)(void))onDrop {
    NSSize size = QDragToGrantWindowSizeFor(driftDetected);
    NSPanel* window = [[QDragToGrantPassiveOverlayPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                  styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self = [super initWithWindow:window];
    if (!self) return nil;
    _onBack = [onBack copy];
    _onReset = [onReset copy];
    _driftDetected = driftDetected;
    _windowSize = size;
    [self configureWindow:window];
    window.contentView = [[QDragToGrantOverlayContentView alloc] initWithDisplayName:displayName
                                                                      bundleURL:bundleURL
                                                                           icon:icon
                                                                     panelTitle:panelTitle
                                                                  driftDetected:driftDetected
                                                                         onBack:onBack
                                                                        onReset:onReset
                                                                         onDrop:onDrop];
    return self;
}

- (void)showSuccessState:(BOOL)needsRestart {
    QDragToGrantOverlayContentView* content = (QDragToGrantOverlayContentView*)self.window.contentView;
    if ([content respondsToSelector:@selector(showSuccessState:)]) {
        [content showSuccessState:needsRestart];
    }
}

- (void)configureWindow:(NSWindow*)window {
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.level = NSStatusWindowLevel;
    window.hasShadow = YES;
    window.hidesOnDeactivate = NO;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                              | NSWindowCollectionBehaviorStationary
                              | NSWindowCollectionBehaviorIgnoresCycle
                              | NSWindowCollectionBehaviorFullScreenAuxiliary;
    window.animationBehavior = NSWindowAnimationBehaviorNone;
}

- (void)close {
    [self stopLaunchAnimation];
    [self.window orderOut:nil];
    [super close];
}

- (void)presentFrom:(NSValue* _Nullable)sourceFrameValue
      settingsFrame:(NSRect)settingsFrame
       visibleFrame:(NSRect)visibleFrame {
    [self stopLaunchAnimation];
    NSWindow* window = self.window;
    if (!window) return;

    NSPoint targetOrigin = [self anchoredOriginForSettingsFrame:settingsFrame visibleFrame:visibleFrame];
    NSRect targetFrame = NSMakeRect(targetOrigin.x, targetOrigin.y,
                                    _windowSize.width, _windowSize.height);

    if (!sourceFrameValue || NSIsEmptyRect(sourceFrameValue.rectValue)) {
        _isAnimatingLaunch = NO;
        window.alphaValue = 1.0;
        [window setFrame:targetFrame display:NO];
        [window orderFrontRegardless];
        return;
    }

    NSRect sourceFrame = sourceFrameValue.rectValue;
    _isAnimatingLaunch = YES;
    _launchFromFrame = sourceFrame;
    _launchToFrame = targetFrame;
    _launchStartTime = CACurrentMediaTime();

    window.alphaValue = kQDragToGrantInitialAlpha;
    [window setFrame:sourceFrame display:NO];
    [window orderFrontRegardless];
    [self stepLaunchAnimation];

    if (@available(macOS 14.0, *)) {
        CADisplayLink* link = [window displayLinkWithTarget:self
                                                   selector:@selector(displayLinkDidFire:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _launchDisplayLink = link;
    } else {
        __weak typeof(self) weakSelf = self;
        _launchFallbackTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                               repeats:YES
                                                                 block:^(NSTimer* _) {
            [weakSelf stepLaunchAnimation];
        }];
    }
}

- (void)updatePositionWithSettingsFrame:(NSRect)settingsFrame
                           visibleFrame:(NSRect)visibleFrame {
    NSWindow* window = self.window;
    if (!window) return;
    NSPoint origin = [self anchoredOriginForSettingsFrame:settingsFrame visibleFrame:visibleFrame];
    _launchToFrame.origin = origin;
    if (_isAnimatingLaunch) return;
    [window setFrameOrigin:origin];
    [window orderFrontRegardless];
}

- (void)hideOverlay {
    _isAnimatingLaunch = NO;
    [self stopLaunchAnimation];
    [self.window orderOut:nil];
}

- (void)stepLaunchAnimation {
    NSWindow* window = self.window;
    if (!window) {
        [self stopLaunchAnimation];
        return;
    }
    CFTimeInterval elapsed = MAX(0, CACurrentMediaTime() - _launchStartTime);
    if (elapsed >= kQDragToGrantLaunchDuration) {
        _isAnimatingLaunch = NO;
        [self stopLaunchAnimation];
        window.alphaValue = 1.0;
        [window setFrame:_launchToFrame display:YES];
        return;
    }
    CGFloat progress = [self springProgressAt:elapsed];
    window.alphaValue = kQDragToGrantInitialAlpha + ((1 - kQDragToGrantInitialAlpha) * progress);
    [window setFrame:[self curvedFrameFrom:_launchFromFrame to:_launchToFrame progress:progress]
             display:YES];
}

- (void)displayLinkDidFire:(CADisplayLink*)link {
    [self stepLaunchAnimation];
}

- (void)stopLaunchAnimation {
    [_launchDisplayLink invalidate];
    _launchDisplayLink = nil;
    [_launchFallbackTimer invalidate];
    _launchFallbackTimer = nil;
}

- (CGFloat)springProgressAt:(NSTimeInterval)elapsed {
    double omega = (2.0 * M_PI) / kQDragToGrantLaunchResponse;
    double t = MAX(0, elapsed);
    double progress;
    if (fabs(kQDragToGrantLaunchDamping - 1.0) < 0.0001) {
        progress = 1 - exp(-omega * t) * (1 + omega * t);
    } else {
        progress = MIN(1, t / kQDragToGrantLaunchDuration);
    }
    return MIN(MAX(progress, 0), 1);
}

- (NSRect)curvedFrameFrom:(NSRect)from to:(NSRect)to progress:(CGFloat)progress {
    NSSize size = NSMakeSize(
        from.size.width + (to.size.width - from.size.width) * progress,
        from.size.height + (to.size.height - from.size.height) * progress);

    CGPoint startCenter = CGPointMake(NSMidX(from), NSMidY(from));
    CGPoint endCenter = CGPointMake(NSMidX(to), NSMidY(to));
    CGPoint midPoint = CGPointMake((startCenter.x + endCenter.x) * 0.5,
                                   MAX(startCenter.y, endCenter.y));
    CGFloat distance = hypot(endCenter.x - startCenter.x, endCenter.y - startCenter.y);
    CGFloat lift = MIN(140.0, MAX(44.0, distance * 0.18));
    CGPoint controlPoint = CGPointMake(midPoint.x, midPoint.y + lift);
    CGFloat inverse = 1 - progress;
    CGPoint center = CGPointMake(
        inverse * inverse * startCenter.x + 2 * inverse * progress * controlPoint.x +
            progress * progress * endCenter.x,
        inverse * inverse * startCenter.y + 2 * inverse * progress * controlPoint.y +
            progress * progress * endCenter.y);

    return NSMakeRect(center.x - size.width * 0.5,
                      center.y - size.height * 0.5,
                      size.width, size.height);
}

- (NSPoint)anchoredOriginForSettingsFrame:(NSRect)settingsFrame
                             visibleFrame:(NSRect)visibleFrame {
    CGFloat sidebarWidth = 170.0;
    CGFloat contentMinX = NSMinX(settingsFrame) + sidebarWidth;
    CGFloat contentWidth = MAX(NSWidth(settingsFrame) - sidebarWidth, _windowSize.width);
    CGFloat preferredX = contentMinX + (contentWidth - _windowSize.width) / 2.0 - 8.0;
    CGFloat preferredY = NSMinY(settingsFrame) + 14.0;
    CGFloat minX = NSMinX(visibleFrame) + 8.0;
    CGFloat maxX = NSMaxX(visibleFrame) - _windowSize.width - 8.0;
    CGFloat minY = NSMinY(visibleFrame) + 8.0;
    CGFloat maxY = NSMaxY(visibleFrame) - _windowSize.height - 8.0;

    return NSMakePoint(MIN(MAX(preferredX, minX), maxX),
                       MIN(MAX(preferredY, minY), maxY));
}

@end
