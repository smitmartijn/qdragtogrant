#include "qdragtogrant/QDragToGrant.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

namespace QDragToGrant {

HostApp HostApp::current() {
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (!displayName) {
        displayName = [bundle objectForInfoDictionaryKey:(NSString*)kCFBundleNameKey];
    }
    if (!displayName) {
        displayName = [[bundle.bundleURL URLByDeletingPathExtension] lastPathComponent];
    }

    HostApp host;
    host.displayName = QString::fromNSString(displayName ?: @"App");
    host.bundlePath = QString::fromNSString(bundle.bundleURL.path ?: @"");
    return host;
}

} // namespace QDragToGrant
