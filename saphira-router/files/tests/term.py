#!/usr/bin/env python3
"""term.py -- a terminal model that matches what ncurses actually assumes.

pyte is missing REP (``CSI Ps b``, repeat the last printed character Ps
times). ncurses emits it constantly, because real terminfo advertises
``rep=%p1%c\\E[%p2%{1}%-%db`` and using it collapses runs of blanks into a
few bytes. Both egg and hatchling advertise rep for xterm-256color.

Without REP the model silently drops those runs, so a header padded with
%-14s renders compressed, text appears to collide with what was on the
screen before it, and the screen looks corrupted.

That is not a small inaccuracy here. It manufactured a convincing fake
defect -- a modules table that looked like it was bleeding the previous
screen's text into its column headings -- and the corruption was present
in the ORIGINAL src/tui.c exactly as much as in the fixed one, which is
what finally gave it away. A harness that renders differently from the
operator's terminal is worse than no harness: it sends you hunting a bug
in the wrong place.

So: keep pyte, and teach it REP. Any assertion about what the operator
sees is only as trustworthy as this model.
"""
import pyte

__all__ = ["Screen", "Stream", "feed_all", "HAVE_PYTE"]

try:
    import pyte as _pyte
    HAVE_PYTE = True
except ImportError:  # pragma: no cover - handled by callers
    HAVE_PYTE = False
    raise


class Screen(_pyte.Screen):
    """A pyte Screen that remembers its last printed character."""

    last_char = " "

    def draw(self, data):
        if data:
            self.last_char = data[-1]
        return super().draw(data)

    def repeat_char(self, count=1):
        """REP: print the last printed character ``count`` times.

        A terminal with no pending character treats REP as printing spaces,
        which is what ``blank`` starts as.
        """
        try:
            n = int(count)
        except (TypeError, ValueError):
            return
        if n <= 0:
            return
        # Bound it: a hostile or corrupt stream must not ask for a gigabyte.
        n = min(n, 8192)
        ch = self.last_char or " "
        self.draw(ch * n)


class Stream(_pyte.Stream):
    """A pyte Stream that dispatches CSI b to Screen.repeat_char.

    ``csi`` is read once at construction to build the dispatcher, so
    overriding the class attribute is enough. It is copied rather than
    mutated so pyte's own table is left alone.
    """

    csi = dict(_pyte.Stream.csi, **{"b": "repeat_char"})


def feed_all(screen, data):
    """Feed bytes to a Stream, tolerating a partial UTF-8 sequence."""
    stream = Stream(screen)
    stream.feed(data)
    return screen
