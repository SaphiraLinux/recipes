"""Drive the TUI over a REAL ssh transport and resize the terminal.

The unit test uses a local pty. This one proves the thing that was actually
reported: an operator ssh'd into a host, and resizing broke the interface.
So the resize must be delivered across an ssh pty channel, not a local one.
"""
import fcntl, os, pty, re, select, signal, struct, subprocess, sys, termios, time

# term.Screen/Stream add REP, which pyte lacks and ncurses relies on. Without
# it this model invents corruption that is not on the operator's screen. See
# tests/term.py for why that is not a cosmetic detail.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from term import Screen, Stream
except ImportError:
    import pyte
    Screen, Stream = pyte.Screen, pyte.Stream

# The host to test against. Set SR_SSH_TEST_HOST to point elsewhere; the
# suite skips itself when there is nothing to test against, because an
# acceptance test that silently passes off-host is worse than no test.
HOST = os.environ.get("SR_SSH_TEST_HOST", "hatchling")
BIN  = "/usr/local/bin/saphira-router"
T    = "/tmp/sshtest"
PW   = "Resize-t3st!"

fails = 0
def check(what, cond, detail=""):
    global fails
    print(("  ok   " if cond else "  FAIL ") + what + ("" if cond else "\n         " + detail))
    if not cond: fails += 1

def winsize(fd, r, c):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", r, c, 0, 0))

# throwaway state: the operator's real first-run DB is not touched
env = dict(os.environ, SR_SOCK=T+"/api.sock", SR_DB=T+"/router.db",
           SR_MODULES="/usr/local/lib/saphira-router/modules")
# init MUST be given SR_DB too. Without it the binary defaults to
# /var/lib/saphira-router/router.db, which is 0750 to the service identity,
# so a test run under an ordinary account fails with "unable to open
# database file" and then every later step fails for the wrong reason.
r0 = subprocess.run(["ssh","-o","BatchMode=yes",HOST,
                     "rm -rf %s && mkdir -p %s && SR_SOCK=%s/api.sock SR_DB=%s/router.db "
                     "%s init --user admin --password '%s'"
                     % (T, T, T, T, BIN, PW)], capture_output=True, text=True, timeout=90)
check("throwaway state initialised", "tenant" in r0.stdout or r0.returncode == 0,
      repr((r0.stdout + r0.stderr)[:300]))
if subprocess.run(["ssh","-o","BatchMode=yes","-o","ConnectTimeout=8",HOST,"true"],
                  capture_output=True).returncode != 0:
    print("  SKIP %s is not reachable over ssh" % HOST)
    sys.exit(0)

# Started via a SCRIPT FILE using setsid with all fds redirected. Passed
# inline, the && and & precedence leaves the ssh channel open and the call
# times out with the daemon already running; without setsid the daemon either
# dies with the client or outlives it as an orphan holding a database, a
# socket and a module registry.
with open("/tmp/sr-ssh-resize-start.sh", "w") as f:
    f.write("#!/bin/sh\n"
            "cd %s || exit 1\n"
            "setsid sh -c 'exec env SR_SOCK=%s/api.sock SR_DB=%s/router.db "
            "SR_MODULES=%s %s daemon' </dev/null >%s/daemon.log 2>&1 &\n"
            "echo $! >%s/daemon.pid\n" % (T, T, T, env["SR_MODULES"], BIN, T, T))
subprocess.run(["scp","-q","-o","BatchMode=yes","/tmp/sr-ssh-resize-start.sh",
                "%s:/tmp/sr-ssh-resize-start.sh" % HOST], capture_output=True, timeout=60)
d = subprocess.run(["ssh","-o","BatchMode=yes",HOST,"sh /tmp/sr-ssh-resize-start.sh"],
                   capture_output=True, timeout=120)
for _ in range(80):
    if subprocess.run(["ssh","-o","BatchMode=yes",HOST,
                       "test -S %s/api.sock" % T], capture_output=True).returncode == 0:
        break
    time.sleep(0.2)
r = subprocess.run(["ssh","-o","BatchMode=yes",HOST,
                    "SR_SOCK=%s/api.sock SR_DB=%s/router.db %s login --user admin --password '%s' >/dev/null 2>&1; cat ~/.saphira-router/token"
                    % (T, T, BIN, PW)], capture_output=True, text=True, timeout=90)
# Mint a token against THIS daemon and keep it here rather than trusting the
# shared ~/.saphira-router/token file, which the live service and every other
# test also write: whoever logged in last owns it, and a token minted for a
# different daemon authenticates against nothing. That returns {"ok":false,...}
# with no data, which renders as a blank table and looks like a product fault.
_t = [l for l in r.stdout.strip().splitlines() if l.strip()]
tok = _t[-1] if _t else ""
check("obtained a session token over ssh", bool(tok) and len(tok) >= 32, repr(r.stdout[:200]))

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm"
    os.execvp("ssh", ["ssh","-tt","-o","BatchMode=yes",HOST,
                      "SR_SOCK=%s/api.sock SR_DB=%s/router.db SR_MODULES=%s SR_TOKEN=%s %s tui"
                      % (T, T, env["SR_MODULES"], tok, BIN)])
winsize(fd, 40, 120)
scr = Screen(120, 40); stm = Stream(scr)
def pump(sec):
    u = time.time() + sec
    while time.time() < u:
        rr,_,_ = select.select([fd],[],[],0.1)
        if fd in rr:
            try: d2 = os.read(fd, 65536)
            except OSError: return
            if not d2: return
            stm.feed(d2.decode("utf-8","replace"))
def screen(): return "\n".join(scr.display)
TOT = [0]
def rawcount(): return TOT[0]

def wait_for(needle, limit=30.0):
    """Wait for the interface to actually be ready.

    A fixed sleep is wrong over ssh: the remote process has to be exec'd,
    dynamically linked and ncurses-initialised across two hops, and the
    screen legitimately stays blank until then. An assertion that fires
    before readiness measures the network, not the interface.
    """
    u = time.time() + limit
    while time.time() < u:
        pump(0.5)
        if needle in screen():
            return True
    return False

try:
    ready = wait_for("hotkeys")
    check("TUI reaches the menu across an ssh channel", ready,
          repr(screen()[-300:]))
    for r_, c_ in ((50,160),(24,80)):
        before = TOT[0]
        winsize(fd, r_, c_); scr.resize(r_, c_); wait_for("hotkeys", 15)
        check("ssh resize to %dx%d keeps the interface" % (r_, c_), "hotkeys" in screen(),
              "grid=%dx%d bytes_after_resize=%d" % (scr.columns, scr.lines, TOT[0]-before))
    winsize(fd, 8, 40); scr.resize(8, 40); wait_for("too small", 15) or wait_for("needs at least", 5)
    check("ssh resize to 8x40 reports too small rather than scribbling",
          "too small" in screen() or "needs at least" in screen(), repr(screen()[-300:]))
    winsize(fd, 40, 120); scr.resize(40, 120); wait_for("hotkeys", 15)
    check("ssh resize back to 40x120 recovers", "hotkeys" in screen(),
          repr(screen()[-300:]))
    os.write(fd, b"m"); wait_for("fixture", 20)
    check("a screen opens and renders over ssh", "fixture" in screen(), repr(screen()[-400:]))
    winsize(fd, 20, 70); scr.resize(20, 70); wait_for("fixture", 15) or wait_for("too small", 5)
    check("resizing while a screen is open does not freeze it over ssh",
          "fixture" in screen() or "too small" in screen(), repr(screen()[-400:]))
    alive = os.waitpid(pid, os.WNOHANG) == (0,0)
    check("the ssh TUI process is still alive after all resizes", alive)
finally:
    try: os.write(fd, b"q"); pump(1.5)
    except OSError: pass
    for _ in range(20):
        w,_ = os.waitpid(pid, os.WNOHANG)
        if w == pid: break
        pump(0.2)
    else:
        os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
    # Kill the REMOTE daemon by its recorded pid. pkill -f cannot find it --
    # the command line is just "saphira-router daemon" and the SR_DB that
    # identifies it lives in the environment -- and terminating the local ssh
    # client leaves it running, holding a database, a socket and a registry.
    if d is not None:
        try: d.terminate()
        except Exception: pass
    subprocess.run(["ssh","-o","BatchMode=yes",HOST,
                    "if [ -f %s/daemon.pid ]; then kill -9 $(cat %s/daemon.pid) 2>/dev/null; fi" % (T, T)],
                   capture_output=True, timeout=60)
print("  %s" % ("SSH RESIZE PASS" if not fails else "SSH RESIZE FAIL (%d)" % fails))
sys.exit(1 if fails else 0)
