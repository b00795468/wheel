import AppKit
import AudioToolbox

/// Runs operations off the main thread and reports through the HUD (§5.6).
/// New jobs never block: image jobs start at once, audio/video jobs wait
/// for one of `maxConcurrentMediaJobs` ffmpeg slots.
@MainActor
final class JobQueue {
    private static let maxConcurrentMediaJobs = 2
    /// Played through the system sound server: NSSound sets up a full audio
    /// session, which makes macOS check microphone and capture permissions.
    private static let completionSound: SystemSoundID = {
        var sound: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff") as CFURL, &sound)
        return sound
    }()
    private static let genericFailure = "La conversion a échoué."

    private let hud = HUDController()
    private let mediaSlots = AsyncSemaphore(value: JobQueue.maxConcurrentMediaJobs)
    private let ffmpeg = FFmpegRunner.bundled
    private var running: [UUID: Task<Void, Never>] = [:]

    init() {
        if ffmpeg == nil {
            AppInfo.jobLog.error("Embedded ffmpeg not found in the app bundle")
        }
    }

    func run(_ operation: any FileOperation, inputs: [URL]) {
        let id = UUID()
        let context = OperationContext(output: OutputLocator(destination: SettingsStore.outputDestination),
                                       stripsLocation: SettingsStore.stripsLocation, ffmpeg: ffmpeg,
                                       quality: SettingsStore.outputQuality)
        let toast = hud.begin(title: operation.title, symbol: operation.symbol) { [weak self] in
            self?.running[id]?.cancel()
        }
        let slots = operation.usesMediaEngine ? mediaSlots : nil
        AppInfo.jobLog.info("Job \(operation.id, privacy: .public) queued on \(inputs.count) file(s)")

        running[id] = Task.detached(priority: .userInitiated) {
            let result: Result<[URL], Error>
            do {
                try await slots?.wait()
                let outcome: Result<[URL], Error>
                do {
                    outcome = .success(try await operation.run(inputs: inputs, context: context) { fraction in
                        Task { @MainActor in toast.setProgress(fraction) }
                    })
                } catch {
                    outcome = .failure(error)
                }
                await slots?.signal()
                result = outcome
            } catch {
                // Cancelled while waiting for a slot.
                result = .failure(error)
            }
            await MainActor.run {
                self.finish(id, operation: operation, inputs: inputs, toast: toast, result: result)
            }
        }
    }

    /// Stops every job, terminating their ffmpeg processes (app quitting).
    func cancelAll() {
        running.values.forEach { $0.cancel() }
    }

    private func finish(_ id: UUID, operation: any FileOperation, inputs: [URL], toast: HUDToast,
                        result: Result<[URL], Error>) {
        running[id] = nil
        switch result {
        case .success(let outputs):
            let paths = outputs.map(\.path).joined(separator: ", ")
            AppInfo.jobLog.info("Job \(operation.id, privacy: .public) done: \(paths, privacy: .public)")
            if let message = operation.completionMessage(inputs: inputs, outputs: outputs) {
                hud.succeed(toast, message: message, outputs: outputs, symbol: operation.symbol)
            } else {
                hud.cancel(toast)
            }
            if !outputs.isEmpty, SettingsStore.playsCompletionSound {
                AudioServicesPlaySystemSound(Self.completionSound)
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
