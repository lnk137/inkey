import AppKit
import Carbon.HIToolbox
import ServiceManagement
import Testing
@testable import Inkey

@Suite("Silent login launch")
struct LoginLaunchTests {
    func openEvent(login: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                          eventID: AEEventID(kAEOpenApplication),
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        if login {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                           forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    @Test func loginEventIsSilentButManualLaunchIsVisible() {
        #expect(LoginLaunch.isSilentLaunch(event: openEvent(login: true), arguments: []))
        #expect(!LoginLaunch.isSilentLaunch(event: openEvent(login: false), arguments: []))
        #expect(!LoginLaunch.isSilentLaunch(event: nil, arguments: []))
        let reopen = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: AEEventID(kAEReopenApplication),
                                           targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        reopen.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                        forKeyword: AEKeyword(keyAEPropData))
        #expect(!LoginLaunch.isSilentLaunch(event: reopen, arguments: []))
    }

    @Test func explicitBackgroundLaunchAndTestModes() {
        #expect(LoginLaunch.isSilentLaunch(event: nil, arguments: ["Inkey", "--background"]))
        for mode in ["--smoke-test", "--ui-test"] {
            #expect(!LoginLaunch.isSilentLaunch(event: openEvent(login: true), arguments: [mode, "--background"]))
        }
    }

    @Test func registrationTracksSystemStateAndCanCancelPendingApproval() throws {
        let service = FakeLoginItemService()
        let login = LoginLaunch(service: service)
        #expect(!login.isEnabled && !login.needsApproval)
        try login.setEnabled(true)
        #expect(login.isEnabled && service.registrations == 1)
        try login.setEnabled(true)
        #expect(service.registrations == 1)
        // External changes must be reflected without storing a second preference.
        service.status = .requiresApproval
        #expect(!login.isEnabled && login.needsApproval)
        try login.setEnabled(true)
        #expect(service.registrations == 1)
        try login.setEnabled(false)
        #expect(!login.isEnabled && !login.needsApproval)
        #expect(service.unregistrations == 1)
        try login.setEnabled(false)
        #expect(service.unregistrations == 1)
    }

    @Test func serviceErrorsPropagateWithoutPretendingTheSettingChanged() {
        let service = FakeLoginItemService()
        let login = LoginLaunch(service: service)
        service.fails = true
        #expect(throws: FakeLoginItemService.Failure.self) { try login.setEnabled(true) }
        #expect(!login.isEnabled)
        service.status = .enabled
        #expect(throws: FakeLoginItemService.Failure.self) { try login.setEnabled(false) }
        #expect(login.isEnabled)
    }
}

private final class FakeLoginItemService: LoginItemService {
    enum Failure: Error { case unavailable }
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var unregistrations = 0
    var fails = false
    func register() throws {
        if fails { throw Failure.unavailable }
        registrations += 1; status = .enabled
    }
    func unregister() throws {
        if fails { throw Failure.unavailable }
        unregistrations += 1; status = .notRegistered
    }
}
