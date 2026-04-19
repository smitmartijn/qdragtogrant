#import "qdragtogrant/AppDragSourceView.h"

@interface QDragToGrantAppDragSourceView () {
    NSString* _displayName;
    NSURL* _bundleURL;
    NSImage* _icon;
    NSView* _rowView;
    NSView* _iconChrome;
    NSTextField* _label;
    void (^_onDrop)(void);
}
@end

@implementation QDragToGrantAppDragSourceView

- (instancetype)initWithDisplayName:(NSString*)displayName
                          bundleURL:(NSURL*)bundleURL
                               icon:(NSImage*)icon
                             onDrop:(void (^_Nullable)(void))onDrop {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _displayName = [displayName copy];
    _bundleURL = bundleURL;
    _icon = icon;
    _onDrop = [onDrop copy];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setupViews];
    [self updateAppearance];
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    return YES;
}

- (void)mouseDown:(NSEvent*)event {
    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    [item setDataProvider:self forTypes:@[NSPasteboardTypeFileURL]];

    NSDraggingItem* draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:item];
    [draggingItem setDraggingFrame:[self draggingFrame] contents:[self draggingImage]];

    NSDraggingSession* session =
        [self beginDraggingSessionWithItems:@[draggingItem] event:event source:self];
    session.animatesToStartingPositionsOnCancelOrFail = YES;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateAppearance];
}

#pragma mark - NSPasteboardItemDataProvider

- (void)pasteboard:(NSPasteboard*)pasteboard
              item:(NSPasteboardItem*)item
provideDataForType:(NSPasteboardType)type {
    if (![type isEqualToString:NSPasteboardTypeFileURL]) return;
    NSData* data = [_bundleURL.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
    [item setData:data forType:type];
}

#pragma mark - NSDraggingSource

- (void)draggingSession:(NSDraggingSession*)session willBeginAtPoint:(NSPoint)screenPoint {
    _rowView.hidden = YES;
}

- (NSDragOperation)draggingSession:(NSDraggingSession*)session
sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationCopy;
}

- (void)draggingSession:(NSDraggingSession*)session
           endedAtPoint:(NSPoint)screenPoint
              operation:(NSDragOperation)operation {
    _rowView.hidden = NO;
    if (operation != NSDragOperationNone && _onDrop) {
        _onDrop();
    }
}

#pragma mark - Setup

- (void)setupViews {
    self.wantsLayer = YES;

    _rowView = [[NSView alloc] init];
    _rowView.wantsLayer = YES;
    _rowView.layer.cornerRadius = 7;
    _rowView.layer.borderWidth = 1;
    _rowView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_rowView];

    _iconChrome = [[NSView alloc] init];
    _iconChrome.wantsLayer = YES;
    _iconChrome.layer.backgroundColor = [[NSColor whiteColor] colorWithAlphaComponent:0.9].CGColor;
    _iconChrome.layer.cornerRadius = 6;
    _iconChrome.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowView addSubview:_iconChrome];

    NSImageView* iconView = [[NSImageView alloc] init];
    iconView.image = _icon;
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_iconChrome addSubview:iconView];

    _label = [NSTextField labelWithString:_displayName];
    _label.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    _label.textColor = [[NSColor labelColor] colorWithAlphaComponent:0.82];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowView addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_rowView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_rowView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_rowView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_rowView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_rowView.heightAnchor constraintEqualToConstant:43],

        [_iconChrome.leadingAnchor constraintEqualToAnchor:_rowView.leadingAnchor constant:10],
        [_iconChrome.centerYAnchor constraintEqualToAnchor:_rowView.centerYAnchor],
        [_iconChrome.widthAnchor constraintEqualToConstant:26],
        [_iconChrome.heightAnchor constraintEqualToConstant:26],

        [iconView.centerXAnchor constraintEqualToAnchor:_iconChrome.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:_iconChrome.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:22],
        [iconView.heightAnchor constraintEqualToConstant:22],

        [_label.leadingAnchor constraintEqualToAnchor:_iconChrome.trailingAnchor constant:11],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:_rowView.trailingAnchor constant:-12],
        [_label.centerYAnchor constraintEqualToAnchor:_rowView.centerYAnchor],
    ]];
}

- (void)updateAppearance {
    BOOL isDark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]]
                   isEqualToString:NSAppearanceNameDarkAqua];
    if (isDark) {
        _rowView.layer.backgroundColor = [[NSColor whiteColor] colorWithAlphaComponent:0.06].CGColor;
        _rowView.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.08].CGColor;
    } else {
        _rowView.layer.backgroundColor = [[NSColor whiteColor] colorWithAlphaComponent:0.65].CGColor;
        _rowView.layer.borderColor = [NSColor colorWithCalibratedRed:0.87451
                                                               green:0.866667
                                                                blue:0.862745
                                                               alpha:1].CGColor;
    }
}

- (NSRect)draggingFrame {
    return [self convertRect:_rowView.bounds fromView:_rowView];
}

- (NSImage*)draggingImage {
    NSBitmapImageRep* rep = [_rowView bitmapImageRepForCachingDisplayInRect:_rowView.bounds];
    [_rowView cacheDisplayInRect:_rowView.bounds toBitmapImageRep:rep];
    NSImage* image = [[NSImage alloc] initWithSize:_rowView.bounds.size];
    [image addRepresentation:rep];
    return image;
}

@end
