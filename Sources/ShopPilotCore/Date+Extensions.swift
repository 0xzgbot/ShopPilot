import Foundation

// MARK: - Formatting

extension Date {

    /// ISO 8601 string (e.g. "2026-07-31T14:30:00Z")
    func formattedISO() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Short date string (e.g. "Jul 31, 2026")
    func formattedShort() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Relative time string (e.g. "2 hours ago", "in 5 minutes")
    func formattedRelative() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    // MARK: - Day boundaries

    /// Date at midnight (00:00:00) of this day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Date at 23:59:59 of this day
    var endOfDay: Date {
        let end = Calendar.current.date(byAdding: .second, value: -1, to: Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!)
        return end ?? self
    }

    // MARK: - Offsets

    /// Date N days ago
    static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    /// Date N hours from now
    static func hoursFromNow(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: Date()) ?? Date()
    }

    // MARK: - Day checks

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }
}
