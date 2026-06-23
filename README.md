# QDragToGrant

![](./docs/example-app.gif)

Qt 6 / C++ library for macOS that helps users grant Privacy & Security permissions (Accessibility, Screen Recording, etc.) via a drag-helper overlay placed over System Settings. Includes signature-drift detection and a `tccutil reset` flow for clearing stale TCC entries.

## Build

Requires Qt 6, CMake 3.20+, macOS 14+, Xcode command line tools.

```sh
cmake -S . -B build -DCMAKE_PREFIX_PATH=$HOME/Qt/6.11.1/macos
cmake --build build
open build/QDragToGrantSample.app
```

## API

```cpp
#include "qdragtogrant/QDragToGrant.h"

QDragToGrant::Assistant::shared().present(QDragToGrant::Panel::Accessibility);
// or with a source rect for the launch animation
QDragToGrant::Assistant::shared().present(QDragToGrant::Panel::ScreenRecording, button->geometry());

// Query whether the current process has the grant.
bool ok = QDragToGrant::isPanelGranted(QDragToGrant::Panel::Accessibility);

// Manually clear a stale TCC entry (runs `tccutil reset`).
QDragToGrant::resetPanelGrant(QDragToGrant::Panel::Accessibility);
```

`QRect` is in Qt screen coordinates (top-left origin, virtual desktop). The library converts to AppKit coordinates internally.

## Signature drift handling

`present()` always shows the helper. It additionally:

- **Records the current CDHash** to `NSUserDefaults` if `AXIsProcessTrusted()` / `CGPreflightScreenCaptureAccess()` reports trust at call time, so future signature changes can be compared against it.
- **Compares saved vs. current CDHash.** If they differ, drift is suspected: the overlay grows by ~38 px and shows a `Reset & Re-add` button. Tapping it runs `/usr/bin/tccutil reset <Service> <bundleId>`, clears the saved hash, and re-presents the helper so the drag adds a fresh entry.

> **Note on `AXIsProcessTrusted` / `CGPreflightScreenCaptureAccess`.** These
> APIs are unreliable for branching UI on. They are cached for the process
> lifetime and can return stale `true` after the user has revoked access in
> System Settings. The library never uses them to skip the overlay — only to
> opportunistically snapshot a CDHash when they say `true`.

The `tccutil reset` flow avoids touching `TCC.db` directly — it is the only supported way to remove a single bundle's entry, and SIP blocks SQLite writes anyway.

## Layout

- `src/qdragtogrant/` — the library
  - `QDragToGrant.h` — public C++ API
  - `QDragToGrantPanel.cpp` — panel enum + URL/title
  - `QDragToGrantHostApp.mm` — host bundle metadata via `NSBundle`
  - `SettingsWindowLocator.{h,mm}` — finds the System Settings window via `CGWindowListCopyWindowInfo`
  - `AppDragSourceView.{h,mm}` — `NSDraggingSource` view that vends the host `.app` as a file URL
  - `OverlayWindowController.{h,mm}` — non-activating `NSPanel` with material chrome and spring launch animation
  - `QDragToGrantAssistant.mm` — singleton wiring opens the settings URL, polls window position, owns overlay lifecycle
- `src/MainWindow.{h,cpp}` and `src/main.cpp` — sample app with two buttons

## Credits & origin

- The drag-helper UX pattern was originated by **[OpenAI Codex](https://openai.com/codex/)** (as far as I know).
- Want a Swift implementation? Check out **Permiso** by [Sash Zats](https://x.com/zats/status/2044972844216381802).

## License

Released under the [MIT License](LICENSE.md).