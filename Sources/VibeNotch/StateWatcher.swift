import SwiftUI
import Combine

final class ClaudeState: ObservableObject {
    static let shared = ClaudeState()
    @Published var pattern: IndicatorPattern = .idle

    // State is written to this file by Claude Code hooks (hooks/vibe-notch-hook.sh)
    private let statePath = "/tmp/vibe-notch"
    private var cancellable: AnyCancellable?

    func start() {
        // Poll instead of using FSEvents — simpler and plenty fast for a visual indicator
        cancellable = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        guard let raw = try? String(contentsOfFile: statePath, encoding: .utf8) else {
            if pattern != .idle { pattern = .idle }
            return
        }
        let next: IndicatorPattern
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "thinking": next = .thinking
        case "tool":     next = .tool
        case "awaiting": next = .awaiting
        case "done":     next = .done
        case "off":      next = .off
        default:         next = .idle
        }
        if pattern != next { pattern = next }
    }
}
