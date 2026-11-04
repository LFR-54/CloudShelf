import Foundation

/// Number formats of the mockup, in French.
enum Format {
    /// Below 1 Ko/s a drive counts as idle.
    static let idleThreshold = 1_000.0

    /// "182 Mo/s", "64,0 Mo/s", "320 Ko/s", or "—" when nothing moves.
    static func speed(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        if bytesPerSecond < idleThreshold { return "—" }
        if megabytes >= 100 { return "\(Int(megabytes.rounded())) Mo/s" }
        if megabytes >= 1 { return "\(decimal(megabytes, 1)) Mo/s" }
        return "\(Int((bytesPerSecond / 1_000).rounded())) Ko/s"
    }

    /// Drive capacities: "1,31 To", "620 Go", "85 Mo".
    static func capacity(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e12 { return "\(decimal(value / 1e12, 2)) To" }
        if value >= 1e9 { return "\(Int((value / 1e9).rounded())) Go" }
        return "\(Int((value / 1e6).rounded())) Mo"
    }

    /// Cache sizes: "48 Go", "1,4 Go".
    static func gigabytes(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1e9
        return value >= 10 || value == 0 ? "\(Int(value.rounded())) Go" : "\(decimal(value, 1)) Go"
    }

    /// Chart scale labels: "120 Mo/s", "7,5 Mo/s".
    static func tick(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        return megabytes == megabytes.rounded() ? "\(Int(megabytes)) Mo/s" : "\(decimal(megabytes, 1)) Mo/s"
    }

    static func decimal(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count > 1 ? "s" : "")"
    }

    /// "à l'instant", "il y a 6 min", "il y a 2 h", "jamais".
    static func ago(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "jamais" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "à l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        if minutes < 48 * 60 { return "il y a \(minutes / 60) h" }
        return "le " + date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }
}
