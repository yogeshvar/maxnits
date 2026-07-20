import Carbon.HIToolbox
import AppKit

/// Registers global (system-wide) keyboard shortcuts using the Carbon Event
/// Manager — the same low-level mechanism macOS itself uses for things like
/// Spotlight. Unlike an `NSEvent` global monitor, this needs no Accessibility
/// / Input Monitoring permission, since it only reacts to specific hotkey
/// combinations it registers up front rather than observing all key events.
@MainActor
final class HotKeyManager {
    private static let signature: OSType = 0x4D584E54 // 'MXNT'

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Registers a global shortcut. `modifiers` uses Carbon modifier
    /// constants (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`) OR'd
    /// together. Returns false if the combination is already claimed by
    /// another app or the system.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return false }
        handlers[id] = handler
        hotKeyRefs.append(hotKeyRef)
        return true
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
