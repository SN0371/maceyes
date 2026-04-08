import AppKit

// MARK: - DayCell

private final class DayCell: NSControl {
    let dateKey: String
    private let day: Int
    private let isToday: Bool
    var isSelected: Bool { didSet { needsDisplay = true } }
    var hasTodos: Bool   { didSet { needsDisplay = true } }
    private let isPast: Bool
    private let sz: CGFloat

    init(day: Int, dateKey: String, isToday: Bool, isPast: Bool, isSelected: Bool, hasTodos: Bool, cellSize: CGFloat) {
        self.day = day
        self.dateKey = dateKey
        self.isToday = isToday
        self.isPast = isPast
        self.isSelected = isSelected
        self.hasTodos = hasTodos
        self.sz = cellSize
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: cellSize),
            heightAnchor.constraint(equalToConstant: cellSize),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isToday {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: bounds).fill()
        } else if isSelected {
            let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let color: NSColor = isToday ? .white : .labelColor
        let weight: NSFont.Weight = isToday ? .semibold : .regular
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: weight),
            .foregroundColor: color,
        ]
        let str = "\(day)" as NSString
        let strSz = str.size(withAttributes: attrs)
        // Shift number up slightly when dot is shown
        let yOffset: CGFloat = hasTodos ? 1.5 : 0
        str.draw(in: NSRect(
            x: (bounds.width  - strSz.width)  / 2,
            y: (bounds.height - strSz.height) / 2 + yOffset,
            width: strSz.width,
            height: strSz.height
        ), withAttributes: attrs)

        if hasTodos {
            let dotColor: NSColor = isToday  ? .white.withAlphaComponent(0.75)
                                 : isPast    ? NSColor.systemRed.withAlphaComponent(0.7)
                                             : NSColor.controlAccentColor.withAlphaComponent(0.6)
            dotColor.setFill()
            let dotD: CGFloat = 3
            NSBezierPath(ovalIn: NSRect(
                x: (bounds.width - dotD) / 2,
                y: 3,
                width: dotD, height: dotD
            )).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - ClosureButton / ClosureCheckbox

private final class ClosureButton: NSButton {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

private final class ClosureCheckbox: NSButton {
    private let handler: () -> Void
    init(isChecked: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        isBordered = false
        title = ""
        image = NSImage(systemSymbolName: isChecked ? "checkmark.circle.fill" : "circle",
                        accessibilityDescription: nil)
        contentTintColor = isChecked ? .controlAccentColor : .tertiaryLabelColor
        imageScaling = .scaleProportionallyUpOrDown
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 14),
            heightAnchor.constraint(equalToConstant: 14),
        ])
        self.target = self
        self.action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

// MARK: - CalendarViewController

final class CalendarViewController: NSViewController {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private let dateKeyFmt: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private var displayedDate: Date = Date()
    private var selectedDateKey: String? = nil
    private var dayCells: [String: DayCell] = [:]

    private var outerStack: NSStackView!
    private var headerLabel: NSTextField!
    private var gridStack: NSStackView!
    private var todoSep: NSBox!
    private var todoDateLabel: NSTextField!
    private var todoStack: NSStackView!
    private var todoInputField: NSTextField?

    private let cellSize:    CGFloat = 26
    private let wkWidth:     CGFloat = 22
    private let cellSpacing: CGFloat = 2
    private let rowCount = 6

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
        snapToCurrentMonth()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeKey()
    }

    private func snapToCurrentMonth() {
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = 1
        displayedDate = cal.date(from: comps)!
        selectedDateKey = dateKeyFmt.string(from: Date())
        rebuildGrid()
        updatePreferredSize()
    }

    // MARK: - Static layout

    private func buildStaticLayout() {
        let prev = chevronButton("‹", action: #selector(prevMonth))
        let next = chevronButton("›", action: #selector(nextMonth))

        headerLabel = NSTextField(labelWithString: "")
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.alignment = .center

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

        todoSep = NSBox()
        todoSep.boxType = .separator
        todoSep.isHidden = true

        todoDateLabel = NSTextField(labelWithString: "")
        todoDateLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        todoDateLabel.textColor = .secondaryLabelColor
        todoDateLabel.alignment = .center
        todoDateLabel.isHidden = true

        todoStack = NSStackView()
        todoStack.orientation = .vertical
        todoStack.spacing = 5
        todoStack.alignment = .leading
        todoStack.isHidden = true

        let bottomSep = NSBox()
        bottomSep.boxType = .separator

        let quitBtn = NSButton(title: "Quit macEyeDo", target: NSApp,
                               action: #selector(NSApplication.terminate(_:)))
        quitBtn.isBordered = false
        quitBtn.font = .systemFont(ofSize: 11)
        quitBtn.contentTintColor = .secondaryLabelColor
        quitBtn.alignment = .center

        outerStack = NSStackView(views: [headerRow, gridStack, todoSep, todoDateLabel, todoStack, bottomSep, quitBtn])
        let outer = outerStack!
        outer.orientation = .vertical
        outer.spacing = 6
        outer.edgeInsets = NSEdgeInsets(top: 10 + cellSize / 2, left: 10, bottom: 10, right: 10)
        outer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outer)
        let bottomPin = outer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        bottomPin.priority = .defaultLow
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: view.topAnchor),
            outer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPin,
        ])
        // Force todoDateLabel and todoStack to fill outer's content width.
        // NSStackView with alignment=.leading only pins the leading edge; trailing must be manual.
        todoDateLabel.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -10).isActive = true
        todoStack.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -10).isActive = true
    }

    // MARK: - Grid

    private func rebuildGrid() {
        dayCells = [:]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "MMMM yyyy"
        headerLabel.stringValue = df.string(from: displayedDate)

        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

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
        gridStack.setCustomSpacing(cellSize / 2 + 2, after: colSep)

        let today      = Date()
        let todayYear  = cal.component(.year,  from: today)
        let todayMonth = cal.component(.month, from: today)
        let todayDay   = cal.component(.day,   from: today)

        let year        = cal.component(.year,  from: displayedDate)
        let month       = cal.component(.month, from: displayedDate)
        let daysInMonth = cal.range(of: .day, in: .month, for: displayedDate)!.count

        let firstWeekday = cal.component(.weekday, from: displayedDate)
        let startOffset  = (firstWeekday - 2 + 7) % 7
        var dayNum = 1 - startOffset

        for _ in 0..<rowCount {
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
            wkLbl.translatesAutoresizingMaskIntoConstraints = false
            wkLbl.widthAnchor.constraint(equalToConstant: wkWidth).isActive = true
            cells.append(wkLbl)

            for col in 0..<7 {
                let d = dayNum + col
                if d >= 1 && d <= daysInMonth {
                    var comps = DateComponents()
                    comps.year = year; comps.month = month; comps.day = d
                    let date = cal.date(from: comps)!
                    let key = dateKeyFmt.string(from: date)
                    let isToday = d == todayDay && month == todayMonth && year == todayYear
                    let isPast  = date < cal.startOfDay(for: today)
                    let cell = DayCell(day: d, dateKey: key, isToday: isToday, isPast: isPast,
                                       isSelected: selectedDateKey == key,
                                       hasTodos: TodoStore.shared.items(for: key).contains(where: { !$0.isCompleted }),
                                       cellSize: cellSize)
                    cell.target = self
                    cell.action = #selector(dayTapped(_:))
                    dayCells[key] = cell
                    cells.append(cell)
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

        if selectedDateKey != nil {
            todoSep.isHidden = false
            todoDateLabel.isHidden = false
            todoStack.isHidden = false
            rebuildTodoSection()
        } else {
            todoSep.isHidden = true
            todoDateLabel.isHidden = true
            todoStack.isHidden = true
        }
    }

    // MARK: - Day selection

    @objc private func dayTapped(_ sender: DayCell) {
        let key = sender.dateKey
        if selectedDateKey == key {
            dayCells[key]?.isSelected = false
            selectedDateKey = nil
            todoSep.isHidden = true
            todoDateLabel.isHidden = true
            todoStack.isHidden = true
        } else {
            if let prev = selectedDateKey { dayCells[prev]?.isSelected = false }
            sender.isSelected = true
            selectedDateKey = key
            todoSep.isHidden = false
            todoDateLabel.isHidden = false
            todoStack.isHidden = false
            rebuildTodoSection()
        }
        updatePreferredSize()
    }

    // MARK: - Todo section

    private func rebuildTodoSection() {
        guard let dateKey = selectedDateKey else { return }
        todoStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        todoInputField = nil
        todoDateLabel.stringValue = formattedDate(for: dateKey)

        for item in TodoStore.shared.items(for: dateKey) {
            let row = makeTodoRow(item: item, dateKey: dateKey)
            todoStack.addArrangedSubview(row)
            row.trailingAnchor.constraint(equalTo: todoStack.trailingAnchor).isActive = true
        }

        let addRow = makeAddRow(dateKey: dateKey)
        todoStack.addArrangedSubview(addRow)
        addRow.trailingAnchor.constraint(equalTo: todoStack.trailingAnchor).isActive = true
    }

    private func makeTodoRow(item: TodoItem, dateKey: String) -> NSView {
        let itemID = item.id

        let checkbox = ClosureCheckbox(isChecked: item.isCompleted) { [weak self] in
            guard let self else { return }
            TodoStore.shared.toggleCompleted(id: itemID, for: dateKey)
            self.dayCells[dateKey]?.hasTodos = TodoStore.shared.items(for: dateKey).contains(where: { !$0.isCompleted })
            self.rebuildTodoSection()
            self.updatePreferredSize()
        }

        let titleLbl = NSTextField(labelWithString: "")
        if item.isCompleted {
            let attrs: [NSAttributedString.Key: Any] = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12),
            ]
            titleLbl.attributedStringValue = NSAttributedString(string: item.title, attributes: attrs)
        } else {
            titleLbl.stringValue = item.title
            titleLbl.font = .systemFont(ofSize: 12)
        }
        titleLbl.maximumNumberOfLines = 0
        titleLbl.cell?.wraps = true
        titleLbl.cell?.lineBreakMode = .byWordWrapping
        // Without preferredMaxLayoutWidth the intrinsic height stays single-line and the
        // text truncates instead of wrapping. Use the known constants to compute the
        // available width: todoStack inner width minus checkbox, two spacings, delete button.
        let todoInnerWidth = wkWidth + cellSpacing + 7 * cellSize + 6 * cellSpacing
        titleLbl.preferredMaxLayoutWidth = todoInnerWidth - 14 - 8 - 16
        titleLbl.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let deleteBtn = ClosureButton(title: "×") { [weak self] in
            guard let self else { return }
            TodoStore.shared.delete(id: itemID, for: dateKey)
            self.dayCells[dateKey]?.hasTodos = TodoStore.shared.items(for: dateKey).contains(where: { !$0.isCompleted })
            self.rebuildTodoSection()
            self.updatePreferredSize()
        }
        deleteBtn.isBordered = false
        deleteBtn.font = .systemFont(ofSize: 13)
        deleteBtn.contentTintColor = .tertiaryLabelColor

        let row = NSStackView(views: [checkbox, titleLbl, deleteBtn])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.spacing = 4
        row.alignment = .centerY
        return row
    }

    private func makeAddRow(dateKey: String) -> NSView {
        let field = NSTextField()
        field.placeholderString = "New todo…"
        field.font = .systemFont(ofSize: 12)
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitAddTodo)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        todoInputField = field

        let addBtn = ClosureButton(title: "+") { [weak self] in self?.commitAddTodo() }
        addBtn.isBordered = false
        addBtn.font = .systemFont(ofSize: 16)
        addBtn.contentTintColor = .controlAccentColor

        let row = NSStackView(views: [field, addBtn])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.spacing = 4
        row.alignment = .centerY
        return row
    }

    @objc private func commitAddTodo() {
        guard let field = todoInputField, let dateKey = selectedDateKey else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        TodoStore.shared.add(title: text, for: dateKey)
        dayCells[dateKey]?.hasTodos = true
        field.stringValue = ""
        rebuildTodoSection()
        updatePreferredSize()
        todoInputField?.window?.makeFirstResponder(todoInputField)
    }

    // MARK: - Helpers

    private func formattedDate(for dateKey: String) -> String {
        guard let date = dateKeyFmt.date(from: dateKey) else { return dateKey }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "EEEE, MMMM d"
        return df.string(from: date)
    }

    private func updatePreferredSize() {
        let gridWidth = wkWidth + cellSpacing + 7 * cellSize + 6 * cellSpacing + 20
        // Set the width first so relative constraints resolve and labels can compute
        // their wrapped intrinsic height before fittingSize is queried.
        outerStack.frame.size.width = gridWidth
        outerStack.layoutSubtreeIfNeeded()
        preferredContentSize = CGSize(width: gridWidth, height: outerStack.fittingSize.height)
    }

    private func constrain(_ view: NSView, width: CGFloat, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
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
        selectedDateKey = nil
        displayedDate = cal.date(byAdding: .month, value: -1, to: displayedDate)!
        rebuildGrid()
        updatePreferredSize()
    }

    @objc private func nextMonth() {
        selectedDateKey = nil
        displayedDate = cal.date(byAdding: .month, value: 1, to: displayedDate)!
        rebuildGrid()
        updatePreferredSize()
    }
}
