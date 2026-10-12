#!/usr/bin/env python3
"""tui_resize.py -- regression test for terminal resize (SIGWINCH).

Reported defect: over SSH the TUI appeared to work, but resizing the terminal
window broke it. Four separate causes, all exercised here:

  1. KEY_RESIZE was never read, so the resize event was discarded and the
     window was never repainted at its new size.
  2. Layout used hardcoded absolute coordinates. A fixed column such as
     mvprintw(1, 40, ...) is fine while the window is wide and corrupts the
     display once it is not, because ncurses wraps the overflow onto the next
     row.
  3. The "screen stays put" wait called getch() under timeout(-1), blocking
     indefinitely, so a resize while a screen was displayed looked frozen.
  4. A window too small to hold the layout produced scribble rather than an
     honest message.

The test drives a real pty, changes the real window size (which makes the
kernel deliver SIGWINCH), and asserts the visible screen at each size.
"""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

# term.Screen/Stream add REP, which pyte lacks and ncurses relies on. See
# tests/term.py: without it this model invents corruption that is not there.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from term import Screen, Stream, HAVE_PYTE
except ImportError:
    try:
        import pyte
        Screen, Stream, HAVE_PYTE = pyte.Screen, pyte.Stream, True
    except ImportError:
        HAVE_PYTE = False

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
BIN = os.path.join(ROOT, "build", "saphira-router")
ADMIN_PW = "Saphira-r0uter!"

FAILS = 0


def check(what, cond, detail=""):
    global FAILS
    if cond:
        print("  ok   %s" % what)
    else:
        FAILS += 1
        print("  FAIL %s%s" % (what, ("\n         " + detail) if detail else ""))


def clean(s):
    s = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s)
    s = re.sub(r"\x1b[()][B0]", "", s)
    return re.sub(r"[ \t]+", " ", s.replace("\r", ""))


def set_winsize(fd, rows, cols):
    """Resize the pty. This is what makes the kernel send SIGWINCH."""
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


class Tui:
    """A TUI running in a pty whose window size we control.

    When pyte is available the pty output is fed to a real terminal emulator
    that is resized alongside the window, so assertions read the screen an
    operator would actually see, row by row. Stripping escape sequences and
    searching the raw stream is not equivalent: ncurses repaints by cursor
    position, so text that looks adjacent in the stream need not be adjacent
    on screen, and a short screen is unrepresentable that way.
    """

    def __init__(self, env, rows, cols):
        self.buf = b""
        self.screen = Screen(cols, rows) if HAVE_PYTE else None
        self.stream = Stream(self.screen) if HAVE_PYTE else None
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ.update(env)
            os.environ["TERM"] = "xterm"
            try:
                os.execv(BIN, [BIN, "tui"])
            except Exception:
                os._exit(127)
        set_winsize(self.fd, rows, cols)
        self.rows, self.cols = rows, cols
        self.settle(1.6)

    def settle(self, secs):
        until = time.time() + secs
        while time.time() < until:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if self.fd in r:
                try:
                    d = os.read(self.fd, 65536)
                except OSError:
                    return
                if not d:
                    return
                self.buf += d
                if self.stream is not None:
                    try:
                        self.stream.feed(d.decode("utf-8", "replace"))
                    except Exception:
                        pass

    def resize(self, rows, cols, settle=1.6):
        self.rows, self.cols = rows, cols
        set_winsize(self.fd, rows, cols)
        if self.screen is not None:
            self.screen.resize(rows, cols)
        self.settle(settle)

    def send(self, keys, settle=1.0):
        try:
            os.write(self.fd, keys)
        except OSError:
            pass
        self.settle(settle)

    def text(self):
        if self.screen is not None:
            return "\n".join(self.screen.display)
        return clean(self.buf.decode("utf-8", "replace"))

    def tail(self, n=2500):
        # With a real screen, truncating the text would cut off the TOP rows --
        # which is exactly where a header or a table lives. The whole point of
        # this test is what is visible after a resize, so the full screen is
        # what must be examined. Only the escape-stripped fallback is capped.
        t = self.text()
        return t if self.screen is not None else t[-n:]

    def lines(self):
        return [l.rstrip() for l in self.text().split("\n")]

    def close(self):
        try:
            os.write(self.fd, b"q")
            self.settle(0.5)
        except OSError:
            pass
        for _ in range(20):
            wpid, _ = os.waitpid(self.pid, os.WNOHANG)
            if wpid == self.pid:
                break
            self.settle(0.2)
        else:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        try:
            os.close(self.fd)
        except OSError:
            pass


def main():
    if not os.path.exists(BIN):
        print("  missing %s -- run make first" % BIN)
        return 1

    tmp = tempfile.mkdtemp(prefix="sr-resize-")
    home = os.path.join(tmp, "home")
    os.makedirs(home, exist_ok=True)
    env = dict(os.environ)
    env["SR_SOCK"] = os.path.join(tmp, "api.sock")
    env["SR_DB"] = os.path.join(tmp, "router.db")
    env["SR_MODULES"] = os.path.join(ROOT, "build")
    # Isolate HOME so the session token cannot leak in from, or be clobbered
    # by, a real operator login on the build host.
    env["HOME"] = home
    env.pop("SR_TOKEN", None)

    subprocess.run([BIN, "init", "--user", "admin", "--password", ADMIN_PW],
                   env=env, capture_output=True, timeout=60)
    daemon = subprocess.Popen([BIN, "daemon"], env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              start_new_session=True)
    for _ in range(60):
        if os.path.exists(env["SR_SOCK"]):
            break
        time.sleep(0.1)

    r = subprocess.run([BIN, "login", "--user", "admin", "--password", ADMIN_PW],
                       env=env, capture_output=True, text=True, timeout=60)
    # Read the token from the file the login wrote. Do NOT scrape it from the
    # login message: that message prints the user_id and deliberately never
    # prints the token ("never print the token itself"). A 32-hex user_id
    # looks exactly like a token, and feeding it back yields
    # {"ok":false,"error":"authentication failed"} with every screen blank.
    tokfile = os.path.join(home, ".saphira-router", "token")
    tok = None
    if os.path.exists(tokfile):
        with open(tokfile) as f:
            tok = f.read().strip()
    if not tok:
        print("  FAIL could not obtain a session token\n         %s" % r.stdout[:300])
        daemon.terminate()
        return 1
    tenv = dict(env)
    tenv["SR_TOKEN"] = tok

    t = Tui(tenv, 40, 120)
    try:
        txt = t.text()
        check("TUI paints the menu at 40x120", "saphira-router" in txt and
              "hotkeys" in txt, repr(txt[-400:]))

        # --- grow: a larger window must repaint, not keep the old frame
        t.resize(50, 160)
        check("growing to 50x160 keeps the interface alive",
              "hotkeys" in t.tail(), repr(t.tail()[-400:]))

        # --- shrink to a workable but much smaller window
        t.resize(24, 80)
        txt = t.tail()
        check("shrinking to 24x80 still shows the menu", "hotkeys" in txt,
              repr(txt[-400:]))

        # --- shrink BELOW the layout minimum: must be honest, not scribble
        t.resize(8, 40)
        txt = t.tail()
        check("an undersized window reports its size instead of scribbling",
              "too small" in txt or "needs at least" in txt, repr(txt[-400:]))
        check("the undersized notice is not corrupted by wrapped overflow",
              "controller:" not in txt.split("too small")[-1][:200],
              repr(txt[-400:]))

        # --- and back again: recovery must not need a keypress
        t.resize(40, 120)
        txt = t.tail()
        check("restoring a large window recovers without a keypress",
              "hotkeys" in txt, repr(txt[-400:]))

        # --- a screen must survive a resize too (defect 3: the blocking wait)
        t.send(b"m")           # modules screen
        txt = t.tail()
        check("modules screen renders the table, not just its header",
              "MODULE" in txt and "fixture" in txt, repr(txt[-600:]))
        t.resize(20, 70)
        txt = t.tail()
        check("resizing while a screen is displayed does not freeze it",
              "MODULE" in txt or "too small" in txt, repr(txt[-400:]))
        t.resize(40, 120)
        txt = t.tail()
        check("the screen redraws after growing back", "MODULE" in txt,
              repr(txt[-400:]))
        t.send(b"\r")          # back to the menu

        # --- rapid successive resizes must not corrupt state
        for rows, cols in ((30, 100), (45, 150), (20, 65), (40, 120)):
            t.resize(rows, cols, settle=0.5)
        txt = t.tail()
        check("rapid resizing leaves a coherent screen", "hotkeys" in txt,
              repr(txt[-400:]))
    finally:
        t.close()
        daemon.terminate()
        try:
            daemon.wait(timeout=5)
        except subprocess.TimeoutExpired:
            daemon.kill()

    print("  %s" % ("RESIZE SUITE PASS" if FAILS == 0
                    else "RESIZE SUITE FAIL (%d)" % FAILS))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
