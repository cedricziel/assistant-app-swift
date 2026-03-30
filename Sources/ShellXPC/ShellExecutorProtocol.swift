import Foundation

/// Mach service name used by the shell agent for XPC registration.
let shellAgentMachServiceName = "com.cedricziel.assistant.app.macos.shell-agent"

/// Result of a shell command execution, delivered over XPC.
@objc
final class ShellExecutionResult: NSObject, NSSecureCoding, @unchecked Sendable {
    static let supportsSecureCoding = true

    /// Process exit code (0 = success).
    let exitCode: Int32
    /// Standard output captured from the process.
    let standardOutput: Data
    /// Standard error captured from the process.
    let standardError: Data

    init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    required init?(coder: NSCoder) {
        guard let standardOutput = coder.decodeObject(of: NSData.self, forKey: "standardOutput") as Data?,
              let standardError = coder.decodeObject(of: NSData.self, forKey: "standardError") as Data?
        else {
            return nil
        }
        exitCode = coder.decodeInt32(forKey: "exitCode")
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    func encode(with coder: NSCoder) {
        coder.encode(exitCode, forKey: "exitCode")
        coder.encode(standardOutput as NSData, forKey: "standardOutput")
        coder.encode(standardError as NSData, forKey: "standardError")
    }
}

/// XPC protocol exposed by the shell agent.
///
/// The sandboxed main app connects to the agent's Mach service and calls
/// these methods. The agent runs outside the sandbox and can execute
/// arbitrary user-level commands.
@objc
protocol ShellExecutorProtocol {
    /// Execute a command and return the result when the process exits.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable (e.g. `/usr/bin/env`).
    ///   - arguments: Arguments passed to the executable.
    ///   - environment: Environment variables; pass an empty dictionary to inherit.
    ///   - workingDirectory: Working directory for the process, or `nil` for default.
    ///   - reply: Callback with the execution result.
    func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        reply: @escaping (ShellExecutionResult) -> Void,
    )
}
