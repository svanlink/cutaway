import Carbon.HIToolbox
import AppKit

/// Global ⌥⌘P pause/resume via Carbon RegisterEventHotKey — works without
/// Input Monitoring or Accessibility permissions.
final class GlobalHotKey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @Sendable () -> Void
    /// False when the system refused the registration (shortcut conflict) —
    /// callers MUST surface this; a dead pause-hotkey silently bills breaks.
    private(set) var isRegistered = false

    init(keyCode: UInt32 = UInt32(kVK_ANSI_P),
         modifiers: UInt32 = UInt32(cmdKey | optionKey),
         action: @escaping @Sendable () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var installedHandler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &eventType, selfPtr, &installedHandler)
        handlerRef = installedHandler

        let hotKeyID = EventHotKeyID(signature: OSType(0x54494D58) /* TIMX */, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr && hotKeyRef != nil)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
