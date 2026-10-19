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

    /// Default mapping (§5.1). Becomes remappable in Settings in phase 6.
    var trigger: TriggerKey {
        switch self {
        case .convert: .shift
        case .tools: .command
        case .actions: .control
        }
    }

    static func mode(for key: TriggerKey) -> WheelMode? {
        allCases.first { $0.trigger == key }
    }
}

/// One choice on the wheel.
struct WheelSegment: Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// What a slot of the ring shows: a segment, or the "more" pager.
enum WheelItem: Equatable {
    case segment(WheelSegment)
    case more

    static let moreTitle = "Plus…"
    static let moreSymbol = "ellipsis"
}

/// Segments of the current wheel, split into pages of at most
/// `maxItemsPerPage` slots. When paging is needed, the last slot of every
/// page is `.more`, which cycles to the next page.
struct WheelModel: Equatable {
    static let maxItemsPerPage = 8

    let mode: WheelMode
    let segments: [WheelSegment]
    private(set) var page = 0

    init(mode: WheelMode, segments: [WheelSegment]) {
        self.mode = mode
        self.segments = segments
    }

    private var needsPaging: Bool { segments.count > Self.maxItemsPerPage }
    private var segmentsPerPage: Int { needsPaging ? Self.maxItemsPerPage - 1 : Self.maxItemsPerPage }

    var pageCount: Int { max(1, (segments.count + segmentsPerPage - 1) / segmentsPerPage) }

    var items: [WheelItem] {
        let start = page * segmentsPerPage
        let end = min(start + segmentsPerPage, segments.count)
        let pageItems = segments[start..<end].map(WheelItem.segment)
        return needsPaging ? pageItems + [.more] : pageItems
    }

    mutating func nextPage() {
        page = (page + 1) % pageCount
    }
}

/// Stand-in segments for phase 2. The operation registry replaces this in phase 3.
enum PlaceholderSegments {
    static func segments(for mode: WheelMode) -> [WheelSegment] {
        switch mode {
        case .convert:
            [
                WheelSegment(id: "convert.png", title: "PNG", symbol: "photo"),
                WheelSegment(id: "convert.jpg", title: "JPG", symbol: "photo.fill"),
                WheelSegment(id: "convert.heic", title: "HEIC", symbol: "photo.on.rectangle"),
                WheelSegment(id: "convert.webp", title: "WebP", symbol: "globe"),
                WheelSegment(id: "convert.tiff", title: "TIFF", symbol: "doc.richtext"),
                WheelSegment(id: "convert.pdf", title: "PDF", symbol: "doc.text"),
            ]
        case .tools:
            [
                WheelSegment(id: "tool.compress", title: "Compresser", symbol: "arrow.down.right.and.arrow.up.left"),
                WheelSegment(id: "tool.resize", title: "Redimensionner", symbol: "aspectratio"),
            ]
        case .actions:
            [
                WheelSegment(id: "action.copyPath", title: "Copier le chemin", symbol: "doc.on.clipboard"),
                WheelSegment(id: "action.reveal", title: "Afficher", symbol: "folder"),
                WheelSegment(id: "action.airdrop", title: "AirDrop", symbol: "airplayaudio"),
            ]
        }
    }
}
