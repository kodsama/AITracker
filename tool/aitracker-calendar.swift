// Publishes the AI hours as a macOS calendar.
//
// Diarium reads system calendars as one of its sources, so a calendar of its
// own is how this tool shows up there without touching Diarium's database.
// Apple Calendar and anything else reading EventKit gets it for free.
//
// Reads one JSON request, from the file named as the first argument or from
// stdin, and writes one JSON result on stdout:
//   {"calendar":"AI work","from":"2026-07-01","to":"2026-09-22","dryRun":false,
//    "days":[{"date":"2026-09-21","title":"AI work: 3h 20m","notes":"..."}]}

import EventKit
import Foundation

struct Day: Decodable {
  let date: String
  let title: String
  let notes: String?
}

struct Request: Decodable {
  let calendar: String
  let from: String
  let to: String
  let days: [Day]
  let dryRun: Bool
}

func fail(_ message: String) -> Never {
  let payload = ["ok": false, "error": message] as [String: Any]
  let data = try! JSONSerialization.data(withJSONObject: payload)
  FileHandle.standardOutput.write(data)
  exit(1)
}

let formatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone.current
  return formatter
}()

let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let input: Data
if let argument {
  guard let fromFile = FileManager.default.contents(atPath: argument) else {
    fail("no request at \(argument)")
  }
  input = fromFile
} else {
  guard let piped = try? FileHandle.standardInput.readToEnd() ?? Data(),
        !piped.isEmpty else {
    fail("no request on stdin")
  }
  input = piped
}
guard let request = try? JSONDecoder().decode(Request.self, from: input) else {
  fail("could not read the request")
}
guard let from = formatter.date(from: request.from),
      let to = formatter.date(from: request.to) else {
  fail("from and to must be yyyy-MM-dd")
}

let store = EKEventStore()
var granted = false
let wait = DispatchSemaphore(value: 0)
store.requestFullAccessToEvents { ok, _ in
  granted = ok
  wait.signal()
}
if wait.wait(timeout: .now() + 60) == .timedOut { fail("no answer to the calendar permission prompt") }
if !granted {
  fail("calendar access was refused; allow it in System Settings, Privacy & Security, Calendars")
}

// The calendar this tool owns, created on a local source so it stays on the
// machine unless the user moves it themselves.
var calendar = store.calendars(for: .event).first { $0.title == request.calendar }
if calendar == nil {
  if request.dryRun {
    calendar = nil
  } else {
    let created = EKCalendar(for: .event, eventStore: store)
    created.title = request.calendar
    created.source =
      store.sources.first { $0.sourceType == .local }
      ?? store.defaultCalendarForNewEvents?.source
    guard created.source != nil else { fail("no calendar source to create in") }
    do {
      try store.saveCalendar(created, commit: true)
    } catch {
      fail("could not create the calendar: \(error.localizedDescription)")
    }
    calendar = created
  }
}

var created = 0
var updated = 0
var removed = 0
var unchanged = 0

let wanted = Dictionary(uniqueKeysWithValues: request.days.map { ($0.date, $0) })
var existing: [String: EKEvent] = [:]

if let calendar {
  let predicate = store.predicateForEvents(
    withStart: from,
    end: Calendar.current.date(byAdding: .day, value: 1, to: to) ?? to,
    calendars: [calendar]
  )
  for event in store.events(matching: predicate) where event.isAllDay {
    let key = formatter.string(from: event.startDate)
    // A day should hold one summary event; anything extra is ours to clear.
    if let earlier = existing[key] {
      if !request.dryRun { try? store.remove(earlier, span: .thisEvent, commit: false) }
      removed += 1
    }
    existing[key] = event
  }
}

for (date, day) in wanted {
  guard let start = formatter.date(from: date) else { continue }
  if let event = existing[date] {
    if event.title == day.title && (event.notes ?? "") == (day.notes ?? "") {
      unchanged += 1
    } else {
      updated += 1
      if !request.dryRun {
        event.title = day.title
        event.notes = day.notes
        try? store.save(event, span: .thisEvent, commit: false)
      }
    }
  } else {
    created += 1
    if !request.dryRun, let calendar {
      let event = EKEvent(eventStore: store)
      event.calendar = calendar
      event.title = day.title
      event.notes = day.notes
      event.isAllDay = true
      event.startDate = start
      event.endDate = start
      try? store.save(event, span: .thisEvent, commit: false)
    }
  }
}

// A day that no longer has hours loses its event, so the calendar keeps
// matching what the transcripts say.
for (date, event) in existing where wanted[date] == nil {
  removed += 1
  if !request.dryRun { try? store.remove(event, span: .thisEvent, commit: false) }
}

if !request.dryRun {
  do {
    try store.commit()
  } catch {
    fail("could not save the calendar: \(error.localizedDescription)")
  }
}

let result: [String: Any] = [
  "ok": true,
  "calendar": request.calendar,
  "created": created,
  "updated": updated,
  "removed": removed,
  "unchanged": unchanged,
  "dryRun": request.dryRun,
]
FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: result))
