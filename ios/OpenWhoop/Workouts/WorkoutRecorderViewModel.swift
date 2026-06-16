import Foundation
import Combine

// MARK: - WorkoutRecorderViewModel
// Owns the live-timer state for an in-progress manual workout.
// Call startWorkout() to lock the start timestamp; stopWorkout() to POST to /v1/manual-workout.

@MainActor
final class WorkoutRecorderViewModel: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var currentHR: Int? = nil
    @Published var selectedType: WorkoutType? = nil
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String? = nil

    private var startTimestamp: Date? = nil
    private var timer: AnyCancellable? = nil

    // Injected so the ViewModel doesn't own a MetricsRepository directly —
    // the view passes metrics.logManualWorkout via the stopAction closure.
    var logAction: ((_ startTs: TimeInterval, _ endTs: TimeInterval, _ kind: String?, _ distanceMi: Double?) async -> Bool)?

    // MARK: - Timer control

    func startWorkout() {
        guard !isRecording else { return }
        startTimestamp = Date()
        elapsedSeconds = 0
        isRecording = true
        errorMessage = nil
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startTimestamp else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(start))
            }
    }

    func stopWorkout(distanceMi: Double? = nil) async -> Bool {
        guard isRecording, let start = startTimestamp else { return false }
        timer?.cancel()
        timer = nil
        isRecording = false
        isSubmitting = true
        defer { isSubmitting = false }

        let end = Date()
        let ok = await logAction?(start.timeIntervalSince1970, end.timeIntervalSince1970, selectedType?.rawValue, distanceMi) ?? false        if !ok {
            errorMessage = "Couldn't save workout — check server connection."
        }
        return ok
    }

    func discardWorkout() {
        timer?.cancel()
        timer = nil
        isRecording = false
        startTimestamp = nil
        elapsedSeconds = 0
        errorMessage = nil
    }

    // MARK: - Formatting

    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}