#!/usr/bin/env python3
"""
NotchAgent hook — sends session state to NotchAgent.app via Unix socket.
Fire-and-forget: exits immediately after sending, no bidirectional handling.
"""
import json
import os
import socket
import subprocess
import sys

SOCKET_PATH = "/tmp/notch-agent.sock"


def find_claude_pid():
    """Walk up the process tree to find the nearest ancestor named 'claude'."""
    try:
        pid = os.getpid()
        for _ in range(6):
            result = subprocess.run(
                ["ps", "-o", "ppid=,comm=", "-p", str(pid)],
                capture_output=True, text=True, timeout=1,
            )
            parts = result.stdout.strip().split(None, 1)
            if len(parts) < 2:
                break
            ppid_str, comm = parts
            if comm.strip() == "claude":
                return int(pid)
            pid = int(ppid_str.strip())
    except Exception:
        pass
    return None


def send_event(state):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        sock.close()
    except (socket.error, OSError):
        pass


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    event = data.get("hook_event_name", "")
    session_id = data.get("session_id", "unknown")
    cwd = data.get("cwd", "")

    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": find_claude_pid(),
    }

    if event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
    elif event in ("UserPromptSubmit", "PostToolUse", "PostToolUseFailure",
                   "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"):
        state["status"] = "processing"
    elif event == "PermissionRequest":
        state["status"] = "waiting_for_approval"
    elif event == "Notification":
        nt = data.get("notification_type")
        if nt == "permission_prompt":
            sys.exit(0)  # PermissionRequest hook handles this with better info
        state["status"] = "waiting_for_input" if nt == "idle_prompt" else "processing"
        state["notification_type"] = nt
    elif event in ("Stop", "StopFailure", "SessionStart"):
        state["status"] = "waiting_for_input"
    elif event == "SessionEnd":
        state["status"] = "ended"
    else:
        state["status"] = "unknown"

    send_event(state)


if __name__ == "__main__":
    main()
