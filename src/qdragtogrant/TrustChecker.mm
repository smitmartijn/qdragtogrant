#include "qdragtogrant/TrustChecker.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

namespace QDragToGrant {

bool isPanelGranted(Panel panel) {
    switch (panel) {
        case Panel::Accessibility:
            return AXIsProcessTrusted();
        case Panel::ScreenRecording:
            if (@available(macOS 10.15, *)) {
                return CGPreflightScreenCaptureAccess();
            }
            return true;
    }
    return false;
}

void resetPanelGrant(Panel panel) {
    QString service = detail::tccServiceName(panel);
    QString bundleId = detail::currentBundleId();
    if (service.isEmpty() || bundleId.isEmpty()) return;
    detail::runTccutilReset(service, bundleId);
    detail::clearLastTrustedCDHash(panel);
}

namespace detail {

QString currentCDHash() {
    SecCodeRef code = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess || !code) {
        return {};
    }
    CFDictionaryRef info = NULL;
    OSStatus status = SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &info);
    CFRelease(code);
    if (status != errSecSuccess || !info) {
        return {};
    }
    NSData* hash = (__bridge NSData*)CFDictionaryGetValue(info, kSecCodeInfoUnique);
    QString hex;
    if (hash && hash.length > 0) {
        const uint8_t* bytes = (const uint8_t*)hash.bytes;
        QString out;
        out.reserve((int)hash.length * 2);
        for (NSUInteger i = 0; i < hash.length; i++) {
            out += QString::asprintf("%02x", bytes[i]);
        }
        hex = out;
    }
    CFRelease(info);
    return hex;
}

QString currentBundleId() {
    NSString* bid = [[NSBundle mainBundle] bundleIdentifier];
    return bid ? QString::fromNSString(bid) : QString();
}

QString tccServiceName(Panel panel) {
    switch (panel) {
        case Panel::Accessibility: return QStringLiteral("Accessibility");
        case Panel::ScreenRecording: return QStringLiteral("ScreenCapture");
    }
    return {};
}

static NSString* defaultsKey(Panel panel) {
    switch (panel) {
        case Panel::Accessibility: return @"org.lostdomain.qdragtogrant.lastTrustedCDHash.Accessibility";
        case Panel::ScreenRecording: return @"org.lostdomain.qdragtogrant.lastTrustedCDHash.ScreenRecording";
    }
    return nil;
}

QString loadLastTrustedCDHash(Panel panel) {
    NSString* key = defaultsKey(panel);
    if (!key) return {};
    NSString* value = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return value ? QString::fromNSString(value) : QString();
}

void saveLastTrustedCDHash(Panel panel, const QString& hash) {
    NSString* key = defaultsKey(panel);
    if (!key) return;
    if (hash.isEmpty()) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:hash.toNSString() forKey:key];
    }
}

void clearLastTrustedCDHash(Panel panel) {
    NSString* key = defaultsKey(panel);
    if (!key) return;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

bool isSignatureDrift(Panel panel) {
    QString saved = loadLastTrustedCDHash(panel);
    if (saved.isEmpty()) return false;
    QString current = currentCDHash();
    if (current.isEmpty()) return false;
    return saved.compare(current, Qt::CaseInsensitive) != 0;
}

bool canPollLive(Panel panel) {
    switch (panel) {
        case Panel::Accessibility: return true;
        case Panel::ScreenRecording: return false;
    }
    return false;
}

bool isActuallyGranted(Panel panel) {
    switch (panel) {
        case Panel::Accessibility: {
            // Pick a long-lived foreign process to query. Deliberately no
            // launchd fallback: launchd runs no accessibility server, so
            // probing it always fails and would report "not granted" forever.
            NSArray<NSRunningApplication*>* finders =
                [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"];
            if (finders.count == 0) {
                NSLog(@"[QDragToGrant] AX cross-process check: Finder not running");
                return false;
            }
            pid_t targetPid = finders.firstObject.processIdentifier;

            AXUIElementRef elem = AXUIElementCreateApplication(targetPid);
            if (!elem) return false;

            // Callers poll this on the main thread, so bound how long an
            // unresponsive target can stall the UI.
            AXUIElementSetMessagingTimeout(elem, 2.0f);

            CFTypeRef value = NULL;
            // kAXRoleAttribute is served by the accessibility runtime and needs
            // no work from the target, so a busy or blocked Finder cannot fail
            // it. It still requires accessibility: an untrusted process gets
            // kAXErrorAPIDisabled. Attributes that make the target do real work
            // (kAXChildrenAttribute enumerates its windows) time out with
            // kAXErrorCannotComplete when it is stuck on e.g. an unreachable
            // network mount, which is indistinguishable from a denial here.
            AXError err = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute, &value);
            if (value) CFRelease(value);
            CFRelease(elem);
            NSLog(@"[QDragToGrant] AX cross-process check: pid=%d err=%d", targetPid, (int)err);
            return err == kAXErrorSuccess;
        }
        case Panel::ScreenRecording:
            // No reliable in-process test (CGPreflight is sticky-cached).
            return false;
    }
    return false;
}

bool runTccutilReset(const QString& service, const QString& bundleId) {
    NSTask* task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/tccutil";
    task.arguments = @[@"reset", service.toNSString(), bundleId.toNSString()];
    @try {
        [task launch];
        [task waitUntilExit];
        return task.terminationStatus == 0;
    } @catch (NSException* e) {
        NSLog(@"[QDragToGrant] tccutil failed: %@", e);
        return false;
    }
}

} // namespace detail
} // namespace QDragToGrant
