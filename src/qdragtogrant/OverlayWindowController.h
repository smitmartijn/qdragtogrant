#pragma once

#import <AppKit/AppKit.h>

@interface QDragToGrantOverlayWindowController : NSWindowController
- (instancetype)initWithDisplayName:(NSString*)displayName
                          bundleURL:(NSURL*)bundleURL
                               icon:(NSImage*)icon
                         panelTitle:(NSString*)panelTitle
                      driftDetected:(BOOL)driftDetected
                             onBack:(void (^)(void))onBack
                            onReset:(void (^)(void))onReset
                             onDrop:(void (^_Nullable)(void))onDrop;

- (void)presentFrom:(NSValue* _Nullable)sourceFrameValue
      settingsFrame:(NSRect)settingsFrame
       visibleFrame:(NSRect)visibleFrame;

- (void)updatePositionWithSettingsFrame:(NSRect)settingsFrame
                           visibleFrame:(NSRect)visibleFrame;

- (void)hideOverlay;

// Replace the drag prompt with a green checkmark + success message. If
// `needsRestart` is YES, the message asks the user to relaunch the host app.
- (void)showSuccessState:(BOOL)needsRestart;

@end
