import AppKit
import Foundation

private enum ClientAuthorization {
    private static let trustedBundleIdentifier = "com.cedricziel.assistant.app.macos"

    static func isTrusted(processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0,
              let application = NSRunningApplication(processIdentifier: processIdentifier)
        else {
            return false
        }
        return application.bundleIdentifier == trustedBundleIdentifier
    }
}

/// XPC listener delegate that vends `ShellExecutorHandler` instances
/// to incoming connections from the sandboxed main app.
final class AgentDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection,
    ) -> Bool {
        guard ClientAuthorization.isTrusted(processIdentifier: newConnection.processIdentifier) else {
            newConnection.exportedInterface = nil
            newConnection.exportedObject = nil
            newConnection.invalidationHandler = nil
            newConnection.invalidate()
            return false
        }

        let interface = NSXPCInterface(with: ShellExecutorProtocol.self)

        // Allow ShellExecutionResult in reply blocks.
        let allowedClasses = NSSet(object: ShellExecutionResult
            .self) as! Set<AnyHashable> // swiftlint:disable:this force_cast
        interface.setClasses(
            allowedClasses,
            for: #selector(ShellExecutorProtocol.execute(executablePath:arguments:environment:workingDirectory:reply:)),
            argumentIndex: 0,
            ofReply: true,
        )

        newConnection.exportedInterface = interface
        newConnection.exportedObject = ShellExecutorHandler()

        newConnection.invalidationHandler = {
            // Connection closed — nothing to clean up per-connection.
        }

        newConnection.resume()
        return true
    }
}

// MARK: - Entry point

let delegate = AgentDelegate()
let listener = NSXPCListener(machServiceName: shellAgentMachServiceName)
listener.delegate = delegate
listener.resume()

// Keep the agent alive.
RunLoop.main.run()
