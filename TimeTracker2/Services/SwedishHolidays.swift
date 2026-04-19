//
//  SwedishHolidays.swift
//  TimeTracker2
//

import Foundation

struct Holiday: Equatable {
    let name: String
}

enum SwedishHolidays {
    static func holiday(for date: Date, calendar: Calendar = .current) -> Holiday? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }

        if let name = fixedHolidayName(month: month, day: day) {
            return Holiday(name: name)
        }

        if let name = easterHolidayName(year: year, month: month, day: day, calendar: calendar) {
            return Holiday(name: name)
        }

        if isMidsommarafton(year: year, month: month, day: day, calendar: calendar) {
            return Holiday(name: "Midsommarafton")
        }

        return nil
    }

    private static func fixedHolidayName(month: Int, day: Int) -> String? {
        switch (month, day) {
        case (1, 1):   return "Nyårsdagen"
        case (1, 6):   return "Trettondedag jul"
        case (5, 1):   return "Första maj"
        case (6, 6):   return "Sveriges nationaldag"
        case (12, 24): return "Julafton"
        case (12, 25): return "Juldagen"
        case (12, 26): return "Annandag jul"
        case (12, 31): return "Nyårsafton"
        default:       return nil
        }
    }

    private static func easterHolidayName(year: Int, month: Int, day: Int, calendar: Calendar) -> String? {
        let easter = easterSunday(year: year, calendar: calendar)
        guard let easterDate = easter else { return nil }

        let target = calendar.date(from: DateComponents(year: year, month: month, day: day))
        guard let targetDate = target else { return nil }

        let diff = calendar.dateComponents([.day], from: easterDate, to: targetDate).day ?? 0
        switch diff {
        case -2: return "Långfredagen"
        case 1:  return "Annandag påsk"
        case 39: return "Kristi himmelsfärdsdag"
        default: return nil
        }
    }

    private static func isMidsommarafton(year: Int, month: Int, day: Int, calendar: Calendar) -> Bool {
        guard month == 6, (19...25).contains(day) else { return false }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        return calendar.component(.weekday, from: date) == 6 // Friday
    }

    // Anonymous Gregorian / Meeus algorithm.
    private static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let L = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * L) / 451
        let month = (h + L - 7 * m + 114) / 31
        let day = ((h + L - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
