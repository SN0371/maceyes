import AppKit

// Custom view: draws the accent circle in draw() and centers an NSTextField
// child for the number — the child renders identically to other day cells.
private final class TodayCell: NSView {
    init(day: Int, cellSize: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: cellSize),
            heightAnchor.constraint(equalToConstant: cellSize),
        ])
        let lbl = NSTextField(labelWithString: "\(day)")
        lbl.font = .systemFont(ofSize: 12, weight: .semibold)
        lbl.textColor = .white
        lbl.alignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lbl)
        // Pin width, let intrinsic height float, center within the oval
        NSLayoutConstraint.activate([
            lbl.widthAnchor.constraint(equalToConstant: cellSize),
            lbl.centerXAnchor.constraint(equalTo: centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

// MARK: -

final class CalendarViewController: NSViewController {

    // ISO 8601 calendar: weeks start Monday, week 1 contains first Thursday
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private var displayedDate: Date = Date()

    private var headerLabel: NSTextField!
    private var gridStack: NSStackView!

    private let cellSize:    CGFloat = 26
    private let wkWidth:     CGFloat = 22
    private let cellSpacing: CGFloat = 2
    private let rowCount = 6   // always render 6 rows so the popover size never changes

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildStaticLayout()
        snapToCurrentMonth()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Refresh every time the popover opens so the today highlight
        // stays correct after midnight or across day boundaries.
        snapToCurrentMonth()
    }

    private func snapToCurrentMonth() {
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = 1
        displayedDate = cal.date(from: comps)!
        rebuildGrid()

        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    // MARK: - Layout

    private func buildStaticLayout() {
        let prev = chevronButton("‹", action: #selector(prevMonth))
        let next = chevronButton("›", action: #selector(nextMonth))

        headerLabel = NSTextField(labelWithString: "")
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.alignment = .center

        // Arrows pinned to the edges; label centered between them — positions never shift.
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.heightAnchor.constraint(equalToConstant: 26).isActive = true

        for v in [prev, next, headerLabel!] {
            v.translatesAutoresizingMaskIntoConstraints = false
            headerRow.addSubview(v)
        }
        NSLayoutConstraint.activate([
            prev.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            prev.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            next.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            next.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),

            headerLabel.centerXAnchor.constraint(equalTo: headerRow.centerXAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: prev.trailingAnchor, constant: 4),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: next.leadingAnchor, constant: -4),
        ])

        gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 1
        gridStack.alignment = .leading

        let bottomSep = NSBox()
        bottomSep.boxType = .separator

        let quitBtn = NSButton(title: "Quit macEyes", target: NSApp,
                               action: #selector(NSApplication.terminate(_:)))
        quitBtn.isBordered = false
        quitBtn.font = .systemFont(ofSize: 11)
        quitBtn.contentTintColor = .secondaryLabelColor
        quitBtn.alignment = .center

        let outer = NSStackView(views: [headerRow, gridStack, bottomSep, quitBtn])
        outer.orientation = .vertical
        outer.spacing = 6
        outer.edgeInsets = NSEdgeInsets(top: 10 + cellSize / 2, left: 8, bottom: 8, right: 8)
        outer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: view.topAnchor),
            outer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func rebuildGrid() {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "MMMM yyyy"
        headerLabel.stringValue = df.string(from: displayedDate)

        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Column headers: Wk + weekday abbreviations
        let columnHeaders = ["Wk", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        let colHeaderRow = NSStackView(views: columnHeaders.enumerated().map { i, title in
            let lbl = NSTextField(labelWithString: title)
            lbl.font = .systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = .secondaryLabelColor
            lbl.alignment = .center
            constrain(lbl, width: i == 0 ? wkWidth : cellSize, height: cellSize)
            return lbl
        })
        colHeaderRow.spacing = cellSpacing
        gridStack.addArrangedSubview(colHeaderRow)

        let colSep = NSBox()
        colSep.boxType = .separator
        gridStack.addArrangedSubview(colSep)
        // Extra breathing room between the header separator and the first week row
        gridStack.setCustomSpacing(cellSize / 2 + 2, after: colSep)

        // Today's date components for highlighting
        let today     = Date()
        let todayYear  = cal.component(.year,  from: today)
        let todayMonth = cal.component(.month, from: today)
        let todayDay   = cal.component(.day,   from: today)

        let year        = cal.component(.year,  from: displayedDate)
        let month       = cal.component(.month, from: displayedDate)
        let daysInMonth = cal.range(of: .day, in: .month, for: displayedDate)!.count

        // Column 0 = Monday; startOffset places day 1 in the correct column
        let firstWeekday = cal.component(.weekday, from: displayedDate)
        let startOffset  = (firstWeekday - 2 + 7) % 7   // Mon=0 … Sun=6
        var dayNum = 1 - startOffset

        // Always render exactly 6 rows so the popover size is constant across all months
        for _ in 0..<rowCount {
            // ISO week number: derived from Thursday of this row (Monday + 3 days).
            // Calendar automatically handles day values that overflow into adjacent months.
            var thursdayComps = DateComponents()
            thursdayComps.year  = year
            thursdayComps.month = month
            thursdayComps.day   = dayNum + 3
            let thursday = cal.date(from: thursdayComps)!
            let weekNum  = cal.component(.weekOfYear, from: thursday)

            var cells: [NSView] = []

            let wkLbl = NSTextField(labelWithString: String(weekNum))
            wkLbl.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            wkLbl.textColor = .tertiaryLabelColor
            wkLbl.alignment = .center
            constrain(wkLbl, width: wkWidth, height: cellSize)
            cells.append(wkLbl)

            for col in 0..<7 {
                let d = dayNum + col
                if d >= 1 && d <= daysInMonth {
                    let isToday = d == todayDay && month == todayMonth && year == todayYear
                    cells.append(dayCell(d, isToday: isToday))
                } else {
                    cells.append(blankCell())
                }
            }

            let weekRow = NSStackView(views: cells)
            weekRow.spacing = cellSpacing
            weekRow.alignment = .centerY
            gridStack.addArrangedSubview(weekRow)

            dayNum += 7
        }
    }

    // MARK: - Cell helpers

    private func constrain(_ view: NSView, width: CGFloat, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
    }

    private func dayCell(_ day: Int, isToday: Bool) -> NSView {
        if isToday { return TodayCell(day: day, cellSize: cellSize) }
        let lbl = NSTextField(labelWithString: "\(day)")
        lbl.font = .systemFont(ofSize: 12)
        lbl.alignment = .center
        // Width only — let intrinsic height float so alignment = .centerY
        // places the text at the same row midY as TodayCell's oval center.
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: cellSize).isActive = true
        return lbl
    }

    private func blankCell() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: cellSize),
            v.heightAnchor.constraint(equalToConstant: cellSize),
        ])
        return v
    }

    private func chevronButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.font = .systemFont(ofSize: 17, weight: .light)
        return b
    }

    // MARK: - Navigation

    @objc private func prevMonth() {
        displayedDate = cal.date(byAdding: .month, value: -1, to: displayedDate)!
        rebuildGrid()
    }

    @objc private func nextMonth() {
        displayedDate = cal.date(byAdding: .month, value: 1, to: displayedDate)!
        rebuildGrid()
    }
}
