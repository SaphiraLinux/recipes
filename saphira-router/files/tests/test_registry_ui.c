/* test_registry_ui.c -- the D2 9 design test, made executable.
 *
 * The claim under test: installing a module makes functionality APPEAR and
 * removing it makes it disappear cleanly, WITHOUT editing the interface.
 *
 * The strongest form of that is not "the TUI looks right" but "the TUI source
 * never changed while the available functionality did". So this test hashes
 * the TUI and the core interface files before and after the whole
 * install/remove cycle and fails if a single byte moved.
 */
#include "sr_db.h"
#include "sr.h"
#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int   sr_module_load_all(sr_db *, const char *, const char *, const char *);
extern char *sr_module_registry_json(sr_db *);
extern int   sr_module_count(void);

static int failures;
static void check(const char *what, int cond)
{
    printf("  %-58s %s\n", what, cond ? "PASS" : "**FAIL**");
    if (!cond) failures++;
}

/* The TUI derives its section list from LOADED modules only. This mirrors
 * tui.c:collect_sections() -- and parses with json-c, as the TUI does, rather
 * than with a hand-rolled tokenizer. (An earlier version of this test split
 * the JSON on braces and commas, which put "name" and "state" in different
 * tokens so nothing ever matched.) */
static int sections_from_registry(sr_db *db, char out[][32], int max)
{
    int n = 0;
    char *resp = sr_module_registry_json(db);
    if (!resp) return -1;
    json_object *o = json_tokener_parse(resp);
    /* sr_module_registry_json() returns a bare ARRAY; the API layer wraps it
     * as {"modules":[...]}. Accept either, so the test exercises the same
     * derivation whether it reads the registry or the API reply. */
    json_object *arr = NULL;
    if (o && json_object_is_type(o, json_type_array)) {
        arr = o;
    } else if (o && json_object_object_get_ex(o, "modules", &arr)) {
        /* wrapped: leave as is */
    }
    if (arr) {
        size_t m = json_object_array_length(arr);
        for (size_t i = 0; i < m && n < max; i++) {
            json_object *mo = json_object_array_get_idx(arr, i);
            const char *state = json_object_get_string(
                json_object_object_get(mo, "state"));
            const char *name = json_object_get_string(
                json_object_object_get(mo, "name"));
            /* Only a LOADED module contributes availability. An incompatible
             * or refused module is reported, never presented as usable. */
            if (state && name && strcmp(state, "loaded") == 0) {
                snprintf(out[n++], 32, "%s", name);
            }
        }
    }
    if (o) json_object_put(o);
    free(resp);
    return n;
}

static void hash_of(const char *path, char *out, size_t n)
{
    char *buf = NULL;
    size_t len = 0;
    out[0] = '\0';
    if (sr_read_file(path, &buf, &len) < 0 || !buf) return;
    /* A content fingerprint is enough to prove the file did not change. */
    unsigned long h = 5381;
    for (size_t i = 0; i < len; i++) h = ((h << 5) + h) + (unsigned char)buf[i];
    snprintf(out, n, "%lx:%zu", h, len);
    free(buf);
}

#include <sys/stat.h>
#include <sys/types.h>

static void mkdir_ignore(const char *p) { (void)mkdir(p, 0700); }

int main(int argc, char **argv)
{
    const char *dir = argc > 1 ? argv[1] : "build";

    /* Stage the module set under our control. */
    const char *empty = "/tmp/sr_mod_empty";
    const char *full  = "/tmp/sr_mod_full";
    const char *bad   = "/tmp/sr_mod_bad";
    mkdir_ignore(empty); mkdir_ignore(full); mkdir_ignore(bad);

    char cmd[512];
    snprintf(cmd, sizeof cmd, "cp %s/mod_fixture.so %s/ 2>/dev/null", dir, full);
    if (system(cmd) != 0) { puts("cannot stage mod_fixture.so"); return 1; }
    snprintf(cmd, sizeof cmd, "cp %s/mod_badabi.so %s/ 2>/dev/null", dir, bad);
    if (system(cmd) != 0) { puts("cannot stage mod_badabi.so"); return 1; }
    snprintf(cmd, sizeof cmd, "cp %s/mod_fixture.so %s/ 2>/dev/null", dir, bad);
    (void)system(cmd);

    unlink("/tmp/sr_ui.db"); unlink("/tmp/sr_ui.db-wal"); unlink("/tmp/sr_ui.db-shm");
    sr_db *db = NULL; char *err = NULL;
    sr_db_open("/tmp/sr_ui.db", &db);
    sr_db_migrate(db, &err);
    sr_db_exec(db, "INSERT INTO tenant(id,slug,name,created_at,updated_at) "
                   "VALUES('t1','t','T',datetime('now'),datetime('now'))", &err);

    /* Fingerprint the interface sources BEFORE anything is installed. */
    char tui_before[64], cli_before[64], api_before[64], main_before[64];
    hash_of("src/tui.c",  tui_before,  sizeof tui_before);
    hash_of("src/cli.c",  cli_before,  sizeof cli_before);
    hash_of("src/api.c",  api_before,  sizeof api_before);
    hash_of("src/main.c", main_before, sizeof main_before);
    check("interface sources are present to fingerprint", tui_before[0] != '\0');

    char secs[16][32];

    /* 1. No module installed: the interface has no provider sections. */
    int n0 = sr_module_load_all(db, empty, "a", "t1");
    int s0 = sections_from_registry(db, secs, 16);
    printf("  stage 1 (no modules):   loaded=%d  sections=%d\n", n0, s0);
    check("core usable with zero modules", n0 == 0 && s0 == 0);

    /* 2. Install a provider. The section must APPEAR. */
    n0 = sr_module_load_all(db, full, "a", "t1");
    int s1 = sections_from_registry(db, secs, 16);
    printf("  stage 2 (fixture in):   loaded=%d  sections=%d", n0, s1);
    if (s1 > 0) printf("  [%s]", secs[0]);
    printf("\n");
    check("installing a module makes a section appear", s1 == 1);
    check("the section is named by the module", s1 == 1 && strcmp(secs[0], "fixture") == 0);

    /* 3. An incompatible module must NOT contribute a section. */
    n0 = sr_module_load_all(db, bad, "a", "t1");
    int s2 = sections_from_registry(db, secs, 16);
    printf("  stage 3 (+badabi):      loaded=%d  sections=%d\n", n0, s2);
    check("a refused module contributes NO section", s2 == 1);

    /* 4. Remove it again. The section must DISAPPEAR. */
    n0 = sr_module_load_all(db, empty, "a", "t1");
    int s3 = sections_from_registry(db, secs, 16);
    printf("  stage 4 (removed):      loaded=%d  sections=%d\n", n0, s3);
    check("removing a module makes the section disappear cleanly", s3 == 0);

    /* The design test proper: none of the interface files moved. */
    char tui_after[64], cli_after[64], api_after[64], main_after[64];
    hash_of("src/tui.c",  tui_after,  sizeof tui_after);
    hash_of("src/cli.c",  cli_after,  sizeof cli_after);
    hash_of("src/api.c",  api_after,  sizeof api_after);
    hash_of("src/main.c", main_after, sizeof main_after);
    printf("\n  tui.c  %s -> %s\n", tui_before, tui_after);
    check("src/tui.c byte-identical across install AND remove",
          strcmp(tui_before, tui_after) == 0);
    check("src/cli.c byte-identical", strcmp(cli_before, cli_after) == 0);
    check("src/api.c byte-identical", strcmp(api_before, api_after) == 0);
    check("src/main.c byte-identical", strcmp(main_before, main_after) == 0);

    printf("\n");
    if (failures == 0) puts("  ALL PASS");
    else printf("  %d FAILURE(S)\n", failures);
    return failures ? 1 : 0;
}
