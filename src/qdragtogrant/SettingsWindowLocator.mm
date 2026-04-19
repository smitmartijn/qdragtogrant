#import "qdragtogrant/SettingsWindowLocator.h"

#import <CoreGraphics/CoreGraphics.h>

@implementation QDragToGrantSettingsWindowSnapshot
@end

@implementation QDragToGrantSettingsWindowLocator

static NSString* const kSettingsBundleId = @"com.apple.systempreferences";

+ (BOOL)isSystemSettingsFrontmost {
    return [[[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier
            isEqualToString:kSettingsBundleId];
}

+ (QDragToGrantSettingsWindowSnapshot* _Nullable)frontmostWindow {
    if (![self isSystemSettingsFrontmost]) {
        return nil;
    }

    NSArray<NSRunningApplication*>* apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:kSettingsBundleId];
    NSRunningApplication* app = nil;
    for (NSRunningApplication* candidate in apps) {
        if (candidate.activationPolicy != NSApplicationActivationPolicyProhibited) {
            app = candidate;
            break;
        }
    }
    if (!app) app = apps.firstObject;
    if (!app) return nil;

    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!windowList) return nil;

    QDragToGrantSettingsWindowSnapshot* best = nil;
    CGFloat bestArea = 0;
    NSArray* windows = (__bridge NSArray*)windowList;

    for (NSDictionary* info in windows) {
        NSNumber* ownerPID = info[(id)kCGWindowOwnerPID];
        if (ownerPID.intValue != app.processIdentifier) continue;
        NSNumber* layer = info[(id)kCGWindowLayer];
        if (layer.intValue != 0) continue;
        NSDictionary* boundsDict = info[(id)kCGWindowBounds];
        if (!boundsDict) continue;

        CGRect cgFrame = CGRectMake(
            [boundsDict[@"X"] doubleValue],
            [boundsDict[@"Y"] doubleValue],
            [boundsDict[@"Width"] doubleValue],
            [boundsDict[@"Height"] doubleValue]);

        if (cgFrame.size.width <= 320 || cgFrame.size.height <= 240) continue;

        NSRect appkitFrame = NSZeroRect;
        NSRect visibleFrame = NSZeroRect;
        [self appkitGeometryFromCG:cgFrame outFrame:&appkitFrame outVisible:&visibleFrame];

        CGFloat area = appkitFrame.size.width * appkitFrame.size.height;
        if (area > bestArea) {
            bestArea = area;
            QDragToGrantSettingsWindowSnapshot* snap = [[QDragToGrantSettingsWindowSnapshot alloc] init];
            snap.pid = ownerPID.intValue;
            snap.frame = appkitFrame;
            snap.visibleFrame = visibleFrame;
            best = snap;
        }
    }

    CFRelease(windowList);
    return best;
}

+ (void)appkitGeometryFromCG:(CGRect)cgFrame
                    outFrame:(NSRect*)outFrame
                  outVisible:(NSRect*)outVisible {
    NSScreen* matchedScreen = nil;
    CGRect matchedCGBounds = CGRectZero;
    CGFloat bestIntersection = 0;

    for (NSScreen* screen in [NSScreen screens]) {
        NSNumber* number = screen.deviceDescription[@"NSScreenNumber"];
        if (!number) continue;
        CGDirectDisplayID displayID = (CGDirectDisplayID)number.unsignedIntValue;
        CGRect cgBounds = CGDisplayBounds(displayID);
        CGRect intersection = CGRectIntersection(cgBounds, cgFrame);
        if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) continue;
        CGFloat area = intersection.size.width * intersection.size.height;
        if (area > bestIntersection) {
            bestIntersection = area;
            matchedScreen = screen;
            matchedCGBounds = cgBounds;
        }
    }

    if (!matchedScreen) {
        NSScreen* main = [NSScreen mainScreen];
        *outFrame = cgFrame;
        *outVisible = main ? main.visibleFrame
                           : NSMakeRect(0, 0, cgFrame.size.width, cgFrame.size.height);
        return;
    }

    CGFloat localX = cgFrame.origin.x - matchedCGBounds.origin.x;
    CGFloat localY = cgFrame.origin.y - matchedCGBounds.origin.y;
    *outFrame = NSMakeRect(
        matchedScreen.frame.origin.x + localX,
        NSMaxY(matchedScreen.frame) - localY - cgFrame.size.height,
        cgFrame.size.width,
        cgFrame.size.height);
    *outVisible = matchedScreen.visibleFrame;
}

@end
