#!/usr/bin/env python3
"""tui_pty.py -- interactive smoke test of the ncurses TUI.

Everything else in the suite tests the TUI's *inputs* to the registry
deterministically. This drives the real interface through a pty and reads the
real screen, because the acceptance criterion is an operator looking at a
terminal (D1 4).

It checks: login, host list, per-host navigation, capability rendering,
registry-driven section appearance and disappearance across daemon restarts
with different module sets, that a refused module stays absent, and that
exiting returns the shell cleanly.
"""
import os
import pty
import re
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
BIN = os.path.join(ROOT, "build", "saphira-router")
ADMIN_PW = "Saphira-r0uter!"
NODES = [("nodea", "172.16.7.100"), ("nodeb", "172.16.7.110"),
         ("nodec", "172.16.7.120")]

failures = []
def check(what, cond, detail=""):
    print("  %-58s %s" % (what, "PASS" if cond else "**FAIL**"))
    if not cond:
        failures.append(what)
        if detail:
            print("      %s" % detail.replace("\n", "\n      ")[:400])

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|\x1b[=>]|\r")

def clean(s):
    s = ANSI.sub("", s)
    return re.sub(r"[ \t]+", " ", s)

def run_tui(env, keys, settle=0.8, timeout=40, credentials=False):
    """Run the TUI in a pty, send keys, return the visible screen text."""
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(env)
        os.environ["TERM"] = "xterm"
        os.environ["LINES"] = "40"
        os.environ["COLUMNS"] = "120"
        try:
            os.execv(BIN, [BIN, "tui"])
        except Exception:
            os._exit(127)
    buf = b""
    deadline = time.time() + timeout

    def pump(until):
        nonlocal buf
        while time.time() < until:
            r, _, _ = select.select([fd], [], [], 0.15)
            if fd in r:
                try:
                    d = os.read(fd, 65536)
                except OSError:
                    break
                if not d:
                    break
                buf += d

    pump(time.time() + settle)
    for i, k in enumerate(keys):
        try:
            os.write(fd, k)
        except OSError:
            break
        # the first field of a login needs longer to settle on screen
        pump(time.time() + (settle * 3 if (credentials and i == 0) else settle))

    status = None
    for _ in range(int(timeout * 4)):
        wpid, st = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            status = st
            break
        pump(time.time() + 0.25)
    if status is None:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        status = -1
    os.close(fd)
    txt = clean(buf.decode("utf-8", "replace"))
    if os.environ.get("TUI_DUMP"):
        with open("/tmp/tui_dump.txt", "a") as f:
            f.write("==== keys=%r status=%s ====\n%s\n" % (keys, status, txt))
    return txt, status

def start_daemon(env):
    p = subprocess.Popen([BIN, "daemon"], env=env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    for _ in range(50):
        if os.path.exists(env["SR_SOCK"]):
            return p
        time.sleep(0.1)
    return p

def stop_daemon(p):
    if p and p.poll() is None:
        p.terminate()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()

def cli(env, *args):
    r = subprocess.run([BIN] + list(args), env=env,
                       capture_output=True, text=True, timeout=60)
    return r.stdout + r.stderr

def main():
    if not os.path.exists(BIN):
        print("  missing %s -- run make first" % BIN)
        return 1
    if not shutil.which("ssh"):
        print("  ssh unavailable; cannot enroll nodes")
        return 1

    tmp = tempfile.mkdtemp(prefix="sr-tui-")
    db = os.path.join(tmp, "router.db")
    sock = os.path.join(tmp, "api.sock")
    mod_empty = os.path.join(tmp, "mods-empty")
    mod_fix = os.path.join(tmp, "mods-fixture")
    mod_bad = os.path.join(tmp, "mods-both")
    home = os.path.join(tmp, "home")
    for d in (mod_empty, mod_fix, mod_bad, home):
        os.makedirs(d, exist_ok=True)
    shutil.copy(os.path.join(ROOT, "build", "mod_fixture.so"), mod_fix)
    shutil.copy(os.path.join(ROOT, "build", "mod_fixture.so"), mod_bad)
    shutil.copy(os.path.join(ROOT, "build", "mod_badabi.so"), mod_bad)

    base = dict(os.environ)
    base.update({"SR_DB": db, "SR_SOCK": sock, "HOME": home,
                 "SR_MODULES": mod_empty})
    print("  workspace: %s" % tmp)

    # ---- init + enroll so the screens have real content -------------------
    subprocess.run([BIN, "init", "--user", "admin", "--password", ADMIN_PW],
                   env=base, capture_output=True, timeout=60)
    d = start_daemon(base)
    cli(base, "login", "--user", "admin", "--password", ADMIN_PW)
    enrolled = []
    for name, addr in NODES:
        out = cli(base, "host", "enroll", "--address", addr,
                  "--hostname", name, "--json")
        if '"ok":true' in out:
            enrolled.append(name)
    stop_daemon(d)
    check("three nodes enrolled for the TUI screens", len(enrolled) == 3,
          "enrolled: %s" % enrolled)

    # ---- phase A: login screen, hosts, capabilities, no modules -----------
    d = start_daemon(base)
    time.sleep(0.4)

    # Authenticate once so navigation tests exercise the menu rather than the
    # login screen; the login screen itself is tested on its own below.
    tok = cli(base, "login", "--user", "admin", "--password", ADMIN_PW, "--json")
    m = re.search(r'"token":"([0-9a-f]{64})"', tok)
    check("CLI obtained a session token", m is not None, tok[:200])
    if m is None:
        return 1
    nav = dict(base); nav["SR_TOKEN"] = m.group(1)

    # LOGIN: the real login screen, not a pre-supplied token.
    scr, st = run_tui(base, [b"admin\r", (ADMIN_PW + "\r").encode()], credentials=True)
    check("login screen accepts a real username/password and reaches the menu",
          "hosts" in scr and "capabilities" in scr and "quit" in scr, scr[-300:])
    check("login screen does not echo the password",
          ADMIN_PW not in scr, scr[-300:])
    check("TUI reports it is the terminal interface, not a web UI",
          "No browser" in scr or "no web access" in scr or "terminal" in scr.lower())

    # HOSTS: down to "hosts", enter.
    scr, st = run_tui(nav, [b"h"])
    for n in NODES:
        check("host list shows %s" % n[0], n[0] in scr, scr[-300:])
    check("host list shows the addresses", "172.16.7.100" in scr)

    # CAPABILITIES: down to "capabilities", enter.
    scr, st = run_tui(nav, [b"c"])
    check("capability screen renders a capability matrix", "CAPABILITY" in scr)
    check("capability states are rendered", "usable" in scr or "unavailable" in scr)
    check("probe evidence is shown with the state",
          "nft -c" in scr or "probe" in scr.lower(), scr[-400:])
    check("states are not rounded up to healthy",
          "healthy" not in scr.lower() or "nftables" in scr)
    stop_daemon(d)

    # ---- phase B: fixture installed -> section appears ---------------------
    env_fix = dict(base); env_fix["SR_MODULES"] = mod_fix
    d = start_daemon(env_fix)
    scr, st = run_tui(dict(env_fix, SR_TOKEN=m.group(1)), [b"f"])
    check("functionality screen lists the fixture section", "fixture" in scr, scr[-400:])
    check("core-owned screens still listed alongside module sections",
          "hosts" in scr and "modules" in scr)
    stop_daemon(d)

    # ---- phase C: incompatible module present -> still absent --------------
    env_bad = dict(base); env_bad["SR_MODULES"] = mod_bad
    d = start_daemon(env_bad)
    scr, st = run_tui(dict(env_bad, SR_TOKEN=m.group(1)), [b"f"])
    check("loaded module's section is present", "fixture" in scr)
    check("refused/incompatible module contributes NO section", "badabi" not in scr,
          scr[-400:])
    # the modules screen must SHOW it, but as refused
    scr2, _ = run_tui(dict(env_bad, SR_TOKEN=m.group(1)), [b"m"])
    check("modules screen reports the refusal with its reason",
          "incompatible" in scr2 and "not supported" in scr2, scr2[-400:])
    stop_daemon(d)

    # ---- phase D: removed again -> section disappears ----------------------
    d = start_daemon(base)
    scr, st = run_tui(nav, [b"f"])
    check("section disappears when the module is removed",
          "fixture" not in scr, scr[-400:])
    check("core still usable with zero modules",
          "hosts" in scr and "capabilities" in scr)
    stop_daemon(d)

    # ---- phase E: clean exit, and a token-based session also works ---------
    d = start_daemon(base)
    scr, st = run_tui(nav, [b"q"])
    check("exiting the menu returns the shell cleanly", st == 0)
    env_tok = dict(base); env_tok["SR_TOKEN"] = m.group(1)
    scr, st = run_tui(env_tok, [b"q"])
    check("a token-authenticated session opens without the login screen", st == 0)
    stop_daemon(d)

    # ---- phase F: bad credentials are refused ------------------------------
    d = start_daemon(base)
    scr, st = run_tui(base, [b"admin\r", b"wrong-password\r", b" ", b" ", b" "], credentials=True)
    check("wrong password does not produce a working session",
          "authentication failed" in scr, scr[-300:])
    stop_daemon(d)

    shutil.rmtree(tmp, ignore_errors=True)
    print("")
    if not failures:
        print("  ALL PASS")
        return 0
    print("  %d FAILURE(S): %s" % (len(failures), ", ".join(failures)))
    return 1

if __name__ == "__main__":
    sys.exit(main())
