import Foundation

extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension TimeZone {
    /// Formatted UTC offset, e.g. "+02:00" or "-05:00".
    var offsetDescription: String {
        let seconds = secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds / 60) % 60
        return String(format: "%+03d:%02d", hours, minutes)
    }
}
