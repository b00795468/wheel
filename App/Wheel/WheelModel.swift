import Foundation

/// The three wheels. Each one is opened by tapping its trigger key.
enum WheelMode: CaseIterable {
    case convert, tools, actions

    var title: String {
        switch self {
        case .convert: "Convertir"
        case .tools: "Outils"
        case .actions: "Actions"
        }
    }

    /// Shown on the ring when no segment applies (§5.2).
    var emptyMessage: String {
        switch self {
        case .convert: "Aucune conversion pour ce type"
        case .tools: "Aucun outil pour ce type"
        case .actions: "Aucune action pour ce type"
        }
    }
}

/// Which modifier opens which wheel (§5.1). Remappable in Settings; the
/// three keys always stay distinct.
struct TriggerMapping: Equatable, Codable, Sendable {
    var convert = TriggerKey.shift
    var tools = TriggerKey.command
    var actions = TriggerKey.control

    static let standard = TriggerMapping()

    func key(for mode: WheelMode) -> TriggerKey {
        switch mode {
        case .convert: convert
        case .tools: tools
        case .actions: actions
        }
    }

    func mode(for key: TriggerKey) -> WheelMode? {
        WheelMode.allCases.first { self.key(for: $0) == key }
    }

    /// Gives `key` to `mode`; the wheel that had `key` takes `mode`'s old key.
    func assigning(_ key: TriggerKey, to mode: WheelMode) -> TriggerMapping {
        var mapping = self
        if let other = self.mode(for: key), other != mode {
            mapping.set(self.key(for: mode), for: other)
        }
        mapping.set(key, for: mode)
        return mapping
    }

    private mutating func set(_ key: TriggerKey, for mode: WheelMode) {
        switch mode {
        case .convert: convert = key
        case .tools: tools = key
        case .actions: actions = key
        }
    }
}

/// One choice on the wheel. A segment with children opens them as a
/// sub-wheel when hovered, instead of accepting the drop (§5.4).
struct WheelSegment: Equatable {
    let id: String
    let title: String
    let symbol: String
    var children: [WheelSegment] = []
}

/// What a slot of the ring shows: a segment, the "more" pager, or the way
/// back from a sub-wheel.
enum WheelItem: Equatable {
    case segment(WheelSegment)
    case more
    case back

    static let moreTitle = "Plus…"
    static let moreSymbol = "ellipsis"
    static let backTitle = "Retour"
    static let backSymbol = "chevron.backward"
}

/// Segments of the current wheel or sub-wheel, split into pages of at
/// most `maxItemsPerPage` slots. A sub-wheel always ends with `.back`;
/// when paging is needed, `.more` cycles to the next page.
struct WheelModel: Equatable {
    static let maxItemsPerPage = 8

    let mode: WheelMode
    let segments: [WheelSegment]
    private(set) var page = 0
    /// The segment whose sub-wheel is shown, nil on the main wheel.
    private(set) var parent: WheelSegment?

    init(mode: WheelMode, segments: [WheelSegment]) {
        self.mode = mode
        self.segments = segments
    }

    var title: String { parent?.title ?? mode.title }

    private var current: [WheelSegment] { parent?.children ?? segments }
    /// Slots taken by navigation: "Retour" in a sub-wheel.
    private var reservedSlots: Int { parent == nil ? 0 : 1 }
    private var needsPaging: Bool { current.count > Self.maxItemsPerPage - reservedSlots }
    private var segmentsPerPage: Int { Self.maxItemsPerPage - reservedSlots - (needsPaging ? 1 : 0) }

    var pageCount: Int { max(1, (current.count + segmentsPerPage - 1) / segmentsPerPage) }

    var items: [WheelItem] {
        let start = page * segmentsPerPage
        let end = min(start + segmentsPerPage, current.count)
        var items = current[start..<end].map(WheelItem.segment)
        if needsPaging { items.append(.more) }
        if parent != nil { items.append(.back) }
        return items
    }

    mutating func nextPage() {
        page = (page + 1) % pageCount
    }

    /// Shows the children of `segment` in place of the main wheel.
    mutating func open(_ segment: WheelSegment) {
        guard !segment.children.isEmpty else { return }
        parent = segment
        page = 0
    }

    mutating func goBack() {
        parent = nil
        page = 0
    }
}
