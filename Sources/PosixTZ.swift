import Foundation

/// Convertit un fuseau IANA (ex. "Europe/Paris") en chaîne TZ POSIX
/// (ex. "CET-1CEST,M3.5.0,M10.5.0/3"), le format attendu par l'horloge.
enum PosixTZ {
    static func string(for tz: TimeZone, referenceDate: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let year = cal.component(.year, from: referenceDate)

        // Cherche les transitions été/hiver de l'année.
        var transitions: [Date] = []
        var cursor = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        while let next = tz.nextDaylightSavingTimeTransition(after: cursor), next < end, transitions.count < 4 {
            transitions.append(next)
            cursor = next
        }

        let januaryOffset = tz.secondsFromGMT(for: cal.date(from: DateComponents(year: year, month: 1, day: 15))!)
        let julyOffset = tz.secondsFromGMT(for: cal.date(from: DateComponents(year: year, month: 7, day: 15))!)
        let stdOffset = min(januaryOffset, julyOffset)
        let dstOffset = max(januaryOffset, julyOffset)

        guard transitions.count >= 2, stdOffset != dstOffset else {
            let offset = tz.secondsFromGMT(for: referenceDate)
            return name(tz, offset: offset, isDST: false, date: referenceDate) + offsetString(-offset)
        }

        // Transition vers l'heure d'été = celle après laquelle le décalage devient dstOffset.
        let startDST = transitions.first { tz.secondsFromGMT(for: $0) == dstOffset }!
        let endDST = transitions.first { tz.secondsFromGMT(for: $0) == stdOffset }!

        let stdName = name(tz, offset: stdOffset, isDST: false, date: endDST)
        let dstName = name(tz, offset: dstOffset, isDST: true, date: startDST)

        // POSIX : l'heure de transition s'exprime dans l'heure locale en vigueur AVANT la transition.
        let startRule = rule(for: startDST, offsetBefore: stdOffset)
        let endRule = rule(for: endDST, offsetBefore: dstOffset)

        var result = stdName + offsetString(-stdOffset) + dstName
        if dstOffset - stdOffset != 3600 {
            result += offsetString(-dstOffset)
        }
        return result + "," + startRule + "," + endRule
    }

    private static func rule(for transition: Date, offsetBefore: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let local = transition.addingTimeInterval(TimeInterval(offsetBefore))
        let c = utc.dateComponents([.month, .day, .weekday, .hour, .minute, .second], from: local)
        let daysInMonth = utc.range(of: .day, in: .month, for: local)!.count
        let week = c.day! + 7 > daysInMonth ? 5 : (c.day! - 1) / 7 + 1
        let weekday = c.weekday! - 1 // POSIX : 0 = dimanche
        var r = "M\(c.month!).\(week).\(weekday)"
        let secs = c.hour! * 3600 + c.minute! * 60 + c.second!
        if secs != 7200 { r += "/" + timeString(secs) }
        return r
    }

    private static func name(_ tz: TimeZone, offset: Int, isDST: Bool, date: Date) -> String {
        let abbr = tz.abbreviation(for: date) ?? ""
        if abbr.count >= 3, abbr.allSatisfy({ $0.isASCII && $0.isLetter }) { return abbr }
        // Pas d'abréviation alphabétique : forme POSIX entre chevrons, ex. <+03>.
        let sign = offset < 0 ? "-" : "+"
        let a = abs(offset)
        var s = String(format: "%@%02d", sign, a / 3600)
        if a % 3600 != 0 { s += String(format: "%02d", (a % 3600) / 60) }
        return "<\(s)>"
    }

    /// Décalage POSIX : signe inversé par rapport à UTC (UTC+1 -> "-1").
    private static func offsetString(_ posixSeconds: Int) -> String {
        let sign = posixSeconds < 0 ? "-" : ""
        return sign + timeString(abs(posixSeconds))
    }

    private static func timeString(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        if s != 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if m != 0 { return String(format: "%d:%02d", h, m) }
        return "\(h)"
    }
}
