#include "qdragtogrant/QDragToGrant.h"

namespace QDragToGrant {

    QString panelTitle(Panel panel) {
        switch (panel) {
            case Panel::Accessibility: return QStringLiteral("Accessibility");
            case Panel::ScreenRecording: return QStringLiteral("Screen Recording");
        }
        return {};
    }

    QString panelSettingsURL(Panel panel) {
        const char* key = "Privacy_Accessibility";
        switch (panel) {
            case Panel::Accessibility: key = "Privacy_Accessibility"; break;
            case Panel::ScreenRecording: key = "Privacy_ScreenCapture"; break;
        }
        return QStringLiteral("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?%1")
            .arg(QString::fromLatin1(key));
    }

} // namespace QDragToGrant
