import Foundation
import IOKit.ps

/// Read-only helpers for the current power situation.
enum PowerMonitor {
    static var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else {
            return false
        }
        return type == kIOPSBatteryPowerValue
    }

    static var isLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Whether the boost should be paused right now. Battery Guard is opt-in:
    /// when enabled it pauses on battery power or in Low Power Mode.
    static func shouldPause(batteryGuard: Bool) -> Bool {
        batteryGuard && (isOnBattery || isLowPowerMode)
    }

    /// Short explanation for the menu/HUD when paused.
    static var pauseReason: String {
        if isLowPowerMode { return "Low Power Mode" }
        return "on battery"
    }
}
