#pragma once

#include <QtCore/QString>

#include "qdragtogrant/QDragToGrant.h"

namespace QDragToGrant::detail {

  // Hex-encoded CDHash of the running process, or empty on failure.
  QString currentCDHash();

  // Bundle identifier of the running process, or empty if none set.
  QString currentBundleId();

  // TCC service string for tccutil ("Accessibility", "ScreenCapture").
  QString tccServiceName(Panel panel);

  // Persisted CDHash from the last time `panel` was observed as granted.
  QString loadLastTrustedCDHash(Panel panel);
  void saveLastTrustedCDHash(Panel panel, const QString& hash);
  void clearLastTrustedCDHash(Panel panel);

  // Returns true if the saved CDHash exists and differs from the current one.
  bool isSignatureDrift(Panel panel);

  // Whether `panel` supports a reliable in-process live grant test.
  // True for Accessibility (real AX call), false for Screen Recording
  // (CGPreflightScreenCaptureAccess is cached for the process lifetime).
  bool canPollLive(Panel panel);

  // Performs an actual API call to verify the current process truly has the
  // grant. Reliable for pollable panels; returns false (don't trust) for
  // non-pollable panels. Use this — not isPanelGranted — for live UI updates.
  bool isActuallyGranted(Panel panel);

  // Spawn `/usr/bin/tccutil reset <service> <bundleId>` synchronously.
  // Returns true on exit code 0.
  bool runTccutilReset(const QString& service, const QString& bundleId);

} // namespace QDragToGrant::detail
