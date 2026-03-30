import Foundation
import OSLog
#if os(macOS)
import ServiceManagement
#endif

private let logger = Logger(
    subsystem: "com.cedricziel.assistant.app",
    category: "ShellAgentService",
)

/// Manages the lifecycle of the shell agent and provides an XPC
/// connection for executing commands from the sandboxed main app.
///
/// macOS-only: on iOS this type is available but all operations are no-ops.
@MainActor
final class ShellAgentService: ObservableObject {
    enum AgentError: LocalizedError {
        case agentNotAvailable
        case agentNotFound
        case agentRequiresApproval
        case connectionFailed(String)
        case executionFailed(String)
        case registrationFailed(String, underlyingStatus: String)

        var errorDescription: String? {
            switch self {
            case .agentNotAvailable:
                "Shell agent is not available on this platform."
            case .agentNotFound:
                "Shell agent binary or plist was not found in the app bundle. "
                    + "Try rebuilding the app with a clean build (Product > Clean Build Folder)."
            case .agentRequiresApproval:
                "Shell agent requires approval. Open System Settings > General > Login Items "
                    + "and enable the agent for this app."
            case let .connectionFailed(detail):
                "Failed to connect to shell agent: \(detail)"
            case let .executionFailed(detail):
                "Command execution failed: \(detail)"
            case let .registrationFailed(detail, underlyingStatus):
                "Registration failed (\(underlyingStatus)): \(detail)"
            }
        }
    }

    /// Human-readable status of the agent service (macOS only).
    enum AgentStatus: String {
        case enabled = "Enabled"
        case requiresApproval = "Requires Approval"
        case notRegistered = "Not Registered"
        case notFound = "Not Found in Bundle"
        case unknown = "Unknown"
    }

    #if os(macOS)
    @Published private(set) var isRegistered = false
    @Published private(set) var agentStatus: AgentStatus = .notRegistered

    private let agentPlistName = "com.cedricziel.assistant.app.macos.shell-agent.plist"
    private var connection: NSXPCConnection?

    /// Register the shell agent with launchd via SMAppService.
    func register() throws {
        let service = SMAppService.agent(plistName: agentPlistName)
        let preStatus = service.status
        let preStatusDesc = statusLabel(preStatus)

        logger.info("Attempting agent registration. Pre-status: \(preStatusDesc)")

        // If already awaiting approval, guide the user instead of re-registering.
        if preStatus == .requiresApproval {
            logger.info("Agent requires approval — prompting user.")
            updateStatus(from: service)
            throw AgentError.agentRequiresApproval
        }

        // Always attempt registration — .notFound may be the default status
        // before the first register() call. Let the system decide.
        do {
            try service.register()
        } catch {
            let postStatus = service.status
            let statusDesc = statusLabel(postStatus)
            let errorDesc = error.localizedDescription
            logger.error("Agent registration failed. Pre: \(preStatusDesc), Post: \(statusDesc). Error: \(errorDesc)")
            updateStatus(from: service)

            // Surface a more specific error when possible.
            if postStatus == .requiresApproval {
                throw AgentError.agentRequiresApproval
            }
            throw AgentError.registrationFailed(
                errorDesc,
                underlyingStatus: statusDesc,
            )
        }

        updateStatus(from: service)
        let postStatusDesc = statusLabel(service.status)
        logger.info("Agent registered. Post-status: \(postStatusDesc)")
    }

    /// Unregister the shell agent.
    func unregister() throws {
        let service = SMAppService.agent(plistName: agentPlistName)
        try service.unregister()
        isRegistered = false
        agentStatus = .notRegistered
        tearDownConnection()
    }

    /// Refresh the published registration status.
    func refreshStatus() {
        logBundleDiagnostics()
        let service = SMAppService.agent(plistName: agentPlistName)
        updateStatus(from: service)
        let currentStatus = agentStatus.rawValue
        logger.debug("Refreshed agent status: \(currentStatus)")
    }

    /// Log diagnostic info about the app bundle to help debug .notFound.
    private func logBundleDiagnostics() {
        let bundle = Bundle.main
        let bundlePath = bundle.bundlePath
        logger.info("App bundle path: \(bundlePath)")

        let plistPath = bundlePath + "/Contents/Library/LaunchAgents/" + agentPlistName
        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        logger.info("Agent plist exists at expected path: \(plistExists) (\(plistPath))")

        let binaryPath = bundlePath + "/Contents/MacOS/com.cedricziel.assistant.app.macos.shell-agent"
        let binaryExists = FileManager.default.fileExists(atPath: binaryPath)
        logger.info("Agent binary exists at expected path: \(binaryExists) (\(binaryPath))")
    }

    // MARK: - Status helpers

    private func updateStatus(from service: SMAppService) {
        let status = service.status
        switch status {
        case .enabled:
            agentStatus = .enabled
            isRegistered = true
        case .requiresApproval:
            agentStatus = .requiresApproval
            isRegistered = false
        case .notRegistered:
            agentStatus = .notRegistered
            isRegistered = false
        case .notFound:
            agentStatus = .notFound
            isRegistered = false
        @unknown default:
            agentStatus = .unknown
            isRegistered = false
        }
    }

    private func statusLabel(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notRegistered: "notRegistered"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }

    /// Execute a shell command via the agent and return the result.
    func execute(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
    ) async throws -> ShellExecutionResult {
        let conn = try ensureConnection()

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var isResolved = false

            let resolve: (Result<ShellExecutionResult, Error>) -> Void = { result in
                lock.lock()
                defer { lock.unlock() }
                guard !isResolved else { return }
                isResolved = true
                continuation.resume(with: result)
            }

            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                resolve(.failure(error))
            }) as? ShellExecutorProtocol else {
                resolve(.failure(AgentError.connectionFailed("Could not obtain remote object proxy.")))
                return
            }

            proxy.execute(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory,
            ) { result in
                resolve(.success(result))
            }
        }
    }

    // MARK: - Private

    private func ensureConnection() throws -> NSXPCConnection {
        if let existing = connection {
            return existing
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

        return conn
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
