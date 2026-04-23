import AVFoundation
import SwiftUI
import Combine
import Foundation
import Darwin

final class ClaudeState: ObservableObject {
    static let shared = ClaudeState()
    @Published var pattern: IndicatorPattern = .idle
    @Published var agentCount: Int = 0

    private static let socketPath = "/tmp/vibe-notch.sock"
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.vibenotch.socket", qos: .userInitiated)
    private var agentCancellable: AnyCancellable?
    private var audioPlayer: AVAudioPlayer?

    private struct HookEvent: Decodable {
        let status: String
    }

    func start() {
        queue.async { [weak self] in self?.bindAndListen() }

        agentCancellable = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollAgentCount() }
        pollAgentCount()
    }

    private func bindAndListen() {
        unlink(Self.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverSocket = fd

        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let buf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
                strcpy(buf, ptr)
            }
        }

        let bindOk = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0

        guard bindOk else { close(fd); serverSocket = -1; return }

        chmod(Self.socketPath, 0o600)
        guard listen(fd, 10) == 0 else { close(fd); serverSocket = -1; return }

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        acceptSource?.setEventHandler { [weak self] in self?.acceptConnection() }
        acceptSource?.resume()
    }

    private func acceptConnection() {
        let client = accept(serverSocket, nil, nil)
        guard client >= 0 else { return }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        var pfd = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
        let deadline = Date().addingTimeInterval(0.5)

        while Date() < deadline {
            let r = poll(&pfd, 1, 50)
            if r > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                let n = read(client, &buf, buf.count)
                if n > 0 { data.append(contentsOf: buf[0..<n]) }
                else { break }
            } else if r == 0 && !data.isEmpty {
                break
            } else if r < 0 { break }
        }
        close(client)

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else { return }

        let next: IndicatorPattern
        switch event.status {
        case "processing", "running_tool", "compacting":
            next = .working
        case "waiting_for_approval":
            next = .awaiting
        default:
            next = .idle
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let prev = self.pattern
            if prev != next {
                self.pattern = next
                self.playSound(for: prev, to: next)
            }
        }
    }

    private func pollAgentCount() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let count = Self.countRunningAgents()
            DispatchQueue.main.async {
                if self?.agentCount != count { self?.agentCount = count }
            }
        }
    }

    private func playSound(for old: IndicatorPattern, to new: IndicatorPattern) {
        let prefs = AppPreferences.shared
        let name: String?
        switch (old, new) {
        case (_, .awaiting):
            name = prefs.interruptSoundEnabled ? prefs.interruptSoundName : nil
        case (.working, .idle), (.awaiting, .idle):
            name = prefs.finishSoundEnabled ? prefs.finishSoundName : nil
        default:
            name = nil
        }
        guard let soundName = name else { return }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
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
