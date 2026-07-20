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

    /// Whether the boost should be paused right now. Low Power Mode always
    /// pauses (the user explicitly asked the machine to save energy);
    /// plain battery power pauses only when the user opted in.
    static func shouldPause(pauseOnBattery: Bool) -> Bool {
        if isLowPowerMode { return true }
        return pauseOnBattery && isOnBattery
    }

    /// Short explanation for the menu/HUD when paused.
    static var pauseReason: String {
        if isLowPowerMode { return "Low Power Mode" }
        return "on battery"
    }
}
