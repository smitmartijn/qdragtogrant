#pragma once

#import <AppKit/AppKit.h>

@interface QDragToGrantSettingsWindowSnapshot : NSObject
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) NSRect frame;
@property (nonatomic, assign) NSRect visibleFrame;
@end

@interface QDragToGrantSettingsWindowLocator : NSObject
+ (BOOL)isSystemSettingsFrontmost;
+ (QDragToGrantSettingsWindowSnapshot* _Nullable)frontmostWindow;

@end
