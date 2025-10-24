import SwiftUI
import UIKit

// MARK: - Compact sizing
private enum CalendarUI {
    static let monthTitleSize: CGFloat = 28
    static let cardPadding: CGFloat   = 12
    static let gridHeight: CGFloat    = 220
    static let gridSpacing: CGFloat   = 4
    static let cellHeight: CGFloat    = 30
    static let cellVPad: CGFloat      = 3
    static let weekdayFont: Font      = .caption2.bold()
}

enum FlipDirection { case forward, backward }

// MARK: - Reminders
struct Reminder: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var due: Date
    var notes: String?

    init(id: UUID = UUID(), title: String, due: Date, notes: String? = nil) {
        self.id = id; self.title = title; self.due = due; self.notes = notes
    }
}

extension Date {
    var weekBounds: (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        return (start, end)
    }
}

fileprivate let monthDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

// MARK: - App UI (root view)
struct ContentView: View {
    @State private var selectedDate = Date()
    @State private var showPlanner  = false

    // Timer feature
    @State private var showTimeSheet = false
    @State private var showStudyProgress = false
    @State private var timerDuration: TimeInterval = 60 * 20 // default 20 min

    @AppStorage("tasksByDay") private var tasksData: Data = Data()
    @AppStorage("hourNotesByDay") private var hourNotesData: Data = Data()
    @AppStorage("remindersData") private var remindersData: Data = Data()
    @AppStorage("weeklyProgressData") private var weeklyProgressData: Data = Data() // NEW
    @State private var weekProgress: [Bool] = Array(repeating: false, count: 7)     // NEW
    @AppStorage("didWipeDemoData") private var didWipeDemoData = false

    @State private var reminders: [Reminder] = []
    

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current; f.locale = .current; f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func loadHourNotes(for date: Date) -> [Int:String] {
        guard !hourNotesData.isEmpty,
              let dict = try? JSONDecoder().decode([String:[Int:String]].self, from: hourNotesData)
        else { return [:] }
        return dict[dateKey(date)] ?? [:]
    }
    private func saveHourNotes(_ notes: [Int:String], for date: Date) {
        var dict: [String:[Int:String]] = [:]
        if !hourNotesData.isEmpty,
           let existing = try? JSONDecoder().decode([String:[Int:String]].self, from: hourNotesData) {
            dict = existing
        }
        dict[dateKey(date)] = notes
        hourNotesData = (try? JSONEncoder().encode(dict)) ?? Data()
    }

    private func loadReminders() -> [Reminder] {
        (try? JSONDecoder().decode([Reminder].self, from: remindersData)) ?? []
    }
    private func saveReminders(_ items: [Reminder]) {
        remindersData = (try? JSONEncoder().encode(items)) ?? Data()
    }

    private func upsertReminderFromNotes(for date: Date) {
        let notes = loadHourNotes(for: date)
        let firstNote = notes
            .sorted(by: { $0.key < $1.key })
            .first(where: { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .value.trimmingCharacters(in: .whitespacesAndNewlines)

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 12; comps.minute = 0
        let due = cal.date(from: comps) ?? date

        var items = reminders
        if let idx = items.firstIndex(where: { cal.isDate($0.due, inSameDayAs: due) && $0.notes == "AUTO-HOURLY" }) {
            if let title = firstNote, !title.isEmpty {
                items[idx].title = title
            } else {
                items.remove(at: idx)
            }
        } else if let title = firstNote, !title.isEmpty {
            items.append(Reminder(title: title, due: due, notes: "AUTO-HOURLY"))
        }

        reminders = items
        saveReminders(items)
    }
    // MARK: - Weekly tracker persistence (per-week bool[7])
    private func weekKey(_ date: Date) -> String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        return dateKey(start) // reuse your existing dateKey
    }

    private func loadWeekProgress(for date: Date) -> [Bool] {
        guard !weeklyProgressData.isEmpty,
              let dict = try? JSONDecoder().decode([String:[Bool]].self, from: weeklyProgressData)
        else { return Array(repeating: false, count: 7) }
        return dict[weekKey(date)] ?? Array(repeating: false, count: 7)
    }

    private func saveWeekProgress(_ progress: [Bool], for date: Date) {
        var dict: [String:[Bool]] = [:]
        if !weeklyProgressData.isEmpty,
           let existing = try? JSONDecoder().decode([String:[Bool]].self, from: weeklyProgressData) {
            dict = existing
        }
        dict[weekKey(date)] = Array(progress.prefix(7) + repeatElement(false, count: max(0, 7 - progress.count)))
        weeklyProgressData = (try? JSONEncoder().encode(dict)) ?? Data()
    }

    private func resetAllLocalData() {
        remindersData = Data()
        hourNotesData = Data()
        reminders = []
        weeklyProgressData = Data()   // add inside resetAllLocalData()

    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.purple.opacity(0.2).ignoresSafeArea()
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.clear]),
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 500)
            .ignoresSafeArea()

            VStack(spacing: 14) {
                PlannerHeader(
                    selectedDate: $selectedDate,
                    onDayTapped: { day in
                        selectedDate = day
                        showPlanner = true
                    }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)

                WeeklyRemindersList(
                    selectedDate: $selectedDate,
                    reminders: $reminders,
                    onToggleDone: { _ in }
                )
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))

                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                WeeklySunTracker(
                    selectedDate: $selectedDate,
                    progress: $weekProgress,
                    onToggle: { index in
                        weekProgress[index].toggle()
                        saveWeekProgress(weekProgress, for: selectedDate)
                    }
                )
                .frame(height: 210)

                Button {
                    showTimeSheet = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "timer").font(.system(size: 20, weight: .bold))
                        Text("Set Time").font(.footnote.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .frame(width: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.96, green: 0.52, blue: 0.64))
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
                    )
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.85), Color.white.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }

        .onAppear {
            if !didWipeDemoData {
                resetAllLocalData()
                didWipeDemoData = true
            }
            reminders = loadReminders()
            weekProgress = loadWeekProgress(for: selectedDate)

        }
        .onChange(of: selectedDate) { _, newVal in
            weekProgress = loadWeekProgress(for: newVal)
        }

        .sheet(isPresented: $showPlanner) {
            HourlyScheduleSheet(
                date: selectedDate,
                initialNotes: loadHourNotes(for: selectedDate),
                onSave: { notes in
                    saveHourNotes(notes, for: selectedDate)
                    upsertReminderFromNotes(for: selectedDate)
                }
            )
        }
        .sheet(isPresented: $showTimeSheet) {
            ClockTimeSheet(duration: $timerDuration) {
                showStudyProgress = true
            }
        }
        .fullScreenCover(isPresented: $showStudyProgress) {
            StudyProgressView(
                totalSeconds: Int(timerDuration),
                onFinished: { showStudyProgress = false }
            )
        }
    }
}

// MARK: - WeeklyRemindersList
struct WeeklyRemindersList: View {
    @Binding var selectedDate: Date
    @Binding var reminders: [Reminder]
    var onToggleDone: (UUID) -> Void

    @State private var appeared = false

    var body: some View {
        let (start, end) = selectedDate.weekBounds
        let weekly = reminders
            .filter { $0.due >= start && $0.due < end }
            .sorted { $0.due < $1.due }

        VStack(alignment: .leading, spacing: 10) {
            Text("This Week")
                .font(.headline)
                .padding(.leading, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: appeared)

            if weekly.isEmpty {
                EmptyStateCard(text: "Nothing listed yet")
                    .opacity(0.6)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(weekly.enumerated()), id: \.element.id) { idx, item in
                        ReminderCard(reminder: item)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.85)
                                .delay(0.05 * Double(idx)),
                                value: appeared
                            )
                            .onTapGesture { onToggleDone(item.id) }
                    }
                }
            }
        }
        .onAppear { appeared = true }
        .onChange(of: selectedDate) { _, _ in
            appeared = false
            DispatchQueue.main.async { appeared = true }
        }
    }
}

private struct EmptyStateCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
}

struct ReminderCard: View {
    let reminder: Reminder

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                let parts = monthDayFormatter.string(from: reminder.due).split(separator: " ")
                Text(parts.first.map(String.init) ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(parts.dropFirst().first.map(String.init) ?? "")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if let notes = reminder.notes, !notes.isEmpty, notes != "AUTO-HOURLY" {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
}

// MARK: - PlannerHeader (page-curl)
struct PlannerHeader: View {
    @Binding var selectedDate: Date
    var onDayTapped: (Date) -> Void

    @State private var displayedMonth: Date = Date()
    @State private var flipToken: Int = 0
    @State private var flipDir: FlipDirection = .forward
    @State private var pendingMonth: Date? = nil

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    let target = calendar.monthByAdding(-1, to: displayedMonth)
                    pendingMonth = target
                    flipDir = .backward
                    flipToken &+= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        displayedMonth = target
                        pendingMonth = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(6)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                }

                Spacer()

                Text(monthTitle(displayedMonth))
                    .font(.custom("Winter Song", size: CalendarUI.monthTitleSize)).bold()

                Spacer()

                Button {
                    let target = calendar.monthByAdding(1, to: displayedMonth)
                    pendingMonth = target
                    flipDir = .forward
                    flipToken &+= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        displayedMonth = target
                        pendingMonth = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(6)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                }
            }

            Divider().padding(.vertical, 2)

            CurlContainer(
                direction: flipDir,
                token: flipToken,
                current: AnyView(MonthGrid(
                    month: displayedMonth,
                    selectedDate: $selectedDate,
                    onDayTapped: onDayTapped
                )),
                next: AnyView(MonthGrid(
                    month: (pendingMonth ?? displayedMonth),
                    selectedDate: $selectedDate,
                    onDayTapped: onDayTapped
                ))
            )
            .frame(maxWidth: .infinity)
            .frame(height: CalendarUI.gridHeight)
            .animation(.none, value: displayedMonth)
        }
        .onAppear { displayedMonth = selectedDate }
        .onChange(of: selectedDate, initial: false) { _, newValue in
            if pendingMonth == nil &&
               !calendar.isDate(newValue, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newValue
            }
        }
        .padding(CalendarUI.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }
}

// MARK: - MonthGrid
struct MonthGrid: View {
    let month: Date
    @Binding var selectedDate: Date
    var onDayTapped: (Date) -> Void

    @Environment(\.calendar) private var calendar
    private let columns = Array(repeating: GridItem(.flexible(), spacing: CalendarUI.gridSpacing), count: 7)

    var body: some View {
        VStack(spacing: CalendarUI.gridSpacing) {
            HStack {
                ForEach(weekdayInitials(), id: \.self) { sym in
                    Text(sym)
                        .font(CalendarUI.weekdayFont)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: CalendarUI.gridSpacing) {
                ForEach(gridDays(for: month), id: \.self) { day in
                    DayCell(
                        day: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day),
                        isCurrentMonth: calendar.isDate(day, equalTo: month, toGranularity: .month)
                    )
                    .onTapGesture {
                        selectedDate = day
                        onDayTapped(day)
                    }
                }
            }
        }
    }

    private func weekdayInitials() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = (calendar.firstWeekday - 1 + 7) % 7
        return Array(symbols[shift...] + symbols[..<shift]).map { String($0.prefix(2)).uppercased() }
    }

    private func gridDays(for month: Date) -> [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)!.count
        let weekdayOfFirst = calendar.component(.weekday, from: first)
        let lead = ((weekdayOfFirst - calendar.firstWeekday) + 7) % 7
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: first)!
        let prevDays = calendar.range(of: .day, in: .month, for: prevMonth)!.count

        var dates: [Date] = []
        if lead > 0 {
            for d in (prevDays - lead + 1)...prevDays {
                var c = calendar.dateComponents([.year, .month], from: prevMonth); c.day = d
                dates.append(calendar.date(from: c)!)
            }
        }
        for d in 1...daysInMonth {
            var c = calendar.dateComponents([.year, .month], from: first); c.day = d
            dates.append(calendar.date(from: c)!)
        }
        while dates.count % 7 != 0 { dates.append(dates.last!.addingTimeInterval(86_400)) }
        while dates.count < 42 { dates.append(dates.last!.addingTimeInterval(86_400)) }
        return dates
    }
}

// MARK: - DayCell
private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    @Environment(\.calendar) private var calendar

    var body: some View {
        Text("\(calendar.component(.day, from: day))")
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, CalendarUI.cellVPad)
            .background(backgroundShape)
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isCurrentMonth
                            ? Color(.sRGB, red: 0.98, green: 0.70, blue: 0.78, opacity: 1)
                            : .clear,
                        lineWidth: 1
                    )
            )
            .frame(height: CalendarUI.cellHeight)
            .contentShape(Rectangle())
    }

    private var backgroundShape: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.sRGB, red: 0.96, green: 0.52, blue: 0.64, opacity: 1))
            } else if isToday {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.sRGB, red: 0.96, green: 0.52, blue: 0.64, opacity: 1), lineWidth: 2)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrentMonth ? Color.white : Color.white.opacity(0.6))
            }
        }
    }

    private var foreground: Color {
        if isSelected { return .white }
        if !isCurrentMonth { return .secondary }
        return .primary
    }
}

// MARK: - CurlContainer (page-curl animation)
struct CurlContainer: UIViewRepresentable {
    var direction: FlipDirection
    var token: Int
    var current: AnyView
    var next: AnyView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true

        let host = UIHostingController(rootView: current)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.currentHost = host
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard context.coordinator.lastToken != token else {
            context.coordinator.currentHost?.rootView = current
            return
        }

        let fromHost = context.coordinator.currentHost
        let toHost = UIHostingController(rootView: next)
        toHost.view.backgroundColor = .clear
        toHost.view.translatesAutoresizingMaskIntoConstraints = false
        toHost.view.isHidden = true
        container.addSubview(toHost.view)
        NSLayoutConstraint.activate([
            toHost.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toHost.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toHost.view.topAnchor.constraint(equalTo: container.topAnchor),
            toHost.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let options: UIView.AnimationOptions = (direction == .forward)
            ? [.transitionCurlUp, .showHideTransitionViews]
            : [.transitionCurlDown, .showHideTransitionViews]

        if let fromView = fromHost?.view {
            UIView.transition(from: fromView,
                              to: toHost.view,
                              duration: 0.6,
                              options: options) { _ in
                fromHost?.view.removeFromSuperview()
                context.coordinator.currentHost = toHost
            }
        } else {
            toHost.view.isHidden = false
            context.coordinator.currentHost = toHost
        }

        context.coordinator.lastToken = token
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastToken: Int = -1
        var currentHost: UIHostingController<AnyView>?
    }
}

// MARK: - HourlyScheduleSheet
struct HourlyScheduleSheet: View {
    let date: Date
    @State private var notes: [Int:String]
    var onSave: ([Int:String]) -> Void

    init(date: Date, initialNotes: [Int:String], onSave: @escaping ([Int:String]) -> Void) {
        self.date = date
        self.onSave = onSave
        _notes = State(initialValue: initialNotes)
    }

    private let hours = Array(4...21)

    private var title: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Text("SCHEDULE FOR \(title.uppercased())")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(red: 0.78, green: 0.87, blue: 0.78)))
                    .foregroundColor(.black.opacity(0.8))

                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.85, green: 0.55, blue: 0.55).opacity(0.6), lineWidth: 1)
                }
                .overlay(
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { h in
                            HourRow(
                                hour: h,
                                text: Binding(
                                    get: { notes[h] ?? "" },
                                    set: { notes[h] = $0 }
                                )
                            )
                            if h != hours.last { Divider().overlay(Color(red: 0.85, green: 0.55, blue: 0.55).opacity(0.6)) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                )
                .padding(.horizontal)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(notes) }
                }
            }
        }
    }
}

private struct HourRow: View {
    let hour: Int
    @Binding var text: String
    var body: some View {
        HStack(spacing: 20) {
            Text(String(format: "%02d:00", hour))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 64, alignment: .leading)
                .foregroundColor(.primary)
            TextField("", text: $text, axis: .vertical).lineLimit(1...3)
        }
        .padding(.vertical, 6)
    }
}

extension Calendar {
    func monthByAdding(_ value: Int, to base: Date) -> Date {
        self.date(byAdding: .month, value: value, to: base) ?? base
    }
}

// ======================================================================
// MARK: - Analog clock time sheet (drag hands; no knobs)
// ======================================================================
struct ClockTimeSheet: View {
    @Binding var duration: TimeInterval
    var onConfirm: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var hour: Int = 0    // 0...23
    @State private var minute: Int = 0  // 0...59

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                Text("Move the hands to set time")
                    .font(.headline)

                AnalogClockTimePicker(hour: $hour, minute: $minute)

                // colon-free readout
                Text("\(hour)h \(String(format: "%02d", minute))m")
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))

                Text(readableDuration(hour: hour, minute: minute))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Set Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        duration = TimeInterval(hour * 3600 + minute * 60)
                        onConfirm?()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let total = Int(duration)
                hour = max(0, min(23, total / 3600))
                minute = (total % 3600) / 60
            }
        }
    }

    private func readableDuration(hour: Int, minute: Int) -> String {
        hour > 0 ? "\(hour)h \(minute)m" : "\(minute)m"
    }
}

struct AnalogClockTimePicker: View {
    @Binding var hour: Int   // 0...23 (AM/PM inferred)
    @Binding var minute: Int // 0...59

    private let dialSize: CGFloat = 260
    private let innerHourRadiusRatio: CGFloat = 0.35 // inner ring = hours

    @State private var activeHand: Hand? = nil
    enum Hand { case hour, minute }

    var body: some View {
        ZStack {
            // Dial background
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: dialSize, height: dialSize)
                .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))

            // Tick marks
            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    let isHour = i % 5 == 0
                    Capsule()
                        .fill(isHour ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.35))
                        .frame(width: 2, height: isHour ? 14 : 7)
                        .offset(y: -(dialSize/2) + (isHour ? 10 : 6))
                        .rotationEffect(.degrees(Double(i) * 6))
                }
            }

            // Numbers
            ZStack {
                ForEach(1...12, id: \.self) { n in
                    Text("\(n)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .position(numberPosition(for: n))
                }
            }
            .frame(width: dialSize, height: dialSize)

            // Hands (no knobs)
            hand(angle: hourAngle(hour: hour, minute: minute), width: 5, lengthRatio: 0.58)
            hand(angle: minuteAngle(minute: minute), width: 3, lengthRatio: 0.86)

            Circle().fill(Color.primary).frame(width: 8, height: 8) // center cap
        }
        .frame(width: dialSize, height: dialSize)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let (r, angle) = polar(from: value.location, in: dialSize)
                    if activeHand == nil {
                        activeHand = (r < dialSize * innerHourRadiusRatio) ? .hour : .minute
                    }
                    switch activeHand {
                    case .hour?:
                        setHourAndMinute(fromClockAngle: angle)
                    case .minute?:
                        setMinute(fromClockAngle: angle)
                    case nil:
                        break
                    }
                }
                .onEnded { _ in
                    activeHand = nil
                }
        )
        // double-tap toggles AM/PM
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                hour = hour >= 12 ? hour - 12 : hour + 12
            }
        )
    }

    // MARK: - Rendering helpers
    private func numberPosition(for n: Int) -> CGPoint {
        let r = dialSize * 0.36
        let a = Double(n) * 30.0 - 90.0
        let rad = a * .pi / 180
        let x = dialSize/2 + CGFloat(cos(rad)) * r
        let y = dialSize/2 + CGFloat(sin(rad)) * r
        return CGPoint(x: x, y: y)
    }

    private func hand(angle: Angle, width: CGFloat, lengthRatio: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: width, height: dialSize * lengthRatio / 2)
            .offset(y: -(dialSize * lengthRatio / 4))
            .rotationEffect(angle)
    }

    // MARK: - Angle math
    private func minuteAngle(minute: Int) -> Angle {
        .degrees(Double(minute) * 6.0 - 90.0)
    }

    private func hourAngle(hour: Int, minute: Int) -> Angle {
        let h12 = Double(hour % 12) + Double(minute)/60.0
        return .degrees(h12 * 30.0 - 90.0)
    }

    // r in points, angle is "clock degrees" (0 = 12 o'clock, clockwise positive)
    private func polar(from point: CGPoint, in size: CGFloat) -> (r: CGFloat, angle: Double) {
        let c = CGPoint(x: size/2, y: size/2)
        let dx = point.x - c.x
        let dy = point.y - c.y
        let r = sqrt(dx*dx + dy*dy)
        let deg = Double(atan2(dy, dx)) * 180.0 / .pi
        let clockDeg = (deg + 90.0).truncatingRemainder(dividingBy: 360.0)
        return (r, clockDeg < 0 ? clockDeg + 360.0 : clockDeg)
    }

    // MARK: - Setters (clockwise adds time)
    private func setMinute(fromClockAngle angle: Double) {
        // 360° -> 60min, rounded to nearest minute
        let m = Int(round(angle / 6.0)) % 60
        minute = (m + 60) % 60
    }

    private func setHourAndMinute(fromClockAngle angle: Double) {
        // 360° -> 12h; fractional part becomes minutes
        let hFloat = angle / 30.0 // 0...12
        let base = hour >= 12 ? 12 : 0 // keep AM/PM unless user double-taps
        // wrap to 0...11
        let h12 = (hFloat.truncatingRemainder(dividingBy: 12) + 12).truncatingRemainder(dividingBy: 12)
        let whole = Int(floor(h12))
        let frac = h12 - Double(whole)
        hour = base + whole % 12
        minute = Int(round(frac * 60)) % 60
        if minute == 60 { minute = 0; hour = base + ((whole + 1) % 12) }
    }
}

// ======================================================================
// MARK: - Study Progress (Guided Access with real passcode flow)
// ======================================================================
struct StudyProgressView: View {
    let totalSeconds: Int
    var onFinished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var remaining: Int = 0
    @State private var tick: Timer?

    // Guided Access state
    @State private var gaActive: Bool = UIAccessibility.isGuidedAccessEnabled
    @State private var showExitConfirm = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.25), Color.blue.opacity(0.15)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "book.circle.fill")
                    .font(.system(size: 96))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)

                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .scaleEffect(2.0)

                Text(spelledTime(remaining))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))

                Text(gaActive
                        ? "Guided Access is ON. Ending requires passcode."
                        : "Guided Access not active — you can study without it or enable in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    handleEndTap()
                } label: {
                    Label("End Session", systemImage: "stop.circle")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.8)))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal)
        }
        .onAppear {
            remaining = max(1, totalSeconds)
            startGuidedAccessIfPossible()
            startTimer()
        }
        .onDisappear { tick?.invalidate() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
            gaActive = UIAccessibility.isGuidedAccessEnabled
        }
        .confirmationDialog("End session?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("End Now", role: .destructive) { endSession() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Guided Access isn’t active, so ending won’t require a passcode.")
        }
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - Double(remaining) / Double(totalSeconds)
    }

    private func spelledTime(_ secs: Int) -> String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m \(String(format: "%02d", s))s" }
        return "\(m)m \(String(format: "%02d", s))s"
    }

    private func startTimer() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            remaining -= 1
            if remaining <= 0 {
                tick?.invalidate()
                if gaActive {
                    UIAccessibility.requestGuidedAccessSession(enabled: false) { success in
                        // After passcode (if set) and GA is off, end session
                        if success { endSession() } else { endSession() } // fall-through to exit screen
                    }
                } else {
                    endSession()
                }
            }
        }
        if let tick { RunLoop.main.add(tick, forMode: .common) }
    }

    private func startGuidedAccessIfPossible() {
        UIAccessibility.requestGuidedAccessSession(enabled: true) { enabled in
            DispatchQueue.main.async { gaActive = enabled }
        }
    }

    private func handleEndTap() {
        if gaActive {
            // System will prompt for passcode if required
            UIAccessibility.requestGuidedAccessSession(enabled: false) { success in
                if success { endSession() }
                // If user cancels passcode, stay on screen.
            }
        } else {
            // No GA — don’t auto-exit; ask the user first
            showExitConfirm = true
        }
    }

    private func endSession() {
        onFinished?()
        dismiss()
    }
}
// MARK: - WeeklySunTracker (7 small suns around a semicircle)
struct WeeklySunTracker: View {
    @Binding var selectedDate: Date
    @Binding var progress: [Bool] // length 7
    var onToggle: (Int) -> Void

    private var dayLabels: [String] {
        let cal = Calendar.current
        // Very short weekday symbols (e.g., S M T W T F S), reordered to match firstWeekday
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = (cal.firstWeekday - 1 + 7) % 7
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Big “sun” background / horizon arc
                SunBase()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.35), Color.orange.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        SunRays()
                            .stroke(Color.orange.opacity(0.45), lineWidth: 6)
                            .opacity(0.7)
                    )
                    .shadow(color: .orange.opacity(0.35), radius: 18, y: 8)
                    .padding(.horizontal, 24)
                    .offset(y: size.height * 0.18)

                // Seven small suns along an arc (200° -> -20°)
                DaySuns(progress: $progress, labels: dayLabels) { index in
                    onToggle(index)
                }
            }
        }
    }
}

private struct DaySuns: View {
    @Binding var progress: [Bool]
    let labels: [String]
    var tap: (Int) -> Void

    var startAngle: Double = 200
    var endAngle:   Double = -20

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w/2, y: h*0.78)
            let radius = min(w, h) * 0.42
            let step = (startAngle - endAngle) / 6.0

            ForEach(0..<7, id: \.self) { i in
                let angle = startAngle - (Double(i) * step)
                let pos = pointOnCircle(center: center, r: radius, angleDegrees: angle)
                VStack(spacing: 6) {
                    SunIcon(isOn: progress[safe: i] ?? false)
                        .frame(width: 40, height: 40)
                        .onTapGesture { tap(i) }
                    Text(labels[safe: i] ?? "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .position(pos)
            }
        }
    }

    private func pointOnCircle(center: CGPoint, r: CGFloat, angleDegrees: Double) -> CGPoint {
        let rad = angleDegrees * .pi / 180
        return CGPoint(x: center.x + r * cos(rad), y: center.y + r * sin(rad))
    }
}

// Small sun icon that glows when `isOn` is true
private struct SunIcon: View {
    var isOn: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.yellow.gradient : Color.gray.opacity(0.25))
                .overlay(
                    Circle().stroke(isOn ? Color.orange.opacity(0.9) : Color.gray.opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: isOn ? Color.yellow.opacity(0.9) : .clear, radius: isOn ? 16 : 0, y: isOn ? 2 : 0)

            Rays(count: 8)
                .stroke(isOn ? Color.orange.opacity(0.9) : Color.gray.opacity(0.35), lineWidth: 3)
                .opacity(isOn ? 0.9 : 0.6)
                .padding(4)
        }
        .contentShape(Circle())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isOn)
        .accessibilityLabel(isOn ? "Met quota" : "Not met")
    }
}

// Big base shapes (background sun + rays)
private struct SunBase: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let circle = rect.insetBy(dx: rect.width*0.18, dy: rect.height*0.18)
        p.addEllipse(in: circle)
        return p
    }
}

private struct SunRays: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let innerR = min(rect.width, rect.height) * 0.22
        let outerR = min(rect.width, rect.height) * 0.44
        for deg in stride(from: -20.0, through: 200.0, by: 15.0) {
            let a = CGFloat(deg * .pi / 180)
            let start = CGPoint(x: center.x + innerR * cos(a), y: center.y + innerR * sin(a))
            let end   = CGPoint(x: center.x + outerR * cos(a), y: center.y + outerR * sin(a))
            p.move(to: start)
            p.addLine(to: end)
        }
        return p
    }
}

// Ray shape for mini suns
private struct Rays: Shape {
    var count: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rIn = min(rect.width, rect.height) * 0.62
        let rOut = min(rect.width, rect.height) * 0.88
        for i in 0..<count {
            let a = CGFloat(Double(i) / Double(count) * 2 * .pi)
            p.move(to: CGPoint(x: c.x + rIn * cos(a), y: c.y + rIn * sin(a)))
            p.addLine(to: CGPoint(x: c.x + rOut * cos(a), y: c.y + rOut * sin(a)))
        }
        return p
    }
}

// Safe index helper
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
