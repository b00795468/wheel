import AppKit

/// Runs operations off the main thread and reports through the HUD (§5.6).
/// New jobs never wait for running ones; the limit of two concurrent media
/// jobs arrives with ffmpeg in phase 4.
@MainActor
final class JobQueue {
    private static let completionSound = NSSound.Name("Pop")
    private static let genericFailure = "La conversion a échoué."

    private let hud = HUDController()
    private var running: [UUID: Task<Void, Never>] = [:]

    func run(_ operation: any FileOperation, inputs: [URL]) {
        let id = UUID()
        let context = OperationContext(output: OutputLocator(destination: SettingsStore.outputDestination),
                                       stripsLocation: SettingsStore.stripsLocation)
        let toast = hud.begin(title: operation.title, symbol: operation.symbol) { [weak self] in
            self?.running[id]?.cancel()
        }
        AppInfo.jobLog.info("Job \(operation.id, privacy: .public) started on \(inputs.count) file(s)")

        running[id] = Task.detached(priority: .userInitiated) {
            let result: Result<[URL], Error>
            do {
                result = .success(try await operation.run(inputs: inputs, context: context) { fraction in
                    Task { @MainActor in toast.setProgress(fraction) }
                })
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                self.finish(id, operation: operation, inputs: inputs, toast: toast, result: result)
            }
        }
    }

    private func finish(_ id: UUID, operation: any FileOperation, inputs: [URL], toast: HUDToast,
                        result: Result<[URL], Error>) {
        running[id] = nil
        switch result {
        case .success(let outputs):
            let paths = outputs.map(\.path).joined(separator: ", ")
            AppInfo.jobLog.info("Job \(operation.id, privacy: .public) done: \(paths, privacy: .public)")
            hud.succeed(toast, outputs: outputs)
            if SettingsStore.playsCompletionSound {
                NSSound(named: Self.completionSound)?.play()
            }
        case .failure(let error) where error is CancellationError:
            AppInfo.jobLog.info("Job \(operation.id, privacy: .public) cancelled")
            hud.cancel(toast)
        case .failure(let error):
            let paths = inputs.map(\.path).joined(separator: ", ")
            TechnicalLog.record("\(operation.id) failed on \(paths): \(String(reflecting: error))")
            hud.fail(toast, message: (error as? OperationError)?.message ?? Self.genericFailure)
        }
    }
}
