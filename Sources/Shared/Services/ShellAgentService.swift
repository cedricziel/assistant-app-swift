import Foundation
#if os(macOS)
import ServiceManagement
#endif

/// Manages the lifecycle of the shell agent and provides an XPC
/// connection for executing commands from the sandboxed main app.
///
/// macOS-only: on iOS this type is available but all operations are no-ops.
@MainActor
final class ShellAgentService: ObservableObject {
    enum AgentError: LocalizedError {
        case agentNotAvailable
        case connectionFailed(String)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .agentNotAvailable:
                "Shell agent is not available on this platform."
            case let .connectionFailed(detail):
                "Failed to connect to shell agent: \(detail)"
            case let .executionFailed(detail):
                "Command execution failed: \(detail)"
            }
        }
    }

    #if os(macOS)
    @Published private(set) var isRegistered = false

    private let agentPlistName = "com.cedricziel.assistant.app.shell-agent.plist"
    private var connection: NSXPCConnection?

    /// Register the shell agent with launchd via SMAppService.
    func register() throws {
        let service = SMAppService.agent(plistName: agentPlistName)
        try service.register()
        isRegistered = service.status == .enabled
    }

    /// Unregister the shell agent.
    func unregister() throws {
        let service = SMAppService.agent(plistName: agentPlistName)
        try service.unregister()
        isRegistered = false
        tearDownConnection()
    }

    /// Refresh the published registration status.
    func refreshStatus() {
        let service = SMAppService.agent(plistName: agentPlistName)
        isRegistered = service.status == .enabled
    }

    /// Execute a shell command via the agent and return the result.
    func execute(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
    ) async throws -> ShellExecutionResult {
        let proxy = try proxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.execute(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory,
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Private

    private func proxy() throws -> ShellExecutorProtocol {
        if let existing = connection {
            if let proxy = existing.remoteObjectProxy as? ShellExecutorProtocol {
                return proxy
            }
            tearDownConnection()
        }

        let conn = NSXPCConnection(machServiceName: shellAgentMachServiceName)
        let interface = NSXPCInterface(with: ShellExecutorProtocol.self)

        let allowedClasses = NSSet(object: ShellExecutionResult
            .self) as! Set<AnyHashable> // swiftlint:disable:this force_cast
        interface.setClasses(
            allowedClasses,
            for: #selector(
                ShellExecutorProtocol.execute(
                    executablePath:arguments:environment:workingDirectory:reply:
                )
            ),
            argumentIndex: 0,
            ofReply: true,
        )

        conn.remoteObjectInterface = interface

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }

        conn.resume()
        connection = conn

        guard let proxy = conn.remoteObjectProxy as? ShellExecutorProtocol else {
            throw AgentError.connectionFailed("Could not obtain remote object proxy.")
        }
        return proxy
    }

    private func tearDownConnection() {
        connection?.invalidate()
        connection = nil
    }

    #else
    /// iOS stub — agent is not supported.
    @Published private(set) var isRegistered = false

    func register() throws {
        throw AgentError.agentNotAvailable
    }

    func unregister() throws {
        throw AgentError.agentNotAvailable
    }

    func refreshStatus() {
        isRegistered = false
    }

    func execute(
        executablePath _: String,
        arguments _: [String] = [],
        environment _: [String: String] = [:],
        workingDirectory _: String? = nil,
    ) async throws -> ShellExecutionResult {
        throw AgentError.agentNotAvailable
    }
    #endif
}
