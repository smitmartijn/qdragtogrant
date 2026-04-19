#include "qdragtogrant/QDragToGrant.h"
#include "qdragtogrant/TrustChecker.h"
#import "qdragtogrant/SettingsWindowLocator.h"
#import "qdragtogrant/OverlayWindowController.h"

#import <AppKit/AppKit.h>

@interface QDragToGrantAssistantImpl : NSObject {
    QDragToGrantOverlayWindowController* _overlay;
    NSTimer* _trackingTimer;
    NSTimer* _grantPollTimer;
    id _activationObserver;
    BOOL _hasPendingSourceFrame;
    NSRect _pendingSourceFrame;
    BOOL _didPresentCurrent;
    BOOL _inSuccessState;
    QDragToGrant::Panel _activePanel;
}

- (void)presentPanel:(QDragToGrant::Panel)panel
                host:(const QDragToGrant::HostApp&)host
         sourceFrame:(const QRect&)sourceFrame;
- (void)dismiss;
@end

@implementation QDragToGrantAssistantImpl

- (NSScreen*)primaryScreen {
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSEqualPoints(screen.frame.origin, NSZeroPoint)) return screen;
    }
    return [NSScreen mainScreen];
}

- (NSRect)appkitRectFromQRect:(const QRect&)rect {
    if (rect.isEmpty()) return NSZeroRect;
    NSScreen* primary = [self primaryScreen];
    CGFloat primaryHeight = primary.frame.size.height;
    return NSMakeRect((CGFloat)rect.x(),
                      primaryHeight - (CGFloat)rect.y() - (CGFloat)rect.height(),
                      (CGFloat)rect.width(),
                      (CGFloat)rect.height());
}

- (void)openSettingsURLForPanel:(QDragToGrant::Panel)panel {
    NSString* urlString = QDragToGrant::panelSettingsURL(panel).toNSString();
    NSURL* settingsURL = [NSURL URLWithString:urlString];
    if (settingsURL) {
        [[NSWorkspace sharedWorkspace] openURL:settingsURL];
    }
}

- (void)presentPanel:(QDragToGrant::Panel)panel
                host:(const QDragToGrant::HostApp&)host
         sourceFrame:(const QRect&)sourceFrame {
    [self dismiss];
    _activePanel = panel;

    // Opportunistically record the current CDHash if we are observed as granted,
    // so future drift can be detected. Do NOT use this to skip the overlay:
    // AXIsProcessTrusted / CGPreflightScreenCaptureAccess can return stale "true"
    // after the user has revoked access — most commonly because the value is
    // cached for the process lifetime and only refreshes on real API use.
    if (QDragToGrant::isPanelGranted(panel)) {
        QString currentHash = QDragToGrant::detail::currentCDHash();
        if (!currentHash.isEmpty()) {
            QDragToGrant::detail::saveLastTrustedCDHash(panel, currentHash);
        }
    }

    BOOL drift = QDragToGrant::detail::isSignatureDrift(panel) ? YES : NO;
    NSLog(@"[QDragToGrant] present panel=%d drift=%d sourceFrame=%dx%d@(%d,%d)",
          (int)panel, drift,
          sourceFrame.width(), sourceFrame.height(),
          sourceFrame.x(), sourceFrame.y());

    _hasPendingSourceFrame = !sourceFrame.isEmpty();
    _pendingSourceFrame = [self appkitRectFromQRect:sourceFrame];
    _didPresentCurrent = NO;

    NSString* displayName = host.displayName.toNSString();
    NSString* bundlePath = host.bundlePath.toNSString();
    NSURL* bundleURL = bundlePath.length > 0 ? [NSURL fileURLWithPath:bundlePath] : nil;
    NSImage* icon = bundlePath.length > 0
        ? [[NSWorkspace sharedWorkspace] iconForFile:bundlePath]
        : nil;
    icon.size = NSMakeSize(48, 48);

    NSString* panelTitleStr = QDragToGrant::panelTitle(panel).toNSString();

    BOOL pollable = QDragToGrant::detail::canPollLive(panel);
    _inSuccessState = NO;

    __weak typeof(self) weakSelf = self;
    QDragToGrant::HostApp hostCopy = host;
    QRect sourceCopy = sourceFrame;
    _overlay = [[QDragToGrantOverlayWindowController alloc]
        initWithDisplayName:displayName
                  bundleURL:bundleURL
                       icon:icon
                 panelTitle:panelTitleStr
              driftDetected:drift
                     onBack:^{
        [weakSelf dismiss];
    }
                    onReset:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        QDragToGrant::Panel p = strongSelf->_activePanel;
        QString service = QDragToGrant::detail::tccServiceName(p);
        QString bundleId = QDragToGrant::detail::currentBundleId();
        if (!service.isEmpty() && !bundleId.isEmpty()) {
            QDragToGrant::detail::runTccutilReset(service, bundleId);
        }
        QDragToGrant::detail::clearLastTrustedCDHash(p);
        // Re-present in normal (non-drift) flow.
        [strongSelf presentPanel:p host:hostCopy sourceFrame:sourceCopy];
    }
                     onDrop:^{
        // Only used for non-pollable panels (e.g. Screen Recording).
        // Pollable panels detect success live via the grant timer.
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_inSuccessState) return;
        if (QDragToGrant::detail::canPollLive(strongSelf->_activePanel)) return;
        [strongSelf enterSuccessStateNeedsRestart:YES];
    }];

    [self openSettingsURLForPanel:panel];
    [self startTracking];
    if (pollable) {
        [self startGrantPolling];
    }
}

- (void)startGrantPolling {
    [_grantPollTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _grantPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      repeats:YES
                                                        block:^(NSTimer* _) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_inSuccessState) return;
        if (QDragToGrant::detail::isActuallyGranted(strongSelf->_activePanel)) {
            NSLog(@"[QDragToGrant] grant detected via live poll");
            [strongSelf enterSuccessStateNeedsRestart:NO];
        }
    }];
}

- (void)enterSuccessStateNeedsRestart:(BOOL)needsRestart {
    if (_inSuccessState) return;
    _inSuccessState = YES;

    // Stop tracking + polling so the success message stays put.
    [_trackingTimer invalidate];
    _trackingTimer = nil;
    [_grantPollTimer invalidate];
    _grantPollTimer = nil;
    if (_activationObserver) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:_activationObserver];
        _activationObserver = nil;
    }

    // Save current CDHash now that we know we are truly granted.
    if (!needsRestart) {
        QString hash = QDragToGrant::detail::currentCDHash();
        if (!hash.isEmpty()) {
            QDragToGrant::detail::saveLastTrustedCDHash(_activePanel, hash);
        }
    }

    [_overlay showSuccessState:needsRestart];

    // Auto-dismiss the live-detected case after a short read time.
    // For the restart case, leave it up so the user can read and act.
    if (!needsRestart) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf dismiss];
        });
    }
}

- (void)dismiss {
    [_trackingTimer invalidate];
    _trackingTimer = nil;
    [_grantPollTimer invalidate];
    _grantPollTimer = nil;
    if (_activationObserver) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:_activationObserver];
        _activationObserver = nil;
    }
    [_overlay close];
    _overlay = nil;
    _hasPendingSourceFrame = NO;
    _didPresentCurrent = NO;
    _inSuccessState = NO;
}

- (void)startTracking {
    [_trackingTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _trackingTimer = [NSTimer scheduledTimerWithTimeInterval:0.15
                                                     repeats:YES
                                                       block:^(NSTimer* _) {
        [weakSelf refreshPosition];
    }];
    if (_activationObserver) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:_activationObserver];
    }
    _activationObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserverForName:NSWorkspaceDidActivateApplicationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* _Nonnull note) {
        [weakSelf refreshPosition];
    }];
    [self refreshPosition];
}

- (void)refreshPosition {
    BOOL frontmost = [QDragToGrantSettingsWindowLocator isSystemSettingsFrontmost];
    QDragToGrantSettingsWindowSnapshot* snapshot = [QDragToGrantSettingsWindowLocator frontmostWindow];
    if (!snapshot) {
        NSLog(@"[QDragToGrant] refresh: no settings window (frontmost=%d), hiding overlay", frontmost);
        [_overlay hideOverlay];
        return;
    }
    NSLog(@"[QDragToGrant] refresh: settings window %g x %g at (%g,%g) didPresent=%d",
          snapshot.frame.size.width, snapshot.frame.size.height,
          snapshot.frame.origin.x, snapshot.frame.origin.y,
          _didPresentCurrent);
    if (_didPresentCurrent) {
        [_overlay updatePositionWithSettingsFrame:snapshot.frame
                                     visibleFrame:snapshot.visibleFrame];
        return;
    }
    NSValue* sourceValue = _hasPendingSourceFrame
        ? [NSValue valueWithRect:_pendingSourceFrame]
        : nil;
    [_overlay presentFrom:sourceValue
            settingsFrame:snapshot.frame
             visibleFrame:snapshot.visibleFrame];
    _didPresentCurrent = YES;
}

@end

namespace QDragToGrant {

Assistant& Assistant::shared() {
    static Assistant instance;
    return instance;
}

Assistant::Assistant() {
    impl_ = (__bridge_retained void*)[[QDragToGrantAssistantImpl alloc] init];
}

Assistant::~Assistant() {
    if (impl_) {
        CFRelease(impl_);
        impl_ = nullptr;
    }
}

void Assistant::present(Panel panel, const QRect& sourceFrameInScreen) {
    present(panel, HostApp::current(), sourceFrameInScreen);
}

void Assistant::present(Panel panel, const HostApp& host, const QRect& sourceFrameInScreen) {
    QDragToGrantAssistantImpl* impl = (__bridge QDragToGrantAssistantImpl*)impl_;
    [impl presentPanel:panel host:host sourceFrame:sourceFrameInScreen];
}

void Assistant::dismiss() {
    QDragToGrantAssistantImpl* impl = (__bridge QDragToGrantAssistantImpl*)impl_;
    [impl dismiss];
}

} // namespace QDragToGrant
