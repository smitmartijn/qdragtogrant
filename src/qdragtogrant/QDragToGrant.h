#pragma once

#include <QtCore/QString>
#include <QtCore/QRect>

namespace QDragToGrant {

    enum class Panel {
        Accessibility,
        ScreenRecording,
    };

    QString panelTitle(Panel panel);
    QString panelSettingsURL(Panel panel);

    // Returns true if the current process has been granted access for the panel.
    bool isPanelGranted(Panel panel);

    // Removes the host bundle's TCC entry for the given panel by invoking
    // `tccutil reset <service> <bundleId>`. No admin prompt; only affects the
    // host bundle. Use when a stale signature entry is blocking re-grant.
    void resetPanelGrant(Panel panel);

    struct HostApp {
        QString displayName;
        QString bundlePath;

        static HostApp current();
    };

    class Assistant {
    public:
        static Assistant& shared();

        void present(Panel panel, const QRect& sourceFrameInScreen = {});
        void present(Panel panel, const HostApp& host, const QRect& sourceFrameInScreen = {});
        void dismiss();

    private:
        Assistant();
        ~Assistant();
        Assistant(const Assistant&) = delete;
        Assistant& operator=(const Assistant&) = delete;
        void* impl_;
    };

} // namespace QDragToGrant
