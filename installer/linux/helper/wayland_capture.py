#!/usr/bin/env python3
"""
Wayland screen-capture helper for Internet Monitoring Agent.

GNOME/KDE Wayland block scrot/ffmpeg. The only sanctioned path is the
xdg-desktop-portal ScreenCast interface + PipeWire. This helper:

  1. Opens a ScreenCast session via org.freedesktop.portal.Desktop
  2. Selects the monitor source with persist_mode=2 (token saved), so the
     "Share your screen?" dialog appears only the FIRST time; subsequent
     runs reuse the restore_token silently.
  3. Starts a GStreamer pipewiresrc pipeline that writes the latest frame
     as JPEG to the given output path every ~333ms (3 fps).

The Flutter agent launches this as a long-lived subprocess during a stream
session, reads the JPEG file, and uploads it. On stop, the agent kills it.

Usage:  wayland_capture.py <output.jpg> <restore_token_file>

Requires (pulled in by the .deb Depends):
  python3-gi gir1.2-gst-1.0 gstreamer1.0-pipewire gstreamer1.0-plugins-good
"""

import os
import sys
import json
import signal
import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst, GLib  # noqa: E402

import dbus  # noqa: E402
from dbus.mainloop.glib import DBusGMainLoop  # noqa: E402

OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ima_frame.jpg"
TOKEN_FILE = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(
    "~/.local/share/internet-monitoring-agent/screencast_token")

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
REQUEST_IFACE = "org.freedesktop.portal.Request"
SCREENCAST_IFACE = "org.freedesktop.portal.ScreenCast"

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
loop = GLib.MainLoop()

portal = bus.get_object(PORTAL, PORTAL_PATH)
screencast = dbus.Interface(portal, SCREENCAST_IFACE)

sender_name = bus.get_unique_name()[1:].replace(".", "_")
_req_counter = [0]


def _new_request_path():
    _req_counter[0] += 1
    token = f"ima{_req_counter[0]}"
    return f"/org/freedesktop/portal/desktop/request/{sender_name}/{token}", token


def _read_token():
    try:
        with open(TOKEN_FILE) as f:
            return f.read().strip()
    except Exception:
        return ""


def _save_token(tok):
    try:
        os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
        with open(TOKEN_FILE, "w") as f:
            f.write(tok or "")
    except Exception:
        pass


session_handle = [None]


def on_response(callback):
    path, token = _new_request_path()

    def handler(response, results):
        bus.remove_signal_receiver(
            handler, "Response", REQUEST_IFACE, PORTAL, path)
        callback(response, results)

    bus.add_signal_receiver(
        handler, "Response", REQUEST_IFACE, PORTAL, path)
    return token


def create_session():
    token = on_response(on_session_created)
    screencast.CreateSession({
        "session_handle_token": "imasession",
        "handle_token": token,
    })


def on_session_created(response, results):
    if response != 0:
        sys.stderr.write("CreateSession failed\n")
        loop.quit()
        return
    session_handle[0] = results["session_handle"]
    select_sources()


def select_sources():
    token = on_response(on_sources_selected)
    opts = {
        "handle_token": token,
        "types": dbus.UInt32(1),        # 1 = MONITOR
        "multiple": False,
        "cursor_mode": dbus.UInt32(2),  # 2 = embedded cursor
        "persist_mode": dbus.UInt32(2), # 2 = persist until revoked
    }
    saved = _read_token()
    if saved:
        opts["restore_token"] = saved
    screencast.SelectSources(session_handle[0], opts)


def on_sources_selected(response, results):
    if response != 0:
        sys.stderr.write("SelectSources failed\n")
        loop.quit()
        return
    start()


def start():
    token = on_response(on_started)
    screencast.Start(session_handle[0], "", {"handle_token": token})


def on_started(response, results):
    if response != 0:
        sys.stderr.write("Start denied by user\n")
        loop.quit()
        return
    # Saqlangan restore_token (keyingi safar dialog chiqmasin)
    if "restore_token" in results:
        _save_token(str(results["restore_token"]))
    streams = results.get("streams", [])
    if not streams:
        sys.stderr.write("No streams\n")
        loop.quit()
        return
    node_id = streams[0][0]
    open_pipewire(node_id)


def open_pipewire(node_id):
    # PipeWire fd ni portal'dan olamiz
    fd_obj = screencast.OpenPipeWireRemote(session_handle[0], {})
    fd = fd_obj.take()

    Gst.init(None)
    # pipewiresrc -> videorate 3fps -> jpegenc -> multifilesink (har frame faylga)
    pipeline_str = (
        f"pipewiresrc fd={fd} path={node_id} do-timestamp=true ! "
        "videoconvert ! videoscale ! "
        "video/x-raw,width=1280 ! "
        "videorate ! video/x-raw,framerate=3/1 ! "
        "jpegenc quality=60 ! "
        f"multifilesink location={OUTPUT} max-files=2"
    )
    pipeline = Gst.parse_launch(pipeline_str)
    pipeline.set_state(Gst.State.PLAYING)
    sys.stderr.write("PipeWire capture started\n")
    sys.stderr.flush()

    def _stop(*_):
        pipeline.set_state(Gst.State.NULL)
        loop.quit()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)


if __name__ == "__main__":
    create_session()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
