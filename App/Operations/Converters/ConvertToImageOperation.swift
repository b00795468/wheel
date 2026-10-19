import Foundation
import UniformTypeIdentifiers

/// "To <format>": images to another image format, and PDF pages to PNG or
/// JPG (§5.4). Never offered for a file that already has that format.
struct ConvertToImageOperation: FileOperation {
    let format: ImageFormat
    /// Only PNG and JPG are offered for PDFs (§5.4).
    let acceptsPDF: Bool

    var id: String { "convert.\(format.fileExtension)" }
    var kind: WheelMode { .convert }
    var title: String { format.title }
    var symbol: String { format.symbol }

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy { type in
            if FileTypes.isPDF(type) { return acceptsPDF }
            return FileTypes.isImage(type) && !format.isSameFormat(as: type)
        }
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let format = self.format.withQuality(context.quality.imageQuality)
        var outputs: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let share = { (fraction: Double) in progress((Double(index) + fraction) / Double(inputs.count)) }
            if FileTypes.isPDF(FileTypes.type(of: input)) {
                outputs.append(try PDFConverter.renderPages(of: input, as: format, output: context.output, progress: share))
            } else {
                outputs.append(try context.output.commit(baseName: input.baseName, fileExtension: format.fileExtension,
                                                         for: input) {
                    try ImageConverter.convert(input, to: format, destination: $0, stripsLocation: context.stripsLocation)
                })
            }
            share(1)
        }
        return outputs
    }
}
