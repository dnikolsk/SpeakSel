import AppKit
import Carbon
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var speakHotKeyRef: EventHotKeyRef?
    private var stopHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x53504B53 // 'SPKS'
    var onSpeak: (() -> Void)?
    var onStop: (() -> Void)?

    private enum HotKeyID: UInt32 {
        case speak = 1
        case stop = 2
    }

    private init() {}

    func register(speak: HotkeyCombo, stop: HotkeyCombo) {
        unregister()
        guard speak.hasModifier else { return }

        installHandler()
        speakHotKeyRef = register(speak, id: .speak)
        if stop != speak, stop.hasModifier {
            stopHotKeyRef = register(stop, id: .stop)
        }
    }

    func unregister() {
        if let speakHotKeyRef {
            UnregisterEventHotKey(speakHotKeyRef)
            self.speakHotKeyRef = nil
        }
        if let stopHotKeyRef {
            UnregisterEventHotKey(stopHotKeyRef)
            self.stopHotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate func fire(id: UInt32) {
        if id == HotKeyID.stop.rawValue {
            onStop?()
        } else {
            onSpeak?()
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )
        if installed != noErr {
            NSLog("SpeakSel: InstallEventHandler failed (\(installed))")
        }
    }

    private func register(_ combo: HotkeyCombo, id: HotKeyID) -> EventHotKeyRef? {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("SpeakSel: RegisterEventHotKey \(id) failed (\(status))")
            return nil
        }
        return hotKeyRef
    }
}

private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let id = status == noErr ? hotKeyID.id : 1
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.fire(id: id)
    }
    return noErr
}
