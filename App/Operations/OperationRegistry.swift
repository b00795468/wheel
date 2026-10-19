import Foundation

/// Catalogue of every operation (§4). The order here is the order on the wheel.
struct OperationRegistry: Sendable {
    let operations: [any FileOperation]

    static let standard: OperationRegistry = {
        var operations: [any FileOperation] = [
            ConvertToImageOperation(format: .jpeg, acceptsPDF: true),
            ConvertToImageOperation(format: .png, acceptsPDF: true),
            ConvertToImageOperation(format: .heic, acceptsPDF: false),
            ImageToWebPOperation(),
            ConvertToImageOperation(format: .tiff, acceptsPDF: false),
            ImagesToPDFOperation(),
        ]
        operations += MediaOutput.allCases.map { MediaConvertOperation(output: $0) as any FileOperation }
        operations.append(CompressOperation())
        operations += ResizePreset.allCases.map { ResizeOperation(preset: $0) as any FileOperation }
        operations += [CopyPathAction(), RevealAction(), AirDropAction()] as [any FileOperation]
        return OperationRegistry(operations: operations)
    }()

    /// Operations of `kind` that apply to every one of `files` (§5.2).
    /// Only the URLs are used: the files are not readable before the drop.
    func operations(for files: [URL], kind: WheelMode) -> [any FileOperation] {
        let types = files.map(FileTypes.type(of:))
        return operations.filter { $0.kind == kind && $0.accepts(types) }
    }

    /// Wheel segments for `files`, in registry order: operations sharing a
    /// group become one segment whose children open as a sub-wheel.
    func segments(for files: [URL], kind: WheelMode) -> [WheelSegment] {
        var segments: [WheelSegment] = []
        for operation in operations(for: files, kind: kind) {
            guard let group = operation.group else {
                segments.append(operation.segment)
                continue
            }
            if let index = segments.firstIndex(where: { $0.id == group.id }) {
                segments[index].children.append(operation.segment)
            } else {
                segments.append(WheelSegment(id: group.id, title: group.title, symbol: group.symbol,
                                             children: [operation.segment]))
            }
        }
        return segments
    }

    func operation(withID id: String) -> (any FileOperation)? {
        operations.first { $0.id == id }
    }
}
