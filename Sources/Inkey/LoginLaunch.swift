import AppKit
import Carbon.HIToolbox
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// The system owns the preference, including changes made in System Settings.
final class LoginLaunch {
    private let service: any LoginItemService

    init(service: any LoginItemService = SMAppService.mainApp) { self.service = service }

    var isEnabled: Bool { service.status == .enabled }
    var needsApproval: Bool { service.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if !isEnabled && !needsApproval { try service.register() }
        } else if isEnabled || needsApproval {
            try service.unregister()
        }
    }

    static func isSilentLaunch(event: NSAppleEventDescriptor?, arguments: [String]) -> Bool {
        if arguments.contains("--smoke-test") || arguments.contains("--ui-test") { return false }
        if arguments.contains("--background") { return true }
        guard let event, event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
            || event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}
