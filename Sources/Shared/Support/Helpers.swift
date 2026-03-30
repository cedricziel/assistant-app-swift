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
        let sign = seconds >= 0 ? "+" : "-"
        let absoluteSeconds = abs(seconds)
        let hours = absoluteSeconds / 3600
        let minutes = (absoluteSeconds / 60) % 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }
}
