import Darwin
import Foundation

private final class ThreadSafeDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Handles incoming XPC requests by executing shell commands via `Process`.
final class ShellExecutorHandler: NSObject, ShellExecutorProtocol {
    private struct IOCapture {
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let stdoutBuffer: ThreadSafeDataBuffer
        let stderrBuffer: ThreadSafeDataBuffer
        let ioGroup: DispatchGroup
    }

    private let executionTimeout: TimeInterval = 60
    private let terminationGracePeriod: TimeInterval = 2

    func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        reply: @escaping (ShellExecutionResult) -> Void,
    ) {
        let process = Process()
        configure(
            process,
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
        )
        let ioCapture = configureIOCapture(for: process)
        let terminated = makeTerminationSemaphore(for: process)

        do {
            try process.run()
        } catch {
            clearReadabilityHandlers(ioCapture)
            let errorData = Data("Failed to launch process: \(error.localizedDescription)".utf8)
            reply(ShellExecutionResult(exitCode: -1, standardOutput: Data(), standardError: errorData))
            return
        }

        let timedOut = waitForTermination(process, semaphore: terminated)

        clearReadabilityHandlers(ioCapture)
        _ = ioCapture.ioGroup.wait(timeout: .now() + terminationGracePeriod)

        let stdout = ioCapture.stdoutBuffer.data
        var stderr = ioCapture.stderrBuffer.data

        let exitCode: Int32
        if timedOut {
            exitCode = 124
            let timeoutMessage = Data("\nProcess timed out after \(Int(executionTimeout))s".utf8)
            stderr.append(timeoutMessage)
        } else {
            exitCode = process.terminationStatus
        }

        reply(ShellExecutionResult(
            exitCode: exitCode,
            standardOutput: stdout,
            standardError: stderr,
        ))
    }

    private func configure(
        _ process: Process,
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
    ) {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if !environment.isEmpty {
            process.environment = environment
        }

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
    }

    private func configureIOCapture(for process: Process) -> IOCapture {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdoutBuffer = ThreadSafeDataBuffer()
        let stderrBuffer = ThreadSafeDataBuffer()
        let ioGroup = DispatchGroup()
        ioGroup.enter()
        ioGroup.enter()

        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                ioGroup.leave()
                return
            }
            stdoutBuffer.append(chunk)
        }

        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                ioGroup.leave()
                return
            }
            stderrBuffer.append(chunk)
        }

        return IOCapture(
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle,
            stdoutBuffer: stdoutBuffer,
            stderrBuffer: stderrBuffer,
            ioGroup: ioGroup,
        )
    }

    private func makeTerminationSemaphore(for process: Process) -> DispatchSemaphore {
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminated.signal()
        }
        return terminated
    }

    private func waitForTermination(_ process: Process, semaphore: DispatchSemaphore) -> Bool {
        let timedOut = semaphore.wait(timeout: .now() + executionTimeout) == .timedOut
        if timedOut {
            process.terminate()
            if semaphore.wait(timeout: .now() + terminationGracePeriod) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + terminationGracePeriod)
            }
        }
        return timedOut
    }

    private func clearReadabilityHandlers(_ ioCapture: IOCapture) {
        ioCapture.stdoutHandle.readabilityHandler = nil
        ioCapture.stderrHandle.readabilityHandler = nil
    }
}
