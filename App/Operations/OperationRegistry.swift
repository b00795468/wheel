import Foundation

/// Catalogue of every operation (§4). The order here is the order on the wheel.
struct OperationRegistry: Sendable {
    let operations: [any FileOperation]

    static let standard = OperationRegistry(operations: [
        ConvertToImageOperation(format: .jpeg, acceptsPDF: true),
        ConvertToImageOperation(format: .png, acceptsPDF: true),
        ConvertToImageOperation(format: .heic, acceptsPDF: false),
        ConvertToImageOperation(format: .tiff, acceptsPDF: false),
        ImagesToPDFOperation(),
    ])

    /// Operations of `kind` that apply to every one of `files` (§5.2).
    /// Only the URLs are used: the files are not readable before the drop.
    func operations(for files: [URL], kind: WheelMode) -> [any FileOperation] {
        let types = files.map(FileTypes.type(of:))
        return operations.filter { $0.kind == kind && $0.accepts(types) }
    }

    func operation(withID id: String) -> (any FileOperation)? {
        operations.first { $0.id == id }
    }
}
