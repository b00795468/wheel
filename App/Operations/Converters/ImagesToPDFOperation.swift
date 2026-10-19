import Foundation
import UniformTypeIdentifiers

/// "PDF": one PDF from one or several images, pages in drag order (§5.4).
struct ImagesToPDFOperation: FileOperation {
    let id = "convert.pdf"
    let kind = WheelMode.convert
    let title = "PDF"
    let symbol = "doc.text"

    func accepts(_ types: [UTType]) -> Bool {
        !types.isEmpty && types.allSatisfy(FileTypes.isImage)
    }

    func run(inputs: [URL], context: OperationContext,
             progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let first = inputs.first else { return [] }
        let pdf = try context.output.commit(baseName: first.baseName, fileExtension: "pdf", for: first) {
            try PDFConverter.makePDF(from: inputs, destination: $0, progress: progress)
        }
        return [pdf]
    }
}
