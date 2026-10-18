import CoreGraphics
import CoreMediaIO
import Foundation
import IOKit.pwr_mgt

/// What the Mac can tell us about whether you're there and what you're doing.
/// None of these need any permission prompts.
enum Checks {
    static func idleSeconds() -> TimeInterval {
        // ~0 is kCGAnyInputEventType: keyboard, mouse, trackpad.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static func screenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    static func cameraInUse() -> Bool {
        func address(_ selector: Int) -> CMIOObjectPropertyAddress {
            CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(selector),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        }

        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var devicesAddress = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr else { return false }

        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &devicesAddress, 0, nil, size, &used, &devices) == noErr else { return false }

        var runningAddress = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return devices.contains { device in
            var running: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
            return status == noErr && running != 0
        }
    }

    /// Processes that keep the display awake without meaning you're watching it.
    static let ignoredDisplayHolders: Set<String> = ["UniversalControl", "caffeinate", "powerd"]

    /// True while an app is keeping the display awake, which video players and
    /// call apps do. Idle time then doesn't mean you've walked away.
    static func displayHeldAwake() -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return false }

        return assertions.contains { pid, list in
            list.contains { $0["AssertType"] as? String == "PreventUserIdleDisplaySleep" }
                && !ignoredDisplayHolders.contains(processName(pid.int32Value))
        }
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }
}
