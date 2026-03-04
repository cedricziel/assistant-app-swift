import Foundation

/// Utilities for compacting shell command output to reduce token consumption.
enum ToolOutputProcessing {
    /// Maximum characters to keep in a single output stream (stdout or stderr).
    static let maxOutputChars = 30000
    /// When truncating, how many characters to keep from the head.
    static let headChars = 2000
    /// When truncating, how many characters to keep from the tail.
    static let tailChars = 20000
    /// Maximum number of lines to keep per stream.
    static let maxLines = 200

    // MARK: - Public

    /// Process raw command output into a compact, token-efficient representation.
    static func compact(stdout: String, stderr: String, exitCode: Int32) -> String {
        let cleanStdout = sanitize(stdout)
        let cleanStderr = sanitize(stderr)

        let trimmedStdout = truncateMiddle(cleanStdout)
        let trimmedStderr = truncateMiddle(cleanStderr)

        var output = ""
        if !trimmedStdout.isEmpty {
            output += trimmedStdout
        }
        if !trimmedStderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += "stderr:\n\(trimmedStderr)"
        }
        if output.isEmpty { output = "(no output)" }
        output += "\nexit_code: \(exitCode)"

        return output
    }

    // MARK: - Sanitization

    /// Strip ANSI escape codes and non-printable characters.
    static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // CSI sequences: ESC [ ... final-byte
        result = replacePattern(in: result, pattern: "\u{1b}\\[[0-9;]*[A-Za-z]")
        // OSC sequences: ESC ] ... ST (BEL or ESC \)
        result = replacePattern(in: result, pattern: "\u{1b}\\][^\u{07}\u{1b}]*(?:\u{07}|\u{1b}\\\\)")
        // Other ESC sequences
        result = replacePattern(in: result, pattern: "\u{1b}[^\\[\\]].?")
        // Carriage returns (overwrite-style progress bars) not followed by newline
        result = replacePattern(in: result, pattern: "\r(?!\n)")

        return result
    }

    // MARK: - Truncation

    /// Truncate long output keeping head and tail with a marker in the middle.
    static func truncateMiddle(_ text: String) -> String {
        // First, limit by line count.
        let lineLimited = limitLines(text)

        guard lineLimited.count > maxOutputChars else { return lineLimited }

        let head = String(lineLimited.prefix(headChars))
        let tail = String(lineLimited.suffix(tailChars))
        let omitted = lineLimited.count - headChars - tailChars

        return "\(head)\n[...\(omitted) characters truncated...]\n\(tail)"
    }

    /// Keep only the last `maxLines` lines.
    static func limitLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return text }

        let kept = lines.suffix(maxLines)
        let omitted = lines.count - maxLines
        return "[\(omitted) lines omitted]\n" + kept.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func replacePattern(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
