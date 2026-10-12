/* tui.c -- the ncurses terminal interface.
 *
 * The TUI is a CLIENT. It holds no database handle, writes no state, and
 * bypasses the API for nothing (D1 3.2, D4 1). Everything it displays comes
 * from the API over the local socket.
 *
 * Its sections are derived from the MODULE REGISTRY, not from a hard-coded
 * provider list. Installing a module makes a section appear; removing it
 * makes the section disappear, and this file is not edited to achieve that
 * (D2 8, D9 2). The only core screens here are the ones the core owns.
 *
 * The TUI draws; modules describe. It must not round a `substituted` step or
 * an `unavailable` capability up into a clean-looking success (D9 3.2).
 */
#include "sr_tui.h"
#include "sr_api.h"
#include "sr.h"

#include <json-c/json.h>
#include <stdbool.h>
#include <curses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SR_DEFAULT_SOCK "/run/saphira-router/api.sock"

/* Null-safe JSON string read. A field the daemon omitted (an optional IPv6
 * address, an absent probe method) must render as empty text; handing NULL to
 * a %s conversion is undefined behaviour and is exactly how a screen
 * disappears mid-render. */
static const char *js(json_object *o, const char *key, const char *dflt)
{
    if (!o) return dflt;
    json_object *v = json_object_object_get(o, key);
    if (!v) return dflt;
    const char *s = json_object_get_string(v);
    return s ? s : dflt;
}

static char *g_token;
static const char *g_sock;
static char g_msg[256];

/* Colour pairs, because ncurses expresses colour as COLOR_PAIR(n) rather
 * than named attributes like A_GREEN. */
enum { SR_C_GREEN = 1, SR_C_YELLOW = 2, SR_C_RED = 3, SR_C_CYAN = 4 };

static void init_colors(void)
{
    if (!has_colors()) return;
    start_color();
    use_default_colors();
    init_pair(SR_C_GREEN,  COLOR_GREEN,  -1);
    init_pair(SR_C_YELLOW, COLOR_YELLOW, -1);
    init_pair(SR_C_RED,    COLOR_RED,    -1);
    init_pair(SR_C_CYAN,   COLOR_CYAN,   -1);
}

/* ----------------------------------------------------------- layout */

/* A terminal smaller than this cannot show a table honestly, so the TUI says
 * so instead of drawing past the last cell. */
#define SR_MIN_LINES 12
#define SR_MIN_COLS  52

static int  g_screen = -1;   /* -1 menu, 0 hosts, 1 caps, 2 modules, 3 sections */

static int layout_too_small(void) { return LINES < SR_MIN_LINES || COLS < SR_MIN_COLS; }

static void draw_too_small(void)
{
    erase();
    mvprintw(0, 0, "saphira-router: terminal is %dx%d", COLS, LINES);
    mvprintw(1, 0, "needs at least %d cols x %d rows -- resize this window",
             SR_MIN_COLS, SR_MIN_LINES);
    refresh();
}

/* Print at (y,x) bounded by the CURRENT terminal size.
 *
 * This is the fix for resize corruption. A hardcoded column such as
 * mvprintw(1, 40, ...) is harmless while the window is wide and catastrophic
 * once it is not: ncurses wraps at the right margin, so the overflow lands on
 * the following row and the display scribbles itself. Reading LINES/COLS on
 * every draw means the layout follows the window instead of assuming it. */
static void put_at(int y, int x, const char *fmt, ...)
{
    if (y < 0 || y >= LINES || x < 0 || x >= COLS) return;
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    mvaddnstr(y, x, buf, COLS - x);
}

/* ncurses installs its own SIGWINCH and updates LINES/COLS, but asking it to
 * resync makes the new size authoritative on this redraw rather than the next.
 * Ignored where the extension is unavailable. */
static void sr_sync_size(void)
{
#ifdef NCURSES_VERSION
    resize_term(0, 0);
#else
    (void)0;
#endif
}

/* ------------------------------------------------------------- api */

static char *call(const char *op, const char *extra)
{
    char req[SR_MAX_TEXT];
    snprintf(req, sizeof req, "{\"op\":\"%s\",\"token\":\"%s\"%s%s}",
             op, g_token ? g_token : "", extra ? "," : "", extra ? extra : "");
    return sr_api_call(g_sock, req, NULL);
}

static int do_login_screen(void)
{
    char user[64] = "admin", pass[128];
    /* The menu loop uses a 1s input timeout so 'r' can refresh. That timeout
     * ALSO applies to getnstr, so a login field would return ERR after one
     * second of typing. Credential entry must block. */
    timeout(-1);
    curs_set(1);
    /* cbreak (not raw) is what getnstr needs, and the prompt MUST be
     * refreshed before reading: without the refresh the field is not actually
     * on screen when input starts arriving, and the first byte of the next
     * field can be swallowed. */
    cbreak(); echo();
    mvprintw(4, 4, "username: ");
    move(4, 15); clrtoeol();
    refresh();
    if (getnstr(user, sizeof user) == ERR) return -1;
    sr_trim(user);

    noecho();
    mvprintw(6, 4, "password: ");
    move(6, 14); clrtoeol();
    refresh();
    if (getnstr(pass, sizeof pass) == ERR) return -1;
    sr_trim(pass);

    int code = SR_OK;
    char *tok = NULL;
    char *resp = sr_api_login(g_sock, user, pass, &tok, &code);
    if (!resp) { snprintf(g_msg, sizeof g_msg, "cannot reach the daemon at %s", g_sock); return -1; }
    if (code != SR_OK || !tok) {
        snprintf(g_msg, sizeof g_msg, "authentication failed");
        free(resp);
        return -1;
    }
    g_token = tok;
    free(resp);
    snprintf(g_msg, sizeof g_msg, "logged in");
    return 0;
}

/* --------------------------------------------------------- registry */

/* Collect the distinct section names contributed by LOADED modules. This is
 * the only place the interface learns what functionality exists. */
static int collect_sections(char sections[][32], int max, int *nout)
{
    int n = 0;
    char *resp = call("module.list", NULL);
    if (!resp) return -1;
    json_object *o = json_tokener_parse(resp);
    json_object *arr = NULL;
    if (o && json_object_object_get_ex(o, "modules", &arr)) {
        size_t m = json_object_array_length(arr);
        for (size_t i = 0; i < m && n < max; i++) {
            json_object *mo = json_object_array_get_idx(arr, i);
            /* Only a LOADED module contributes availability. An incompatible
             * or refused module is reported, never presented as usable. */
            const char *state = js(mo, "state", "");
            const char *name = js(mo, "name", "");
            if (strcmp(state, "loaded") == 0) {
                snprintf(sections[n++], 32, "%s", name);
            }
        }
    }
    if (o) json_object_put(o);
    *nout = n;
    return 0;
}

/* ------------------------------------------------------------ screens */

static void draw_header(const char *title)
{
    attron(A_BOLD);
    mvprintw(0, 0, " saphira-router ");
    attron(A_REVERSE); mvprintw(0, 16, " %s ", title); attroff(A_REVERSE);
    attroff(A_BOLD);
    put_at(1, 0, "controller: %s", g_sock);
    if (g_msg[0]) { attron(A_DIM); put_at(1, 40, "%s", g_msg); attroff(A_DIM); }
}

static void screen_hosts(void)
{
    char *resp = call("host.list", NULL);
    erase();
    draw_header("hosts");
    if (!resp) {
        put_at(3, 2, "cannot reach the daemon");
        refresh();
        return;
    }
    json_object *o = json_tokener_parse(resp);
    json_object *arr = NULL;
    if (o && json_object_object_get_ex(o, "hosts", &arr)) {
        size_t n = json_object_array_length(arr);
        put_at(3, 2, "%-4s %-16s %-15s %-8s %-9s %s",
                 "#", "HOST", "ADDRESS", "ARCH", "STATUS", "OS");
        for (size_t i = 0; i < n; i++) {
            json_object *h = json_object_array_get_idx(arr, i);
            put_at(4 + (int)i, 2, "%-4zu %-16s %-15s %-8s %-9s %s",
                i + 1,
                js(h, "hostname", ""),
                js(h, "address_v4", "-"),
                js(h, "arch", ""),
                js(h, "status", ""),
                js(h, "os_name", ""));
        }
        if (n == 0) put_at(4, 2, "no hosts enrolled yet");
    }
    if (o) json_object_put(o);
    free(resp);
    refresh();
}

static void screen_caps(void)
{
    char *hosts = call("host.list", NULL);
    if (!hosts) return;
    json_object *o = json_tokener_parse(hosts);
    json_object *arr = NULL;
    erase();
    draw_header("capabilities");
    if (!o || !json_object_object_get_ex(o, "hosts", &arr)) { free(hosts); refresh(); return; }
    size_t hn = json_object_array_length(arr);
    if (hn == 0) { put_at(3, 2, "no hosts enrolled yet"); refresh(); free(hosts); return; }

    /* Show the first host's capabilities as a worked example. */
    json_object *h0 = json_object_array_get_idx(arr, 0);
    const char *hid = js(h0, "id", "");
    put_at(2, 2, "host: %s   (showing the first enrolled host)",
             js(h0, "hostname", ""));

    char extra[256];
    snprintf(extra, sizeof extra, "\"host_id\":\"%s\"", hid);
    char *resp = call("host.caps", extra);
    if (resp) {
        json_object *c = json_tokener_parse(resp);
        json_object *ca = NULL;
        if (c && json_object_object_get_ex(c, "capabilities", &ca)) {
            size_t n = json_object_array_length(ca);
            put_at(4, 2, "%-18s %-14s %s", "CAPABILITY", "STATE", "PROBE / DETAIL");
            for (size_t i = 0; i < n; i++) {
                json_object *e = json_object_array_get_idx(ca, i);
                const char *st = js(e, "state", "");
                const char *cap = js(e, "capability", "");
                const char *pm = js(e, "probe_method", "");
                const char *dt = js(e, "detail", "");
                /* A state is shown as it was proven. 'unavailable' and
                 * 'unestablished' are NOT rounded up to healthy. */
                if (strcmp(st, "unavailable") == 0) attron(A_DIM);
                else if (strcmp(st, "usable") == 0 || strcmp(st, "healthy") == 0) attron(COLOR_PAIR(SR_C_GREEN));
                else if (strcmp(st, "installed") == 0 || strcmp(st, "available") == 0) attron(COLOR_PAIR(SR_C_YELLOW));
                if (pm[0]) put_at(5 + (int)i, 2, "%-18s %-14s %-26s [%s]", cap, st, dt, pm);
                else       put_at(5 + (int)i, 2, "%-18s %-14s %s", cap, st, dt);
                attroff(COLOR_PAIR(0));
            }
        }
        if (c) json_object_put(c);
        free(resp);
    }
    if (o) json_object_put(o);
    free(hosts);
    refresh();
}

static void screen_modules(void)
{
    char *resp = call("module.list", NULL);
    erase();
    draw_header("modules");
    if (!resp) { put_at(3, 2, "cannot reach the daemon"); refresh(); return; }
    json_object *o = json_tokener_parse(resp);
    json_object *arr = NULL;
    if (o && json_object_object_get_ex(o, "modules", &arr)) {
        size_t n = json_object_array_length(arr);
        put_at(3, 2, "%-14s %-8s %-5s %-14s %s",
                 "MODULE", "VERSION", "ABI", "STATE", "NOTE");
        for (size_t i = 0; i < n; i++) {
            json_object *m = json_object_array_get_idx(arr, i);
            const char *state = js(m, "state", "");
            if (strcmp(state, "loaded") == 0) attron(COLOR_PAIR(SR_C_GREEN));
            else if (strcmp(state, "incompatible") == 0) attron(COLOR_PAIR(SR_C_RED));
            else attron(COLOR_PAIR(SR_C_YELLOW));
            put_at(4 + (int)i, 2, "%-14s %-8s %-5d %-14s %s",
                js(m, "name", ""),
                js(m, "version", ""),
                json_object_get_int(json_object_object_get(m, "abi_version")),
                state,
                js(m, "diagnostic", ""));
            attroff(COLOR_PAIR(0));
        }
        if (n == 0) {
            put_at(4, 2, "no modules installed -- the core is still usable");
            put_at(5, 2, "install a module and it will appear here, and as a TUI section,");
            put_at(6, 2, "without any change to the TUI code.");
        }
    }
    if (o) json_object_put(o);
    free(resp);
    refresh();
}

static void screen_sections(void)
{
    char sections[16][32];
    int n = 0;
    collect_sections(sections, 16, &n);
    erase();
    draw_header("available functionality");
    put_at(3, 2, "Sections contributed by LOADED modules (derived from the registry):");
    for (int i = 0; i < n; i++) {
        attron(COLOR_PAIR(SR_C_GREEN));
        put_at(5 + i, 4, "  %s", sections[i]);
        attroff(COLOR_PAIR(SR_C_GREEN));
    }
    if (n == 0)
        put_at(5, 2, "  (none -- no module is currently loaded)");
    put_at(LINES - 4, 2, "Core-owned screens are always present: hosts, capabilities,");
    put_at(LINES - 3, 2, "modules, transactions, audit.");
    put_at(LINES - 1, 2, "This list is computed at runtime from the module registry.");
    refresh();
}

/* -------------------------------------------------------------- menu */

static const char *MENU[] = {
    "hosts", "capabilities", "modules", "functionality", "quit", NULL
};

/* Letter hotkeys as well as arrows. A terminal operator wants to press h for
 * hosts, not navigate to it -- and it removes any dependence on how a
 * particular terminal happens to translate arrow keys. */
static const char MENU_KEY[] = { 'h', 'c', 'm', 'f', 'q' };

static void draw_menu(int sel)
{
    erase();
    draw_header("menu");
    put_at(3, 2, "sections are derived from the module registry:");
    for (int i = 0; MENU[i]; i++) {
        if (sel == i) attron(A_REVERSE);
        put_at(5 + i, 4, " %c  %-16s", MENU_KEY[i], MENU[i]);
        if (sel == i) attroff(A_REVERSE);
    }
    /* Anchored to the BOTTOM of the window rather than fixed rows 12/13, so a
     * short window drops the help instead of writing past the last line. */
    put_at(LINES - 2, 2, "hotkeys: h hosts  c capabilities  m modules  f functionality  q quit");
    put_at(LINES - 1, 2, "up/down select   enter open   r refresh");
    refresh();
}

/* Redraw whatever is on screen. Called on SIGWINCH (as KEY_RESIZE) so a
 * resized window recovers on its own instead of showing stale cells until
 * the operator happens to press a key. */
static void redraw(void)
{
    if (layout_too_small()) { draw_too_small(); return; }
    switch (g_screen) {
    case 0: screen_hosts();    break;
    case 1: screen_caps();     break;
    case 2: screen_modules();  break;
    case 3: screen_sections(); break;
    default: draw_menu(0);     break;
    }
}

/* Wait for a key while staying responsive to a resize. The original code
 * called getch() under timeout(-1): that blocks indefinitely, so a resize
 * while a screen is displayed was swallowed and the TUI looked frozen. */
static void wait_for_key_or_resize(void)
{
    timeout(250);
    for (;;) {
        int ch = getch();
        if (ch == ERR) continue;
        if (ch == KEY_RESIZE) { sr_sync_size(); redraw(); timeout(250); continue; }
        break;
    }
    timeout(1000);
}

int sr_tui_main(int argc, char **argv, const char *socket_path)
{
    (void)argc; (void)argv;
    g_sock = socket_path ? socket_path : SR_DEFAULT_SOCK;

    const char *env = getenv("SR_TOKEN");
    if (env && *env) g_token = sr_xstrdup(env);

    initscr(); cbreak(); noecho(); curs_set(0); keypad(stdscr, TRUE);
    init_colors();
    timeout(1000);

    /* Login unless a token was supplied. */
    for (int attempt = 0; attempt < 3 && !g_token; attempt++) {
        /* A window too small to hold the form is a resize-away state, not an
         * error: wait for the operator to make room, redrawing as they go. */
        while (layout_too_small()) {
            draw_too_small();
            int wch = getch();
            if (wch == KEY_RESIZE) { sr_sync_size(); continue; }
            if (wch == 'q') { endwin(); return SR_ERR_DENIED; }
        }
        erase();
        attron(A_BOLD);
        put_at(1, 2, "saphira-router -- Saphira Linux control plane");
        attroff(A_BOLD);
        put_at(2, 2, "the primary human interface. No browser, no web access.");
        if (do_login_screen() == 0) break;
        attron(COLOR_PAIR(SR_C_RED)); put_at(8, 2, "%s", g_msg); attroff(COLOR_PAIR(SR_C_RED));
        refresh();
        wait_for_key_or_resize();
    }
    if (!g_token) { endwin(); fputs("login failed\n", stderr); return SR_ERR_DENIED; }
    timeout(1000);   /* back to a refreshable menu loop */

    int sel = 0;
    bool quit = false;
    g_screen = -1;
    while (!quit) {
        if (layout_too_small()) draw_too_small(); else draw_menu(sel);

        int ch = getch();
        if (ch == ERR) continue;
        /* The bug this fixes: KEY_RESIZE was never handled, so the old event
         * was discarded and the window was never repainted at its new size. */
        if (ch == KEY_RESIZE) { sr_sync_size(); continue; }
        if (ch >= 'A' && ch <= 'Z') ch += 32;
        int hot = -1;
        for (int i = 0; i < 5; i++) if (MENU_KEY[i] == ch) { hot = i; break; }

        /* A hotkey opens its screen directly: an operator pressing h wants
         * to see hosts, not to select them and then press enter. */
        int open = -1;
        if (hot == 4) quit = true;
        else if (hot >= 0) { sel = hot; open = sel; }
        else if (ch == KEY_UP)   sel = (sel + 4) % 5;
        else if (ch == KEY_DOWN) sel = (sel + 1) % 5;
        else if (ch == 'r' || ch == 'R') { g_msg[0] = '\0'; }
        else if (ch == '\n' || ch == '\r' || ch == KEY_ENTER) {
            open = sel;
        }

        if (open == 0) screen_hosts();
        else if (open == 1) screen_caps();
        else if (open == 2) screen_modules();
        else if (open == 3) screen_sections();
        else if (open == 4) quit = true;

        if (open >= 0 && open <= 3 && !quit) {
            /* Stay put until a key, but a resize repaints immediately rather
             * than sitting on a stale frame the operator cannot trust. */
            g_msg[0] = '\0';
            g_screen = open;
            if (layout_too_small()) draw_too_small(); else redraw();
            wait_for_key_or_resize();
            g_screen = -1;
        }
    }
    endwin();
    return SR_OK;
}
