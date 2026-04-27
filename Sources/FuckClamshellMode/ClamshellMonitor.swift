import Foundation
import IOKit
import IOKit.pwr_mgt
import CoreGraphics

// Bit 0 of the kIOPMMessageClamshellStateChange message argument indicates
// whether the lid is closed (1) or open (0).
private let kClamshellStateBit: UInt = 0x01

// C-compatible IOKit interest callback.
// Recovers the ClamshellMonitor instance from `refcon` and forwards the event.
private func pmDomainChange(
    refcon: UnsafeMutableRawPointer?,
    service: io_service_t,
    messageType: UInt32,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<ClamshellMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleMessage(type: messageType, argument: messageArgument)
}

/// Monitors IOKit power-management events for lid open/close state changes.
/// When the lid is closed with an external display active (clamshell mode),
/// the screen is locked immediately.
final class ClamshellMonitor {

    private var notificationPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    // Retained reference to self passed as the IOKit callback `refcon`.
    private var selfRef: Unmanaged<ClamshellMonitor>?

    // MARK: - Lifecycle

    /// Register for lid-state change notifications. Call once at startup.
    func start() {
        // Obtain the power-management root domain service.
        let powerManagementRD = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard powerManagementRD != MACH_PORT_NULL else {
            NSLog("FuckClamshellMode: failed to obtain IOPMrootDomain service")
            return
        }
        defer { IOObjectRelease(powerManagementRD) }

        // Create the notification port that will deliver callbacks.
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            NSLog("FuckClamshellMode: failed to create IONotificationPort")
            return
        }
        notificationPort = port

        // Dispatch callbacks on a dedicated high-priority serial queue.
        let queue = DispatchQueue(
            label: "com.roblabla.FuckClamshellMode.lidMonitor",
            qos: .userInteractive
        )
        IONotificationPortSetDispatchQueue(port, queue)

        // Retain self so the raw pointer we hand to IOKit stays valid.
        selfRef = Unmanaged.passRetained(self)

        let status = IOServiceAddInterestNotification(
            port,
            powerManagementRD,
            kIOGeneralInterest,
            pmDomainChange,
            selfRef!.toOpaque(),
            &notification
        )

        if status != KERN_SUCCESS {
            NSLog("FuckClamshellMode: IOServiceAddInterestNotification failed: 0x%x", status)
            selfRef?.release()
            selfRef = nil
        } else {
            NSLog("FuckClamshellMode: monitoring lid state")
        }
    }

    /// Tear down IOKit resources and stop receiving notifications.
    func stop() {
        if notification != 0 {
            IOObjectRelease(notification)
            notification = 0
        }
        if let port = notificationPort {
            IONotificationPortSetDispatchQueue(port, nil)
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        selfRef?.release()
        selfRef = nil
    }

    deinit { stop() }

    // MARK: - IOKit callback

    /// Called from `pmDomainChange`; runs on the monitor's serial dispatch queue.
    func handleMessage(type messageType: UInt32, argument messageArgument: UnsafeMutableRawPointer?) {
        // Ignore everything that is not a clamshell-state change.
        guard messageType == UInt32(kIOPMMessageClamshellStateChange) else { return }

        let arg = UInt(bitPattern: messageArgument)
        let lidClosed = (arg & kClamshellStateBit) != 0

        NSLog("FuckClamshellMode: lid state changed: %@", lidClosed ? "closed" : "open")

        // Lock the screen only when the lid is closed **and** an external
        // display is active — i.e. the Mac is operating in clamshell mode.
        if lidClosed && isExternalDisplayActive() {
            NSLog("FuckClamshellMode: clamshell mode detected — locking screen")
            lockScreen()
        }
    }

    // MARK: - Display helpers

    /// Returns `true` when at least one non-built-in display is active.
    private func isExternalDisplayActive() -> Bool {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        guard displayCount > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        // CGDisplayIsBuiltin returns a boolean_t (C int); compare explicitly to
        // avoid relying on implicit boolean conversion semantics.
        return displays.prefix(Int(displayCount)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    // MARK: - Screen lock

    /// Locks the current user session using `SACLockScreenImmediate` from the
    /// private `login` framework.  This is the same private API used by macOS
    /// system components and works even when `CGSession -suspend` is absent.
    private func lockScreen() {
        let loginFrameworkPath = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(loginFrameworkPath, RTLD_LAZY) else {
            NSLog("FuckClamshellMode: failed to open login.framework: %@",
                  String(cString: dlerror()))
            return
        }
        defer { dlclose(handle) }

        guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
            NSLog("FuckClamshellMode: SACLockScreenImmediate not found in login.framework: %@",
                  String(cString: dlerror()))
            return
        }

        typealias SACLockScreenImmediateFn = @convention(c) () -> Void
        let lockFn = unsafeBitCast(sym, to: SACLockScreenImmediateFn.self)
        lockFn()
    }
}
