#pragma once

#import <AppKit/AppKit.h>

@interface QDragToGrantAppDragSourceView : NSView <NSDraggingSource, NSPasteboardItemDataProvider>
- (instancetype)initWithDisplayName:(NSString*)displayName
                          bundleURL:(NSURL*)bundleURL
                               icon:(NSImage*)icon
                             onDrop:(void (^_Nullable)(void))onDrop;
@end
