#!/usr/bin/env python3
"""tui_negative.py -- the operator-facing negative path, with Bambi live.

mod_badabi.so declares ABI 100 against a core that implements ABI 1. It is
the standing negative fixture: the loader must refuse it, and that refusal
must be legible to the person who has to act on it, not merely present in a
log nobody reads.

Proven here, from the operator's seat, over ssh:
  1. Bambi is discovered, not ignored
  2. the refusal is safe -- never loaded, reason recorded
  3. the refusal is VISIBLE in the TUI with a reason an operator can act on
  4. it cannot present itself as available/usable/healthy
  5. the failure does not disturb the valid module beside it
  6. resize and repaint stay clean WHILE the failure is on screen
  7. the audit trail records the reason, in the detail column

The screens are rendered with term.py, which adds REP to pyte. Without it
the model invents corruption ncurses never sends -- a convincing fake defect
that sent this work hunting a bug in the wrong file.

Bambi's LIVE DUTY IS OVER, and mod_badabi.so is no longer in any production
module directory -- the r9 package never shipped it and never compiled it. So
this test no longer depends on the host having it. It provisions its own
scratch module directory from the build fixtures and points a throwaway
daemon at that. That is what makes the negative path permanently testable:
it is a property of the test, not of a machine somebody remembered to
contaminate. Point SR_SSH_TEST_MODS at a directory to reuse one instead.
"""
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import fcntl
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from term import Screen, Stream
except ImportError:
    try:
        import pyte
        Screen, Stream = pyte.Screen, pyte.Stream
        print("  NOTE term.py absent -- rendering will not model REP, so a")
        print("       clean result here is weaker than it looks")
    except ImportError:
        print("  SKIP no terminal model available")
        sys.exit(0)

HOST = os.environ.get("SR_SSH_TEST_HOST", "hatchling")
BIN  = os.environ.get("SR_SSH_TEST_BIN", "/usr/local/bin/saphira-router")
T    = "/tmp/bambi-acc"
PW   = "Bambi-acc-t3st!"
# The PRODUCTION module directory. Deliberately not this test's subject: it is
# asserted to be clean, and the negative path runs against a scratch dir.
PROD_MODS = "/usr/local/lib/saphira-router/modules"
SCRATCH   = "/tmp/sr-negative-moddir"
MODS      = os.environ.get("SR_SSH_TEST_MODS", SCRATCH)

FAILS = 0
def check(what, cond, detail=""):
    global FAILS
    print(("  ok   " if cond else "  FAIL ") + what + ("" if cond else "\n         " + str(detail)[:400]))
    if not cond: FAILS += 1

def ssh(cmd, timeout=90):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", HOST, cmd],
                          capture_output=True, text=True, timeout=timeout)

def q(sql):
    """Query this test's own throwaway state, never production."""
    return ssh("sudo -u smalley sqlite3 %s/router.db \"%s\"" % (T, sql)).stdout.strip()

def winsize(fd, r, c):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", r, c, 0, 0))

TOK = ""   # this test's own token, minted against its own daemon

class Tui:
    def __init__(self, rows=40, cols=120):
        t = TOK
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ["TERM"] = "xterm"
            os.execvp("ssh", ["ssh", "-tt", "-o", "BatchMode=yes", HOST,
                "SR_SOCK=%s/api.sock SR_DB=%s/router.db SR_MODULES=%s SR_TOKEN=%s %s tui"
                % (T, T, SCRATCH, t, BIN)])
        winsize(self.fd, rows, cols)
        self.scr = Screen(cols, rows)
        self.stm = Stream(self.scr)
        self.rows, self.cols = rows, cols
    def settle(self, secs):
        u = time.time() + secs
        while time.time() < u:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if self.fd in r:
                try: d = os.read(self.fd, 65536)
                except OSError: return
                if not d: return
                self.stm.feed(d.decode("utf-8", "replace"))
    def wait(self, needle, limit=30):
        u = time.time() + limit
        while time.time() < u:
            self.settle(0.4)
            if needle in "\n".join(self.scr.display): return True
        return False
    def send(self, k, s=1.2): os.write(self.fd, k); self.settle(s)
    def resize(self, r, c, limit=12):
        winsize(self.fd, r, c); self.scr.resize(r, c)
        u = time.time() + limit
        while time.time() < u:
            self.settle(0.4)
            if self.wait_now(): return
    def wait_now(self):
        return bool(self.nonblank())
    def text(self): return "\n".join(self.scr.display)
    def nonblank(self): return [l.rstrip() for l in self.scr.display if l.strip()]
    def close(self):
        try: os.write(self.fd, b"q"); self.settle(1.0)
        except OSError: pass
        try:
            w, _ = os.waitpid(self.pid, os.WNOHANG)
            if w != self.pid: os.kill(self.pid, signal.SIGKILL); os.waitpid(self.pid, 0)
        except ChildProcessError: pass
        try: os.close(self.fd)
        except OSError: pass

DAEMON = None

def provision():
    """Own the whole test environment: fixtures, state, and daemon.

    The daemon reads SR_MODULES once, at startup. So a daemon left running
    from an earlier run keeps whatever module directory it was started with,
    and asking the TUI for a different one changes nothing. This test used to
    lean on whatever daemon happened to be on the host, which passed only
    while production still carried Bambi and failed the moment it did not --
    a test whose result depends on ambient machine state is not a test.

    So: build a fresh state, and start a daemon that certainly points at the
    scratch module directory this test owns.
    """
    global DAEMON, TOK
    here = os.path.dirname(os.path.abspath(__file__))
    up = os.path.join(here, "..", "build")
    need = ["mod_fixture.so", "mod_badabi.so"]
    for f in need:
        p = os.path.join(up, f)
        if not os.path.exists(p):
            return "missing build fixture %s (run make)" % p
    # remove both, then create BOTH: the state dir is where sqlite will create
    # its file, so omitting it fails with "unable to open database file".
    ssh("rm -rf %s %s && mkdir -p %s %s" % (SCRATCH, T, SCRATCH, T))
    for f in need:
        r = subprocess.run(["scp", "-o", "BatchMode=yes", os.path.join(up, f),
                            "%s:%s/" % (HOST, SCRATCH)], capture_output=True, text=True)
        if r.returncode != 0:
            return "scp %s failed: %s" % (f, r.stderr[-200:])

    r = ssh("SR_SOCK=%s/api.sock SR_DB=%s/router.db %s init --user admin --password '%s' >/dev/null 2>&1"
            % (T, T, BIN, PW))
    if r.returncode != 0:
        return "init failed: %s" % (r.stderr[-200:])

    # Start the daemon bound to the SCRATCH module dir, not the production one.
    # Started on the far side and its real pid recorded, because pkill -f
    # cannot identify it: the daemon's command line is just
    # "saphira-router daemon" and the SR_DB that marks it belongs to this test
    # lives in its ENVIRONMENT, which pkill does not inspect. Matching on a
    # pattern that never appears in argv is how seven orphans accumulated.
    # Written as a SCRIPT FILE and invoked, rather than inlined into the ssh
    # command. Inline, the && and & precedence changes what is backgrounded,
    # the ssh channel stays open, and the call times out at 90s with the
    # daemon already running -- which reads as a hang and leaves an orphan
    # every time. As a script, setsid + exec with all fds redirected returns
    # in about a second and the recorded pid is the daemon itself.
    start = (
        "#!/bin/sh\n"
        "cd %s || exit 1\n"
        "setsid sh -c 'exec env SR_SOCK=%s/api.sock SR_DB=%s/router.db "
        "SR_MODULES=%s %s daemon' </dev/null >%s/daemon.log 2>&1 &\n"
        "echo $! >%s/daemon.pid\n"
    ) % (T, T, T, SCRATCH, BIN, T, T)
    local = "/tmp/sr-negative-start.sh"
    with open(local, "w") as f:
        f.write(start)
    subprocess.run(["scp", "-q", "-o", "BatchMode=yes", local,
                    "%s:/tmp/sr-negative-start.sh" % HOST],
                   capture_output=True, timeout=60)
    r = ssh("sh /tmp/sr-negative-start.sh")
    if r.returncode != 0:
        return "could not start the daemon: %s" % r.stderr[-200:]
    for _ in range(80):
        if ssh("test -S %s/api.sock" % T, 30).returncode == 0:
            break
        time.sleep(0.25)
    if ssh("test -S %s/api.sock" % T, 30).returncode != 0:
        return "daemon did not create its socket"

    # Mint a token with THAT daemon, and keep it HERE rather than reading the
    # shared ~/.saphira-router/token file. Several tests and the live service
    # all write that one path, so whoever logged in last wins it; a stale token
    # from another daemon authenticates against nothing and comes back as
    # {"ok":false,...} with no "modules" key, which renders as a blank table
    # and looks like a product bug rather than a test artefact.
    r = ssh("SR_SOCK=%s/api.sock SR_DB=%s/router.db %s login --user admin --password '%s' >/dev/null 2>&1; "
            "cat ~/.saphira-router/token" % (T, T, BIN, PW))
    toks = [l for l in r.stdout.strip().splitlines() if l.strip()]
    if not toks:
        return "could not mint a session token: %s" % r.stderr[-200:]
    TOK = toks[-1]
    return None

def teardown():
    """Kill the REMOTE daemon, not just the local ssh client.

    Terminating the ssh client leaves the daemon running on the far side: ssh
    is not the process being tested, and a remote child outlives its client.
    Seven orphans were accumulating on the test host before this was fixed --
    every one of them holding a database, a socket, and a module registry.

    Matched on this test's own state path, which is unique to it, so nothing
    belonging to anyone else can be caught by it.
    """
    if DAEMON is not None:
        try: DAEMON.terminate()
        except Exception: pass
        try: DAEMON.wait(timeout=5)
        except Exception:
            try: DAEMON.kill()
            except Exception: pass
    # The daemon is remote, so it outlives this ssh client. Kill it by the pid
    # recorded at start, matched on this test's own unique state path.
    #
    # The state directory is deliberately LEFT IN PLACE: the audit assertions
    # that follow read it, and deleting it here removed the evidence the test
    # had just produced. The next run's provision() removes it first, so
    # nothing accumulates either way.
    ssh("if [ -f %s/daemon.pid ]; then kill -9 $(cat %s/daemon.pid) 2>/dev/null; fi" % (T, T))

def main():
    if ssh("true", 20).returncode != 0:
        print("  SKIP %s unreachable" % HOST); return 0

    # Production must be clean. This is asserted FIRST: the negative fixture
    # belongs in tests, and a production module directory carrying a module
    # that exists only to be refused is a packaging defect.
    prod = ssh("ls -1 %s 2>/dev/null" % PROD_MODS).stdout.split()
    check("the PRODUCTION module directory carries no broken fixture",
          "mod_badabi.so" not in prod, prod)

    err = provision()
    if err:
        check("negative fixtures provisioned on the test host", False, err)
        return 1
    check("both fixtures provisioned in a scratch module dir", True)
    mods = ssh("ls -1 %s" % MODS).stdout.split()
    check("the scratch dir has Bambi and a valid module",
          "mod_badabi.so" in mods and "mod_fixture.so" in mods, mods)
    # the daemon must be serving THIS scratch dir, not an inherited one
    check("the daemon serves the scratch module dir",
          q("select count(*) from module_registry;") == "2",
          q("select module_name,state from module_registry;"))

    t = Tui()
    try:
        check("TUI reaches the menu with Bambi present", t.wait("hotkeys"),
              "\n".join(t.nonblank())[-300:])

        # ---- 3. the refusal is visible, in the TUI, with a usable reason ----
        t.send(b"m")
        check("modules screen opens", t.wait("MODULE"), "\n".join(t.nonblank())[-300:])
        txt = t.text()
        check("3. Bambi is listed as discovered", "badabi" in txt)
        check("3. its state is shown as a refusal, not a success",
              "incompatible" in txt or "refused" in txt,
              [l for l in t.nonblank() if "badabi" in l])
        check("3. the reason is on screen, naming the ABI",
              "ABI" in txt and "100" in txt,
              [l for l in t.nonblank() if "badabi" in l])

        # ---- 5. the valid module is unaffected, visibly ----
        check("5. the valid module is still loaded beside it",
              "fixture" in txt and "loaded" in txt,
              [l for l in t.nonblank() if "fixture" in l])

        # ---- 4. no operator-facing claim of health ----
        banned = [w for w in ("available", "usable", "healthy")
                  if re.search(r"\b%s\b" % w, txt, re.I)]
        check("4. the TUI never calls Bambi available/usable/healthy",
              not banned, banned)

        # ---- 6. resize and repaint stay clean WHILE the failure is shown ----
        for rows, cols, label in ((50, 160, "50x160"), (24, 80, "24x80"),
                                  (40, 120, "40x120")):
            t.resize(rows, cols)
            tt = t.text()
            check("6. resize to %s keeps the refusal legible" % label,
                  "badabi" in tt and ("incompatible" in tt or "refused" in tt),
                  "\n".join(t.nonblank())[-300:])
        # and an undersized window is honest rather than scribbled over it
        t.resize(8, 40)
        check("6. an undersized window says so instead of mangling the refusal",
              "too small" in t.text() or "needs at least" in t.text(),
              "\n".join(t.nonblank())[-200:])
        t.resize(40, 120)
        check("6. the refusal returns intact after resizing back",
              t.wait("badabi") and "incompatible" in t.text(),
              "\n".join(t.nonblank())[-300:])
    finally:
        t.close()
        teardown()

    # ---- 2 and 4 at the state level, which no display can overrule ----
    check("2. Bambi was never loaded",
          q("select count(*) from module_registry where module_name='badabi' and state='loaded';") == "0")
    # The CHECK lives in the CREATE TABLE text; pragma table_info does not
    # carry it, so asking pragma proves nothing either way.
    ddl = q("select sql from sqlite_master where type='table' and name='module_registry';")
    check("4. the module state vocabulary cannot express health",
          "CHECK(state IN" in ddl and
          all(w in ddl for w in ("'loaded'", "'incompatible'")) and
          not any(w in ddl for w in ("'healthy'", "'usable'", "'available'")),
          ddl[:200])
    check("4. recording Bambi as healthy is refused by the schema itself",
          "CHECK constraint failed" in ssh(
              "sudo -u smalley sqlite3 %s/router.db \"update module_registry "
              "set state='healthy' where module_name='badabi';\"" % T).stderr)
    check("5. the valid module is loaded and still providing",
          q("select state from module_registry where module_name='fixture';") == "loaded")

    # ---- 7. the audit records the reason, in the right column ----
    detail = q("select detail from audit_event where action='module.refuse' "
               "and object_id='badabi' order by rowid desc limit 1;")
    src = q("select coalesce(source_addr,'') from audit_event where action='module.refuse' "
            "and object_id='badabi' order by rowid desc limit 1;")
    check("7. the refusal is audited as denied",
          q("select outcome from audit_event where action='module.refuse' "
            "and object_id='badabi' order by rowid desc limit 1;") == "denied")
    check("7. the audit detail carries the reason", "ABI" in detail, detail)
    check("7. the reason is not misfiled into source_addr", src == "", repr(src))
    check("7. no audit row anywhere uses source_addr for prose",
          q("select count(*) from audit_event where source_addr like '% %';") == "0")

    print("  %s" % ("NEGATIVE PATH PASS" if not FAILS else "NEGATIVE PATH FAIL (%d)" % FAILS))
    return 1 if FAILS else 0

if __name__ == "__main__":
    sys.exit(main())
