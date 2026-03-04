import Foundation

/// Handles incoming XPC requests by executing shell commands via `Process`.
final class ShellExecutorHandler: NSObject, ShellExecutorProtocol {
    func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        reply: @escaping (ShellExecutionResult) -> Void,
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if !environment.isEmpty {
            process.environment = environment
        }

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            let errorData = Data("Failed to launch process: \(error.localizedDescription)".utf8)
            reply(ShellExecutionResult(exitCode: -1, standardOutput: Data(), standardError: errorData))
            return
        }

        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        reply(ShellExecutionResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr,
        ))
    }
}
