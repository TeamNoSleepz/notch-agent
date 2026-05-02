import AVFoundation
import SwiftUI
import Combine
import Foundation
import Darwin

struct AgentEntry: Identifiable, Equatable {
    let id: String          // session_id
    var cwd: String
    var pattern: IndicatorPattern
    var tool: String?
}

final class ClaudeState: ObservableObject {
    static let shared = ClaudeState()
    @Published var agents: [AgentEntry] = []
    @Published var pattern: IndicatorPattern = .idle
    @Published var agentCount: Int = 0
    @Published var pinnedAgentId: String? = nil

    private static let socketPath = "/tmp/notch-agent.sock"
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.notchagent.socket", qos: .userInitiated)
    private var staleCancellable: AnyCancellable?
    private var processCheckCancellable: AnyCancellable?
    // Keyed by session_id, main-thread only
    private var processWatchers: [String: DispatchSourceProcess] = [:]
    private var audioPlayer: AVAudioPlayer?
    // Both keyed by session_id, all accessed on main thread only
    private var jsonlPaths: [String: String] = [:]
    private var lastActivityDate: [String: Date] = [:]

    private struct HookEvent: Decodable {
        let session_id: String
        let cwd: String?
        let status: String
        let tool: String?
        let pid: Int?
    }

    func start() {
        queue.async { [weak self] in self?.bindAndListen() }
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.startupScan() }

        staleCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.cleanupStaleAgents() }

        processCheckCancellable = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.cleanupExitedAgents() }
    }

    // MARK: - Startup scan (process-anchored)

    // Finds active sessions by looking up the cwd of every running claude process,
    // then finding the most recently modified non-ended JSONL for each cwd.
    // This catches idle sessions regardless of how long they've been quiet.
    private func startupScan() {
        let cwds = Self.runningClaudeCwds()
        guard !cwds.isEmpty else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [(sessionId: String, cwd: String, path: String)] = []

        for cwd in cwds {
            let key = cwd.replacingOccurrences(of: "/", with: "-")
            let keyPath = "\(home)/.claude/projects/\(key)"
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: keyPath) else { continue }

            let best = files
                .filter { $0.hasSuffix(".jsonl") }
                .compactMap { file -> (sessionId: String, path: String, mtime: Date)? in
                    let path = "\(keyPath)/\(file)"
                    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                    guard let mtime = attrs?[.modificationDate] as? Date,
                          !Self.jsonlIsEnded(path: path) else { return nil }
                    return (sessionId: String(file.dropLast(6)), path: path, mtime: mtime)
                }
                .max(by: { $0.mtime < $1.mtime })

            if let item = best {
                found.append((sessionId: item.sessionId, cwd: cwd, path: item.path))
            }
        }

        guard !found.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for item in found {
                let entry = AgentEntry(id: item.sessionId, cwd: item.cwd, pattern: .idle, tool: nil)
                self.upsertAgent(entry, knownJsonlPath: item.path)
            }
        }
    }

    // Get cwds of all running claude processes in one ps + lsof round-trip.
    private static func runningClaudeCwds() -> [String] {
        let psTask = Process()
        psTask.launchPath = "/bin/ps"
        psTask.arguments = ["-A", "-o", "pid=,tty=,comm="]
        let psPipe = Pipe()
        psTask.standardOutput = psPipe
        psTask.standardError = Pipe()
        try? psTask.run()
        psTask.waitUntilExit()

        let psOutput = String(data: psPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = psOutput.components(separatedBy: .newlines).compactMap { line -> Int? in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            // pid= tty= comm= — skip daemon processes that have no controlling terminal
            guard parts.count >= 3, parts[2] == "claude", parts[1] != "??",
                  let pid = Int(parts[0]) else { return nil }
            return pid
        }
        guard !pids.isEmpty else { return [] }

        let lsofTask = Process()
        lsofTask.launchPath = "/usr/bin/lsof"
        lsofTask.arguments = ["-p", pids.map(String.init).joined(separator: ","), "-a", "-d", "cwd", "-Fn"]
        let lsofPipe = Pipe()
        lsofTask.standardOutput = lsofPipe
        lsofTask.standardError = Pipe()
        try? lsofTask.run()
        lsofTask.waitUntilExit()

        let lsofOutput = String(data: lsofPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Array(Set(
            lsofOutput.components(separatedBy: .newlines).compactMap { line -> String? in
                guard line.hasPrefix("n") else { return nil }
                let path = String(line.dropFirst())
                return (path.isEmpty || path == "/") ? nil : path
            }
        ))
    }

    // MARK: - JSONL helpers

    private static func jsonlIsEnded(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { handle.closeFile() }
        let size = handle.seekToEndOfFile()
        let offset = size > 4096 ? size - 4096 : 0
        handle.seek(toFileOffset: offset)
        let text = String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.contains("\"stop_reason\":\"end_turn\"") || text.contains("\"stop_reason\": \"end_turn\"")
    }

    private static func jsonlPath(sessionId: String, cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let key = cwd.replacingOccurrences(of: "/", with: "-")
        return "\(home)/.claude/projects/\(key)/\(sessionId).jsonl"
    }

    // MARK: - Stale cleanup

    // Covers crashes: file stops updating and stop_reason never appears.
    // Only removes idle agents — working/awaiting stay visible so the user
    // can see a stuck state.
    private func cleanupStaleAgents() {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let snapshot = agents
        let activity = lastActivityDate
        let paths = jsonlPaths

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var staleIds: [String] = []
            for agent in snapshot {
                guard agent.pattern == .idle else { continue }
                guard (activity[agent.id] ?? .distantPast) < cutoff else { continue }
                guard let path = paths[agent.id] else { continue }
                let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
                if mtime < cutoff { staleIds.append(agent.id) }
            }
            guard !staleIds.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                for id in staleIds { self?.removeAgent(id: id) }
            }
        }
    }

    // Removes agents whose cwd no longer has a running claude process.
    // Catches the case where the user closes the terminal without /exit.
    private func cleanupExitedAgents() {
        let snapshot = agents.filter { !$0.cwd.isEmpty }
        guard !snapshot.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let runningCwds = Set(Self.runningClaudeCwds())
            let deadIds = snapshot.filter { !runningCwds.contains($0.cwd) }.map { $0.id }
            guard !deadIds.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                for id in deadIds { self?.removeAgent(id: id) }
            }
        }
    }

    // MARK: - Socket server

    private func bindAndListen() {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let buf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
                strcpy(buf, ptr)
            }
        }

        // Retry loop: if Launch at Login races us to the socket file, one instance
        // will lose bind/listen; the retry lets it win on the next attempt.
        for attempt in 0..<6 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.4) }

            unlink(Self.socketPath)

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            let bindOk = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            } == 0

            guard bindOk else { close(fd); continue }
            chmod(Self.socketPath, 0o600)
            guard listen(fd, 10) == 0 else { close(fd); continue }

            serverSocket = fd
            acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            acceptSource?.setEventHandler { [weak self] in self?.acceptConnection() }
            acceptSource?.resume()
            return
        }
    }

    // Drain all pending connections immediately so the listen backlog never saturates.
    // Each connection is handed off to the global queue so the serial accept loop
    // stays unblocked during per-client I/O.
    private func acceptConnection() {
        while true {
            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.readAndProcess(client)
            }
        }
    }

    private func readAndProcess(_ client: Int32) {
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

        if event.status == "ended" {
            let sid = event.session_id
            DispatchQueue.main.async { [weak self] in
                self?.cancelProcessWatcher(for: sid)
                self?.removeAgent(id: sid)
            }
            return
        }

        let next: IndicatorPattern
        switch event.status {
        case "processing", "running_tool", "compacting":
            next = .working
        case "waiting_for_approval":
            next = .awaiting
        default:
            next = .idle
        }

        let entry = AgentEntry(
            id: event.session_id,
            cwd: event.cwd ?? "",
            pattern: next,
            tool: next == .working ? event.tool : nil
        )

        DispatchQueue.main.async { [weak self] in self?.upsertAgent(entry, pid: event.pid) }
    }

    // MARK: - State management (all on main thread)

    private func upsertAgent(_ entry: AgentEntry, knownJsonlPath: String? = nil, pid: Int? = nil) {
        let prev = pattern
        lastActivityDate[entry.id] = Date()

        let resolvedPath = knownJsonlPath ?? (entry.cwd.isEmpty ? nil : Self.jsonlPath(sessionId: entry.id, cwd: entry.cwd))

        if let idx = agents.firstIndex(where: { $0.id == entry.id }) {
            agents[idx] = entry
        } else {
            agents.append(entry)
        }

        if let path = resolvedPath {
            jsonlPaths[entry.id] = path
        }

        if let pid, processWatchers[entry.id] == nil {
            let sessionId = entry.id
            let source = DispatchSource.makeProcessSource(
                identifier: pid_t(pid),
                eventMask: .exit,
                queue: queue
            )
            source.setEventHandler { [weak self] in
                DispatchQueue.main.async { self?.removeAgent(id: sessionId) }
            }
            source.setCancelHandler {}
            processWatchers[sessionId] = source
            source.resume()
        }

        refreshGlobal(prev: prev)
    }

    private func cancelProcessWatcher(for id: String) {
        processWatchers.removeValue(forKey: id)?.cancel()
    }

    private func removeAgent(id: String) {
        let prev = pattern
        agents.removeAll { $0.id == id }
        if pinnedAgentId == id { pinnedAgentId = nil }
        lastActivityDate.removeValue(forKey: id)
        jsonlPaths.removeValue(forKey: id)
        cancelProcessWatcher(for: id)
        refreshGlobal(prev: prev)
    }

    private func refreshGlobal(prev: IndicatorPattern) {
        agentCount = agents.count
        let next = computePattern()
        pattern = next
        if prev != next { playSound(for: prev, to: next) }
    }

    private func computePattern() -> IndicatorPattern {
        if agents.isEmpty { return .idle }
        if agents.contains(where: { $0.pattern == .working }) { return .working }
        if agents.contains(where: { $0.pattern == .awaiting }) { return .awaiting }
        return .idle
    }

    // MARK: - Sound

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
}
