import AVFoundation
import SwiftUI
import Combine
import Foundation
import Darwin
import AppKit

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
    private var socketHealthCancellable: AnyCancellable?
    private var jsonlHealthCancellable: AnyCancellable?
    private var sessionScanCancellable: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var activityToken: NSObjectProtocol?
    private var lastSocketEventDate = Date()
    private var lastJSONLEventDate = Date()
    // Keyed by session_id, main-thread only
    private var processWatchers: [String: DispatchSourceProcess] = [:]
    private var audioPlayer: AVAudioPlayer?
    // Both keyed by session_id, all accessed on main thread only
    private var jsonlPaths: [String: String] = [:]
    private var lastActivityDate: [String: Date] = [:]
    private var jsonlWatchers: [String: JSONLWatcher] = [:]

    private struct HookEvent: Decodable {
        let session_id: String
        let cwd: String?
        let status: String
        let tool: String?
        let pid: Int?
    }

    func start() {
        // Prevent App Nap: macOS throttles background apps during idle, which delays
        // socket event delivery and coalesces timers — exactly what a monitor can't afford.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Monitoring Claude Code state"
        )

        queue.async { [weak self] in self?.bindAndListen() }
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.startupScan() }

        staleCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.cleanupStaleAgents() }

        processCheckCancellable = Timer.publish(every: 120, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.cleanupExitedAgents() }

        socketHealthCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.rebindSocketIfNeeded() }

        // JSONL watcher rebuild — fixes kqueue staleness, runs less often (expensive)
        jsonlHealthCancellable = Timer.publish(every: 5 * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.rebuildJSONLWatchers() }

        // New-session scan — catches agents whose SessionStart hook was dropped.
        // Cheap ps-only pre-check avoids lsof when no claude processes are running.
        sessionScanCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard Self.claudeIsRunning() else { return }
                    self?.startupScan()
                }
            }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.handleWake() }
    }

    private func handleWake() {
        lastSocketEventDate = Date()  // reset so rebindSocketIfNeeded doesn't double-fire
        // Force-rebuild the socket unconditionally: after sleep, kqueue subscriptions
        // go stale silently even though fcntl still reports the fd as valid.
        queue.async { [weak self] in
            guard let self else { return }
            self.acceptSource?.cancel()
            self.acceptSource = nil
            if self.serverSocket >= 0 { close(self.serverSocket); self.serverSocket = -1 }
            self.bindAndListen()
        }
        // Rebuild JSONL watchers — DispatchSourceFileSystemObject is also kqueue-backed
        // and goes stale silently after sleep just like the socket.
        let paths = jsonlPaths
        for (sessionId, path) in paths {
            stopJSONLWatcher(sessionId: sessionId)
            startJSONLWatcher(sessionId: sessionId, path: path)
        }
        // Re-scan at increasing intervals after wake. Covers sessions active before sleep
        // and new sessions launched right after wake before the socket was ready.
        // The 30s session scan timer also kicks in, so this just fills the early gaps.
        for delay in [0.0, 3.0, 8.0, 20.0, 45.0] {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.startupScan()
            }
        }
        // Evict agents whose processes died while the Mac was asleep.
        cleanupExitedAgents()
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
                // Already tracked by session ID — don't override current state with .idle
                if self.agents.contains(where: { $0.id == item.sessionId }) { continue }
                // Already tracked by cwd with a different session ID (stale scan result) — skip
                if self.agents.contains(where: { $0.cwd == item.cwd && $0.id != item.sessionId }) { continue }
                let entry = AgentEntry(id: item.sessionId, cwd: item.cwd, pattern: .idle, tool: nil)
                self.upsertAgent(entry, knownJsonlPath: item.path)
            }
        }
    }

    // Cheap check: returns true if any claude process is running.
    // Use this before calling runningClaudeCwds() to avoid lsof when unnecessary.
    private static func claudeIsRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 && !data.isEmpty
    }

    // Get cwds of all running claude processes in one pgrep + lsof round-trip.
    private static func runningClaudeCwds() -> [String] {
        // pgrep -x claude: exact name match, foreground processes only (has tty)
        // Output is just PIDs, one per line — tiny, no pipe-buffer deadlock risk.
        let pgrepTask = Process()
        pgrepTask.launchPath = "/usr/bin/pgrep"
        pgrepTask.arguments = ["-x", "claude"]
        let pgrepPipe = Pipe()
        pgrepTask.standardOutput = pgrepPipe
        pgrepTask.standardError = Pipe()
        try? pgrepTask.run()
        // Read BEFORE waitUntilExit to avoid pipe-buffer deadlock on large output
        let pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
        pgrepTask.waitUntilExit()

        let pids = (String(data: pgrepData, encoding: .utf8) ?? "")
            .components(separatedBy: .newlines)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return [] }

        let lsofTask = Process()
        lsofTask.launchPath = "/usr/sbin/lsof"
        lsofTask.arguments = ["-p", pids.map(String.init).joined(separator: ","), "-a", "-d", "cwd", "-Fn"]
        let lsofPipe = Pipe()
        lsofTask.standardOutput = lsofPipe
        lsofTask.standardError = Pipe()
        do { try lsofTask.run() } catch {
            return []
        }
        // lsof can hang post-wake while macOS reinitializes the vnode table.
        // Kill after 3s with SIGKILL (SIGTERM can be ignored while lsof waits on vfs).
        let killTimer = DispatchWorkItem { kill(lsofTask.processIdentifier, SIGKILL) }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3, execute: killTimer)
        // Read pipe before waitUntilExit: pipe EOF unblocks when lsof exits/is killed,
        // guaranteeing this call returns within 3s even if lsof ignores signals.
        let lsofData = lsofPipe.fileHandleForReading.readDataToEndOfFile()
        lsofTask.waitUntilExit()
        killTimer.cancel()

        let lsofOutput = String(data: lsofData, encoding: .utf8) ?? ""
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
    // can see a stuck state. Skips agents whose claude process is still running
    // (user is just AFK).
    private func cleanupStaleAgents() {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let snapshot = agents
        let activity = lastActivityDate
        let paths = jsonlPaths

        // Skip process listing entirely if there are no idle agents past the cutoff.
        // Avoids a ps+lsof wakeup every 30s when nothing needs cleaning.
        let hasCandidates = snapshot.contains { agent in
            agent.pattern == .idle
            && (activity[agent.id] ?? .distantPast) < cutoff
            && paths[agent.id] != nil
        }
        guard hasCandidates else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let runningCwds = Set(Self.runningClaudeCwds())
            // Empty result means lsof likely timed out — skip eviction to avoid
            // incorrectly removing agents whose processes are actually still running.
            guard !runningCwds.isEmpty else { return }
            var staleIds: [String] = []
            for agent in snapshot {
                guard agent.pattern == .idle else { continue }
                guard (activity[agent.id] ?? .distantPast) < cutoff else { continue }
                guard let path = paths[agent.id] else { continue }
                // If the process is still alive in this cwd, don't evict — user is just AFK.
                if !agent.cwd.isEmpty && runningCwds.contains(agent.cwd) { continue }
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
            // If lsof returned nothing, it likely timed out (e.g. post-wake vnode table
            // reinit). Treat empty result as "unknown" — don't evict, risk is false
            // retention not false eviction.
            guard !runningCwds.isEmpty else {
                return
            }
            let deadIds = snapshot.filter { !runningCwds.contains($0.cwd) }.map { $0.id }
            guard !deadIds.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                for id in deadIds { self?.removeAgent(id: id) }
            }
        }
    }

    // MARK: - Socket server

    // Periodic health-check (60 s timer). Rebinds if the socket file disappeared, the fd
    // was closed externally, or kqueue silently stopped delivering events.
    //
    // Two dead-socket signals:
    // 1. JSONL activity but no socket events for 60s — Claude is writing to disk but hooks
    //    aren't arriving. Socket is dead. Rebuild immediately (catches missed permission prompts).
    // 2. No socket events for 5 min AND claude running — general silent-death fallback.
    //
    // Process listing always runs off the socket queue so lsof can't block accepts.
    private func rebindSocketIfNeeded() {
        let lastSocket = lastSocketEventDate
        let lastJSONL = lastJSONLEventDate
        queue.async { [weak self] in
            guard let self else { return }
            let fileExists = FileManager.default.fileExists(atPath: Self.socketPath)
            let fdValid = self.serverSocket >= 0 && fcntl(self.serverSocket, F_GETFL) >= 0
            if !fileExists || !fdValid {
                self.doRebind()
                return
            }
            let socketSilent = Date().timeIntervalSince(lastSocket)
            // Signal 1: JSONL active but socket silent for 60s → dead socket
            if socketSilent > 60 && Date().timeIntervalSince(lastJSONL) < 30 {
                self.doRebind()
                return
            }
            // Signal 2: general 5-min silent-death fallback
            guard socketSilent > 5 * 60 else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self, !Self.runningClaudeCwds().isEmpty else { return }
                self.queue.async { self.doRebind() }
            }
        }
    }

    private func doRebind() {
        acceptSource?.cancel()
        acceptSource = nil
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
        bindAndListen()
        DispatchQueue.main.async { self.lastSocketEventDate = Date() }
    }

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
        DispatchQueue.main.async { [weak self] in self?.lastSocketEventDate = Date() }

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

        // Remove stale entry for same cwd with different session ID — happens when startupScan
        // guessed the wrong JSONL and the real hook now arrives with the actual session ID.
        if !entry.cwd.isEmpty {
            let staleIds = agents.filter { $0.id != entry.id && $0.cwd == entry.cwd }.map { $0.id }
            for sid in staleIds { removeAgent(id: sid) }
        }

        if let idx = agents.firstIndex(where: { $0.id == entry.id }) {
            agents[idx] = entry
        } else {
            agents.append(entry)
            if pinnedAgentId == nil { pinnedAgentId = entry.id }
        }

        if let path = resolvedPath {
            jsonlPaths[entry.id] = path
            if jsonlWatchers[entry.id] == nil {
                startJSONLWatcher(sessionId: entry.id, path: path)
            }
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
        stopJSONLWatcher(sessionId: id)
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

    // MARK: - JSONL File Watching

    // Watches the session transcript file for writes. Any new content that doesn't
    // contain end_turn means Claude is actively processing — catches hook events that
    // are silently dropped before they reach the socket.
    private final class JSONLWatcher {
        let source: DispatchSourceFileSystemObject
        let handle: FileHandle
        var offset: UInt64

        init(source: DispatchSourceFileSystemObject, handle: FileHandle, offset: UInt64) {
            self.source = source
            self.handle = handle
            self.offset = offset
        }

        deinit { source.cancel() }
    }

    private func startJSONLWatcher(sessionId: String, path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        let initialOffset = (try? handle.seekToEnd()) ?? 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: handle.fileDescriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        let watcher = JSONLWatcher(source: source, handle: handle, offset: initialOffset)
        jsonlWatchers[sessionId] = watcher
        source.setEventHandler { [weak self] in self?.handleJSONLWrite(sessionId: sessionId) }
        source.setCancelHandler { try? handle.close() }
        source.resume()
    }

    private func stopJSONLWatcher(sessionId: String) {
        jsonlWatchers.removeValue(forKey: sessionId)  // deinit cancels source and closes handle
    }

    // Rebuilds all active JSONL watchers (5-min timer). Fixes kqueue going silently stale
    // during extended runtime. Also recovers offset drift: bytes written while kqueue was
    // dead are processed immediately on rebuild.
    private func rebuildJSONLWatchers() {
        let snapshot = jsonlPaths
        for (sessionId, path) in snapshot {
            let missedOffset = jsonlWatchers[sessionId]?.offset
            stopJSONLWatcher(sessionId: sessionId)
            startJSONLWatcher(sessionId: sessionId, path: path)
            if let missed = missedOffset,
               let watcher = jsonlWatchers[sessionId],
               let currentSize = try? watcher.handle.seekToEnd(),
               currentSize > missed {
                watcher.offset = missed
                handleJSONLWrite(sessionId: sessionId)
            }
        }
    }

    private func handleJSONLWrite(sessionId: String) {
        lastJSONLEventDate = Date()
        guard let watcher = jsonlWatchers[sessionId] else { return }
        guard let size = try? watcher.handle.seekToEnd(), size > watcher.offset,
              let _ = try? watcher.handle.seek(toOffset: watcher.offset),
              let data = try? watcher.handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return }
        watcher.offset = size

        guard let idx = agents.firstIndex(where: { $0.id == sessionId }) else { return }
        let current = agents[idx]
        let prev = pattern

        let hasEndTurn = text.contains("\"stop_reason\":\"end_turn\"") ||
                         text.contains("\"stop_reason\": \"end_turn\"")
        // Only treat a write as "Claude started working" when it contains a real user
        // message — not metadata entries (last-prompt, ai-title, permission-mode) that
        // Claude Code appends after end_turn.
        let hasUserMessage = text.contains("\"type\":\"user\"")

        if hasEndTurn {
            guard current.pattern != .idle else { return }
            agents[idx] = AgentEntry(id: current.id, cwd: current.cwd, pattern: .idle, tool: nil)
        } else if hasUserMessage && current.pattern == .idle {
            agents[idx] = AgentEntry(id: current.id, cwd: current.cwd, pattern: .working, tool: nil)
        } else if current.pattern == .awaiting {
            // Socket event from PreToolUse may have been missed (e.g. socket rebuilding).
            // Any new JSONL write while awaiting means processing resumed — tool result or
            // assistant response after approval/denial — so rescue to .working.
            agents[idx] = AgentEntry(id: current.id, cwd: current.cwd, pattern: .working, tool: nil)
        } else {
            return
        }
        lastActivityDate[sessionId] = Date()
        refreshGlobal(prev: prev)
    }

    // MARK: - Sound

    private func playSound(for old: IndicatorPattern, to new: IndicatorPattern) {
        let prefs = AppPreferences.shared
        guard prefs.soundEnabled else { return }
        let name: String?
        switch (old, new) {
        case (_, .awaiting):
            name = prefs.interruptSoundName
        case (.working, .idle), (.awaiting, .idle):
            name = prefs.finishSoundName
        default:
            name = nil
        }
        guard let soundName = name else { return }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.volume = Float(prefs.soundVolume)
        audioPlayer?.play()
    }
}
