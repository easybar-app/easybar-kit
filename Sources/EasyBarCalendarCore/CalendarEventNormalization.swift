import EasyBarShared
import Foundation

/// Builds stable event identifiers without relying on Swift's randomized Hasher.
enum CalendarEventIdentity {
  /// Creates ID.
  static func makeID(
    prefix: String,
    eventIdentifier: String?,
    calendarID: String?,
    sourceID: String?,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    location: String?
  ) -> String {
    let occurrence = String(startDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
    if let eventIdentifier = normalized(eventIdentifier) {
      return "\(prefix)\(eventIdentifier)-\(occurrence)"
    }

    let payload = [
      normalized(calendarID) ?? "",
      normalized(sourceID) ?? "",
      title.trimmingCharacters(in: .whitespacesAndNewlines),
      String(startDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
      String(endDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
      isAllDay ? "1" : "0",
      normalized(location) ?? "",
    ].joined(separator: "\u{1F}")

    return "\(prefix)fallback-\(fnv1a64(payload))"
  }

  /// Returns the normalized.
  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Returns the fnv1a64.
  private static func fnv1a64(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}

/// Pure normalization helpers shared by EventKit mapping and regression tests.
enum CalendarEventNormalization {
  /// Converts relative and absolute alarms into unique, sorted lead times.
  static func visibleAlertOffsetsSeconds(
    eventStartDate: Date,
    relativeOffsets: [TimeInterval],
    absoluteDates: [Date]
  ) -> [TimeInterval] {
    var values: [TimeInterval] = []
    values.reserveCapacity(relativeOffsets.count + absoluteDates.count)

    for relativeOffset in relativeOffsets {
      guard relativeOffset.isFinite, relativeOffset <= 0 else { continue }
      let leadTime = -relativeOffset
      guard leadTime <= CalendarAgentRequestLimits.maximumAlertOffset else { continue }
      values.append(leadTime)
    }

    for absoluteDate in absoluteDates {
      let leadTime = eventStartDate.timeIntervalSince(absoluteDate)
      guard
        leadTime.isFinite,
        leadTime >= 0,
        leadTime <= CalendarAgentRequestLimits.maximumAlertOffset
      else {
        continue
      }
      values.append(leadTime)
    }

    var seen = Set<UInt64>()
    return
      values
      .filter { seen.insert($0.bitPattern).inserted }
      .sorted()
  }

  /// Removes only a plausible trailing EventKit birthday-age suffix.
  static func birthdayTitle(_ title: String, showAge: Bool) -> String {
    guard let parsed = parsedBirthdayTitle(title) else { return title }
    return showAge ? "\(parsed.title) (\(parsed.age))" : parsed.title
  }

  /// Classifies likely system holiday subscriptions without arbitrary substring matches.
  static func isHolidayCalendar(isSubscription: Bool, titles: [String]) -> Bool {
    guard isSubscription else { return false }
    return titles.map(normalizedSearchText(_:)).contains(where: matchesHolidayName(_:))
  }

  /// Returns whether a formatted end time carries information not present in the start time.
  static func shouldShowEndTime(
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    calendar: Calendar
  ) -> Bool {
    guard !isAllDay, endDate > startDate else { return false }
    guard calendar.isDate(startDate, inSameDayAs: endDate) else { return true }

    let startComponents = calendar.dateComponents([.hour, .minute], from: startDate)
    let endComponents = calendar.dateComponents([.hour, .minute], from: endDate)
    return startComponents != endComponents
  }

  /// Returns the parsed birthday title.
  private static func parsedBirthdayTitle(_ title: String) -> (title: String, age: Int)? {
    guard title.last == ")", let marker = title.range(of: " (", options: .backwards) else {
      return nil
    }

    let ageStart = marker.upperBound
    let ageEnd = title.index(before: title.endIndex)
    guard ageStart < ageEnd else { return nil }

    let ageText = title[ageStart..<ageEnd]
    guard ageText.count <= 3, ageText.allSatisfy(\.isNumber), let age = Int(ageText) else {
      return nil
    }
    guard (0...150).contains(age) else { return nil }

    let base = title[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !base.isEmpty else { return nil }
    return (base, age)
  }

  /// Returns the normalized search text.
  private static func normalizedSearchText(_ value: String) -> String {
    value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
      .split(whereSeparator: { !$0.isLetter })
      .joined(separator: " ")
  }

  /// Evaluates the holiday name condition.
  private static func matchesHolidayName(_ value: String) -> Bool {
    let tokens = value.split(separator: " ").map(String.init)
    guard let last = tokens.last else { return false }

    if ["holiday", "holidays", "feiertag", "feiertage"].contains(last) {
      return true
    }

    return value.hasSuffix("jour ferie") || value.hasSuffix("jours feries")
  }
}

/// Buckets events by overlapping days without rescanning the complete event list per section.
enum CalendarSectionBucketer {
  /// Returns the bucket.
  static func bucket(
    events: [CalendarAgentEvent],
    sectionStartDate: Date,
    dayCount: Int,
    calendar: Calendar
  ) -> [[CalendarAgentEvent]] {
    guard (1...CalendarAgentRequestLimits.maximumSectionDayCount).contains(dayCount) else {
      return []
    }

    let firstDay = calendar.startOfDay(for: sectionStartDate)
    guard let end = calendar.date(byAdding: .day, value: dayCount, to: firstDay) else {
      return []
    }

    var buckets = Array(repeating: [CalendarAgentEvent](), count: dayCount)
    for event in events {
      let overlapStart = max(event.startDate, sectionStartDate)
      let overlapEnd = min(event.endDate, end)
      guard overlapStart < overlapEnd else { continue }

      let eventFirstDay = calendar.startOfDay(for: overlapStart)
      let lastIncludedInstant = overlapEnd.addingTimeInterval(-0.001)
      let eventLastDay = calendar.startOfDay(for: max(overlapStart, lastIncludedInstant))
      guard
        let firstOffset = calendar.dateComponents([.day], from: firstDay, to: eventFirstDay).day,
        let lastOffset = calendar.dateComponents([.day], from: firstDay, to: eventLastDay).day
      else {
        continue
      }

      let lower = max(0, firstOffset)
      let upper = min(dayCount - 1, lastOffset)
      guard lower <= upper else { continue }
      for offset in lower...upper {
        buckets[offset].append(event)
      }
    }

    for index in buckets.indices {
      buckets[index].sort { lhs, rhs in
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        return lhs.id < rhs.id
      }
    }
    return buckets
  }
}
