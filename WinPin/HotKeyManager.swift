import AppKit
import Carbon.HIToolbox

private let hotKeyEventSignature = OSType(UInt32(UInt8(ascii: "W")) << 24 | UInt32(UInt8(ascii: "P")) << 16 | UInt32(UInt8(ascii: "I")) << 8 | UInt32(UInt8(ascii: "N")))
private let hotKeyEventID = UInt32(1)

final class HotKeyManager {
    static let defaultShortcutDisplayName = "Control + Option + Command + T"

    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastTriggerTime: TimeInterval = 0

    var onHotKey: (() -> Void)?
    private(set) var registrationError: String?

    deinit {
        unregister()
    }

    func registerDefaultHotKey() {
        unregister()
        installEventMonitorFallback()

        let status: OSStatus
        if installHandlerIfNeeded() {
            let hotKeyID = EventHotKeyID(signature: hotKeyEventSignature, id: hotKeyEventID)
            let modifiers = UInt32(controlKey | optionKey | cmdKey)
            let keyCode = UInt32(kVK_ANSI_T)
            status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &eventHotKeyRef)
        } else {
            status = OSStatus(eventNotHandledErr)
        }

        if status == noErr {
            registrationError = nil
        } else {
            registrationError = "WinPin shortcut could not be registered. Another app or macOS may already be using it."
            eventHotKeyRef = nil
        }
    }

    func unregister() {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func installHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else {
            return true
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard hotKeyID.signature == hotKeyEventSignature, hotKeyID.id == hotKeyEventID else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.triggerHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        if status != noErr {
            registrationError = "WinPin could not install the global shortcut handler."
            return false
        }
        return true
    }

    private func installEventMonitorFallback() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleFallbackEvent(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleFallbackEvent(event)
            return event
        }
    }

    private func handleFallbackEvent(_ event: NSEvent) {
        guard matchesDefaultShortcut(event) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.triggerHotKey()
        }
    }

    private func triggerHotKey() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTime > 0.25 else {
            return
        }
        lastTriggerTime = now
        onHotKey?()
    }

    private func matchesDefaultShortcut(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_ANSI_T) else {
            return false
        }

        let required: NSEvent.ModifierFlags = [.control, .option, .command]
        return event.modifierFlags.intersection(.deviceIndependentFlagsMask) == required
    }
}
