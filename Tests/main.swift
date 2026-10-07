// Plain-Swift test runner for the Foundation-only core (no XCTest needed).
// Run with:  ./build.sh test
import Foundation

var failures = 0
var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

let day: TimeInterval = 86_400
let now = Date(timeIntervalSince1970: 1_800_000_000)
let folder = WatchedFolder(path: "/tmp/dl")   // 30 days, warn 5 days

func item(_ name: String, ageDays: Double) -> ScannedItem {
    ScannedItem(url: URL(fileURLWithPath: "/tmp/dl/\(name)"),
                isDirectory: false,
                date: now.addingTimeInterval(-ageDays * day))
}

func eval(_ name: String, ageDays: Double, record: ItemRecord? = nil, at t: Date = now) -> Evaluation {
    Planner.evaluate(item: item(name, ageDays: ageDays), folder: folder, record: record, now: t)
}

// MARK: Planner

check(eval("a", ageDays: 10).verdict == .fresh, "10 days old is fresh")
check(eval("a", ageDays: 24).verdict == .fresh, "24 days old is still outside the 5 day window")

let firstWarning = eval("a", ageDays: 26)
check(firstWarning.verdict == .warn, "26 days old, never warned -> warn")
check(firstWarning.daysLeft(now: now) == 5, "first warning promises the full 5 days, got \(firstWarning.daysLeft(now: now))")

check(eval("a", ageDays: 31).verdict == .warn, "overdue but never warned -> warn, not trash")
check(eval("a", ageDays: 31).daysLeft(now: now) == 5, "overdue + never warned gets the full notice period")

check(eval("a", ageDays: 31, record: ItemRecord(firstWarned: now.addingTimeInterval(-5 * day))).verdict == .trash,
      "overdue and warned 5 days ago -> trash")
check(eval("a", ageDays: 31, record: ItemRecord(firstWarned: now.addingTimeInterval(-2 * day))).verdict == .warn,
      "overdue but warned only 2 days ago -> still warn")
check(eval("a", ageDays: 31, record: ItemRecord(firstWarned: now.addingTimeInterval(-2 * day))).daysLeft(now: now) == 3,
      "3 days of notice remain")

let warnedDayBefore = eval("a", ageDays: 26, record: ItemRecord(firstWarned: now.addingTimeInterval(-1 * day)))
check(warnedDayBefore.verdict == .warn && warnedDayBefore.daysLeft(now: now) == 4, "countdown continues: 4 days left")

check(eval("a", ageDays: 40, record: ItemRecord(keptAt: now.addingTimeInterval(-1 * day))).verdict == .fresh,
      "Keep restarts the clock")

// MARK: Engine.apply

let oldItem = eval("old.zip", ageDays: 31, record: ItemRecord(firstWarned: now.addingTimeInterval(-6 * day)))
let warnItem = eval("soon.pdf", ageDays: 27)
let freshItem = eval("new.png", ageDays: 3)

var state = State()
state.records[oldItem.id] = ItemRecord(firstWarned: now.addingTimeInterval(-6 * day),
                                       lastNotified: now.addingTimeInterval(-1 * day))

var trashed: [String] = []
var outcome = Engine.apply(evaluations: [oldItem, warnItem, freshItem], state: &state, now: now, canNotify: true) {
    trashed.append($0.lastPathComponent)
}
check(trashed == ["old.zip"], "only the due, previously warned item is trashed: \(trashed)")
check(outcome.pending.map { $0.name } == ["soon.pdf"], "pending holds only the warning item")
check(outcome.toNotify.map { $0.name } == ["soon.pdf"], "warning item needs a notification")
check(state.records[warnItem.id]?.firstWarned == now, "firstWarned recorded")
check(state.records[oldItem.id] == nil, "trashed item's record is dropped")
check(state.records[freshItem.id] == nil, "fresh item has no record")

// Same day, a minute later: no duplicate notification, still pending.
let later = now.addingTimeInterval(60)
let warnAgain = Planner.evaluate(item: warnItem.item, folder: folder, record: state.records[warnItem.id], now: later)
var stateSameDay = state
outcome = Engine.apply(evaluations: [warnAgain], state: &stateSameDay, now: later, canNotify: true) { _ in }
check(outcome.toNotify.isEmpty, "no second notification on the same day")
check(outcome.pending.count == 1, "still pending")

// Next day: reminder again.
let tomorrow = now.addingTimeInterval(day + 3600)
let warnTomorrow = Planner.evaluate(item: warnItem.item, folder: folder, record: state.records[warnItem.id], now: tomorrow)
var stateNextDay = state
outcome = Engine.apply(evaluations: [warnTomorrow], state: &stateNextDay, now: tomorrow, canNotify: true) { _ in }
check(outcome.toNotify.count == 1, "daily reminder the next day")
check(stateNextDay.records[warnItem.id]?.firstWarned == now, "firstWarned is not overwritten")

// Notifications unavailable: nothing may be trashed and nothing is marked as warned.
var blockedState = State()
blockedState.records[oldItem.id] = ItemRecord(firstWarned: now.addingTimeInterval(-6 * day))
trashed = []
outcome = Engine.apply(evaluations: [oldItem, warnItem], state: &blockedState, now: now, canNotify: false) {
    trashed.append($0.lastPathComponent)
}
check(trashed.isEmpty, "nothing is trashed without notification permission")
check(outcome.blocked == 1, "blocked count")
check(outcome.toNotify.isEmpty, "nothing to notify when notifications are off")
check(blockedState.records[warnItem.id]?.firstWarned == nil, "not marked warned if no notification could be sent")

// A failing trash keeps the item pending.
struct Boom: Error {}
var failState = State()
failState.records[oldItem.id] = ItemRecord(firstWarned: now.addingTimeInterval(-6 * day))
outcome = Engine.apply(evaluations: [oldItem], state: &failState, now: now, canNotify: true) { _ in throw Boom() }
check(outcome.failed.count == 1 && outcome.trashed.isEmpty, "failure reported")
check(failState.records[oldItem.id] != nil, "record kept after a failed trash")

// MARK: Scanner (real files)

let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("sweeptest-\(UUID().uuidString)")
try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

func touch(_ url: URL, ageDays: Double) throws {
    try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-ageDays * day)], ofItemAtPath: url.path)
}

try Data("x".utf8).write(to: tmp.appendingPathComponent("a.txt"))
try Data("x".utf8).write(to: tmp.appendingPathComponent(".hidden"))
try Data("x".utf8).write(to: tmp.appendingPathComponent("movie.mp4.crdownload"))
let sub = tmp.appendingPathComponent("project")
try fm.createDirectory(at: sub, withIntermediateDirectories: true)
let inner = sub.appendingPathComponent("inner.txt")
try Data("x".utf8).write(to: inner)
try touch(tmp.appendingPathComponent("a.txt"), ageDays: 40)
try touch(inner, ageDays: 2)
try touch(sub, ageDays: 50)

let scanned = try FolderScanner.scan(folder: tmp, useAddedDate: false)
let names = Set(scanned.map { $0.url.lastPathComponent })
check(names == ["a.txt", "project"], "hidden files and partial downloads are skipped: \(names)")

if let a = scanned.first(where: { $0.url.lastPathComponent == "a.txt" }) {
    let age = Date().timeIntervalSince(a.date) / day
    check(abs(age - 40) < 0.01, "file age is its modification date, got \(age)")
}
if let p = scanned.first(where: { $0.url.lastPathComponent == "project" }) {
    let age = Date().timeIntervalSince(p.date) / day
    check(abs(age - 2) < 0.01, "folder age follows its newest content, got \(age)")
    check(p.isDirectory, "folder is flagged as a directory")
}

// Engine.evaluate end to end (never warned -> a.txt must be warn, not trash)
let cfg = Config(folders: [WatchedFolder(path: tmp.path)], checkHour: 9)
let result = Engine.evaluate(config: cfg, state: State(), now: Date(), useAddedDate: false)
check(result.errors.isEmpty, "no errors: \(result.errors)")
check(result.evaluations.first(where: { $0.name == "a.txt" })?.verdict == .warn, "40 day old, never warned file gets a warning first")
check(result.evaluations.first(where: { $0.name == "project" })?.verdict == .fresh, "active folder is fresh")

let missing = Engine.evaluate(config: Config(folders: [WatchedFolder(path: tmp.path + "/nope")], checkHour: 9),
                              state: State(), now: Date())
check(missing.errors.count == 1, "missing folder is reported")

// MARK: Safety

let home = URL(fileURLWithPath: "/Users/alice")
check(Safety.rejectionReason(for: URL(fileURLWithPath: "/"), home: home) != nil, "root rejected")
check(Safety.rejectionReason(for: home, home: home) != nil, "home rejected")
check(Safety.rejectionReason(for: URL(fileURLWithPath: "/Users/alice/Library/Mail"), home: home) != nil, "Library rejected")
check(Safety.rejectionReason(for: URL(fileURLWithPath: "/System/Library"), home: home) != nil, "system rejected")
check(Safety.rejectionReason(for: URL(fileURLWithPath: "/Users"), home: home) != nil, "/Users rejected")
check(Safety.rejectionReason(for: URL(fileURLWithPath: "/Users/alice/Downloads"), home: home) == nil, "Downloads allowed")
check(Safety.rejectionReason(for: URL(fileURLWithPath: "/Users/alice/Desktop/Screenshots"), home: home) == nil, "subfolder allowed")

// MARK: Summary

let many = (1...8).map { eval("file\($0).bin", ageDays: 27) }
let text = Summary.notification(for: many, now: now)
check(text.title.hasPrefix("8 items"), "title counts items: \(text.title)")
check(text.title.contains("within 5 days"), "title states the window: \(text.title)")
check(text.body.contains("…and 2 more"), "body is truncated: \(text.body)")
check(Summary.notification(for: [many[0]], now: now).title.hasPrefix("1 item will"), "singular wording")

// MARK: Store

let store = Store(dir: tmp.appendingPathComponent("support"))
var storedConfig = store.loadConfig()
check(storedConfig.folders.first?.path == "~/Downloads", "default config watches ~/Downloads")
storedConfig.folders.append(WatchedFolder(path: "~/Desktop/Shots", maxAgeDays: 7, warnDays: 2))
storedConfig.checkHour = 14
store.saveConfig(storedConfig)
check(store.loadConfig() == storedConfig, "config round-trips")

var storedState = State()
storedState.records["/x"] = ItemRecord(firstWarned: Date(timeIntervalSince1970: 1_700_000_000))
storedState.lastRun = Date(timeIntervalSince1970: 1_700_000_100)
store.saveState(storedState)
check(store.loadState() == storedState, "state round-trips")

store.appendHistory(["one"])
store.appendHistory(["two"])
let historyText = try String(contentsOf: store.historyURL, encoding: .utf8)
check(historyText == "one\ntwo\n", "history appends: \(historyText.debugDescription)")

try? fm.removeItem(at: tmp)
print(failures == 0 ? "All \(checks) checks passed." : "\(failures) of \(checks) checks FAILED.")
exit(failures == 0 ? 0 : 1)
