import SwiftUI
import Combine

final class ClaudeState: ObservableObject {
    static let shared = ClaudeState()
    @Published var pattern: IndicatorPattern = .idle
    @Published var agentCount: Int = 0

    // State is written to this file by Claude Code hooks (hooks/vibe-notch-hook.sh)
    private let statePath = "/tmp/vibe-notch"
    private var cancellable: AnyCancellable?
    private var agentCancellable: AnyCancellable?

    func start() {
        // Poll instead of using FSEvents — simpler and plenty fast for a visual indicator
        cancellable = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
        poll()

        agentCancellable = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollAgentCount() }
        pollAgentCount()
    }

    private func poll() {
        guard let raw = try? String(contentsOfFile: statePath, encoding: .utf8) else {
            if pattern != .idle { pattern = .idle }
            return
        }
        let next: IndicatorPattern
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "thinking", "tool": next = .working
        case "awaiting":         next = .awaiting
        default:                 next = .idle
        }
        if pattern != next { pattern = next }
    }

    private func pollAgentCount() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let count = Self.countRunningAgents()
            DispatchQueue.main.async {
                if self?.agentCount != count { self?.agentCount = count }
            }
        }
    }

    private static func countRunningAgents() -> Int {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
}
