/* cli.c -- the CLI: a thin, first-class client of the API.
 *
 * The CLI does not open the database and does not reimplement authorization
 * (D9 4). --json is the automation contract on every read and write, and exit
 * codes distinguish denied / failed / partial so a script can tell them
 * apart (D9 4, D8 6).
 */

#include "sr.h"
#include "sr_api.h"

#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

#define SR_DEFAULT_SOCK "/run/saphira-router/api.sock"

/* Session token cache, so the CLI is a client and not a login prompt. */
static char *g_token;

/* Build a request object with json-c rather than snprintf-and-concatenate.
 *
 * This is not fussiness. A hand-built format string wraps each value in
 * quotes, but an escaped value already carries its own, and the result is
 * ""172.16.7.100"" -- invalid JSON that the daemon correctly refuses. Using
 * the library removes that whole class of bug, which is the same reason
 * D1 9.1 chooses a packaged JSON library over a hand-rolled writer. */
static char *mkreq(const char *op, const char *k1, const char *v1,
                   const char *k2, const char *v2)
{
    json_object *o = json_object_new_object();
    json_object_object_add(o, "op", json_object_new_string(op));
    json_object_object_add(o, "token",
        json_object_new_string(g_token ? g_token : ""));
    if (k1) json_object_object_add(o, k1, json_object_new_string(v1 ? v1 : ""));
    if (k2) json_object_object_add(o, k2, json_object_new_string(v2 ? v2 : ""));
    char *r = sr_xstrdup(json_object_to_json_string_ext(o, JSON_C_TO_STRING_PLAIN));
    json_object_put(o);
    return r;
}

/* Three key/value pairs: a provider verb needs the op, a module, and a
 * payload -- one more pair than the two-pair builder above carries. */
static char *mkreq3(const char *op, const char *k1, const char *v1,
                    const char *k2, const char *v2,
                    const char *k3, const char *v3)
{
    char *r2 = mkreq(op, k1, v1, k2, v2);
    if (!k3 || !r2) return r2;
    json_object *o = json_tokener_parse(r2);
    free(r2);
    if (!o) return NULL;
    json_object_object_add(o, k3, json_object_new_string(v3 ? v3 : ""));
    char *r = sr_xstrdup(json_object_to_json_string_ext(o, JSON_C_TO_STRING_PLAIN));
    json_object_put(o);
    return r;
}

static const char *sock_path(void)
{
    const char *v = getenv("SR_SOCK");
    return (v && *v) ? v : SR_DEFAULT_SOCK;
}

static void mkdir_ignore(const char *p) { (void)mkdir(p, 0700); }

static int have_token(void)
{
    if (g_token) return 1;
    const char *t = getenv("SR_TOKEN");
    if (t && *t) { g_token = sr_xstrdup(t); return 1; }
    const char *home = getenv("HOME");
    if (!home) return 0;
    char path[SR_MAX_PATH];
    snprintf(path, sizeof path, "%s/.saphira-router/token", home);
    char *buf = NULL;
    if (sr_read_file(path, &buf, NULL) == 0 && buf) {
        sr_trim(buf);
        if (*buf) { g_token = buf; return 1; }
        free(buf);
    }
    return 0;
}

static void save_token(const char *tok)
{
    const char *home = getenv("HOME");
    if (!home || !tok) return;
    char path[SR_MAX_PATH];
    snprintf(path, sizeof path, "%s/.saphira-router/token", home);
    char *slash = strrchr(path, '/');
    if (slash) { *slash = '\0'; mkdir_ignore(path); *slash = '/'; }
    sr_write_file_atomic(path, tok, strlen(tok), 0600);
}

/* pretty-print or pass through, per --json */
static void emit(const char *json, int as_json)
{
    if (as_json) { printf("%s\n", json); return; }
    json_object *o = json_tokener_parse(json);
    if (!o) { printf("%s\n", json); return; }
    printf("%s\n", json_object_to_json_string_ext(o, JSON_C_TO_STRING_PRETTY));
    json_object_put(o);
}

static int has_flag(int argc, char **argv, const char *f)
{
    for (int i = 0; i < argc; i++) if (strcmp(argv[i], f) == 0) return 1;
    return 0;
}

/* --------------------------------------------------------- rendering */

static void render_modules(const char *json, int as_json)
{
    if (as_json) { emit(json, 1); return; }
    json_object *o = json_tokener_parse(json);
    json_object *arr = NULL;
    if (!o || !json_object_object_get_ex(o, "modules", &arr)) {
        printf("no module information\n"); return;
    }
    printf("%-14s %-8s %-6s %-14s %s\n", "MODULE", "VERSION", "ABI", "STATE", "NOTE");
    size_t n = json_object_array_length(arr);
    for (size_t i = 0; i < n; i++) {
        json_object *m = json_object_array_get_idx(arr, i);
        printf("%-14s %-8s %-6d %-14s %s\n",
            json_object_get_string(json_object_object_get(m, "name")),
            json_object_get_string(json_object_object_get(m, "version")),
            json_object_get_int(json_object_object_get(m, "abi_version")),
            json_object_get_string(json_object_object_get(m, "state")),
            json_object_get_string(json_object_object_get(m, "diagnostic")));
    }
    /* This table IS the set of available TUI functionality (D2 3, D9 2). */
    if (n == 0) printf("\n(no modules installed: the core is still usable)\n");
    json_object_put(o);
}

static void render_hosts(const char *json, int as_json)
{
    if (as_json) { emit(json, 1); return; }
    json_object *o = json_tokener_parse(json);
    json_object *arr = NULL;
    if (!o || !json_object_object_get_ex(o, "hosts", &arr)) { printf("no hosts\n"); return; }
    size_t n = json_object_array_length(arr);
    if (n == 0) { printf("no hosts enrolled\n"); return; }
    printf("%-18s %-16s %-10s %-10s %s\n", "HOST", "ADDRESS", "ARCH", "STATUS", "OS");
    for (size_t i = 0; i < n; i++) {
        json_object *h = json_object_array_get_idx(arr, i);
        printf("%-18s %-16s %-10s %-10s %s\n",
            json_object_get_string(json_object_object_get(h, "hostname")),
            json_object_get_string(json_object_object_get(h, "address_v4")),
            json_object_get_string(json_object_object_get(h, "arch")),
            json_object_get_string(json_object_object_get(h, "status")),
            json_object_get_string(json_object_object_get(h, "os_name")));
    }
    json_object_put(o);
}

static void render_caps(const char *json, int as_json)
{
    if (as_json) { emit(json, 1); return; }
    json_object *o = json_tokener_parse(json);
    json_object *arr = NULL;
    if (!o || !json_object_object_get_ex(o, "capabilities", &arr)) { printf("no data\n"); return; }
    size_t n = json_object_array_length(arr);
    if (n == 0) { printf("no capabilities discovered\n"); return; }
    printf("%-18s %-14s %-34s %s\n", "CAPABILITY", "STATE", "PROBE", "DETAIL");
    for (size_t i = 0; i < n; i++) {
        json_object *c = json_object_array_get_idx(arr, i);
        printf("%-18s %-14s %-34.34s %s\n",
            json_object_get_string(json_object_object_get(c, "capability")),
            json_object_get_string(json_object_object_get(c, "state")),
            json_object_get_string(json_object_object_get(c, "probe_method")),
            json_object_get_string(json_object_object_get(c, "detail")));
    }
    json_object_put(o);
}

/* ------------------------------------------------------------- login */

static int do_login(const char *user, const char *pass, const char *sock,
                    int as_json)
{
    if (!pass) {
        /* Read without echo so a password is not left in shell history. */
        struct termios old, t;
        tcgetattr(STDIN_FILENO, &old);
        t = old; t.c_lflag &= ~ECHO;
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t);
        char buf[256];
        fputs("password: ", stderr); fflush(stderr);
        if (!fgets(buf, sizeof buf, stdin)) buf[0] = '\0';
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &old);
        fputc('\n', stderr);
        pass = sr_xstrdup(sr_trim(buf));
    }
    int code = SR_OK;
    char *tok = NULL;
    char *resp = sr_api_login(sock, user, pass, &tok, &code);
    if (!resp) { fprintf(stderr, "cannot reach the daemon at %s\n", sock); return SR_ERR_FAILED; }
    if (tok) { g_token = tok; save_token(tok); }
    if (code != SR_OK) { emit(resp, as_json); return code; }
    if (as_json) emit(resp, 1);
    else {
        json_object *o = json_tokener_parse(resp);
        json_object *tv = NULL;
        if (o && json_object_object_get_ex(o, "token", &tv)) {
            char *t = sr_xstrdup(json_object_get_string(tv));
            /* never print the token itself */
            printf("logged in as %s (tenant %s); token stored in ~/.saphira-router/token\n",
                json_object_get_string(json_object_object_get(o, "user_id")),
                json_object_get_string(json_object_object_get(o, "tenant_id")));
            explicit_bzero(t, strlen(t));
            free(t);
            json_object_put(o);
            free(resp);
            return SR_OK;
        }
    }
    free(resp);
    return SR_OK;
}

/* -------------------------------------------------------------- main */

/* Provider replies carry the real answer inside a JSON string, so printing
 * the envelope hands the operator escaped JSON they have to read through. The
 * other verbs render their payload; this one should too. On a failure the
 * error field is the per-step report, which is exactly the thing an operator
 * needs when a step is refused, so it is printed rather than swallowed. */
/* Provider replies carry the real answer inside a JSON string, so printing the
 * envelope hands the operator escaped JSON they have to read through. The
 * other verbs render their payload; this one should too.
 *
 * On a refusal the payload is the per-step report -- which is exactly what an
 * operator needs when a step is refused -- so it is printed, not swallowed. */
static void render_provider(const char *resp, int as_json)
{
    if (as_json) { emit(resp, 1); return; }
    json_object *o = json_tokener_parse(resp);
    if (!o) { puts(resp); return; }

    json_object *v = NULL;
    int refused = 0;
    const char *inner = NULL;
    if (json_object_object_get_ex(o, "error", &v)) {
        refused = 1;
        inner = json_object_get_string(v);
    } else if (json_object_object_get_ex(o, "output", &v)) {
        inner = json_object_get_string(v);
    } else if (json_object_object_get_ex(o, "report", &v)) {
        inner = json_object_get_string(v);
    }

    if (inner && *inner) {
        if (refused) fputs("refused: ", stderr);
        puts(inner);
    } else {
        emit(resp, 0);
    }
    json_object_put(o);
}

int sr_cli_run(int argc, char **argv)
{
    const char *sock = sock_path();
    int as_json = has_flag(argc, argv, "--json");

    if (argc < 1) { fputs("no command\n", stderr); return SR_ERR_USAGE; }

    if (strcmp(argv[0], "login") == 0) {
        const char *user = "admin", *pass = NULL;
        for (int i = 1; i < argc - 1; i++) {
            if (strcmp(argv[i], "--user") == 0) user = argv[i+1];
            else if (strcmp(argv[i], "--password") == 0) pass = argv[i+1];
        }
        return do_login(user, pass, sock, as_json);
    }

    if (!have_token()) {
        fprintf(stderr,
            "not authenticated. Run:  saphira-router login --user <name>\n");
        return SR_ERR_DENIED;
    }

    /* build the request */
    const char *op = NULL;
    int code = SR_OK;
    char *resp = NULL;
    char *req = NULL;

    if (strcmp(argv[0], "host") == 0 && argc >= 2) {
        if (strcmp(argv[1], "list") == 0) {
            op = "host.list";
            req = mkreq(op, NULL, NULL, NULL, NULL);
        } else if (strcmp(argv[1], "enroll") == 0) {
            const char *addr = NULL, *name = NULL;
            for (int i = 2; i < argc - 1; i++) {
                if (strcmp(argv[i], "--address") == 0) addr = argv[i+1];
                else if (strcmp(argv[i], "--hostname") == 0) name = argv[i+1];
            }
            if (!addr) { fputs("host enroll: --address is required\n", stderr);
                         return SR_ERR_USAGE; }
            op = "host.enroll";
            req = mkreq(op, "address", addr, "hostname", name ? name : addr);
        } else if (strcmp(argv[1], "caps") == 0 && argc >= 3) {
            op = "host.caps";
            req = mkreq(op, "host_id", argv[2], NULL, NULL);
        } else {
            fputs("host: list | enroll | caps <id>\n", stderr);
            return SR_ERR_USAGE;
        }
    } else if (strcmp(argv[0], "module") == 0 && argc >= 2 &&
               strcmp(argv[1], "list") == 0) {
        op = "module.list";
        req = mkreq(op, NULL, NULL, NULL, NULL);
  } else if (strcmp(argv[0], "provider") == 0 && argc >= 2) {
      /* Provider verbs. An operator needs these to use a provider at all;
       * this is the product surface, not a test affordance. The CLI names
       * the module and the step, and the CORE decides whether that module
       * actually provides it -- the client asserts nothing. */
      const char *module = NULL, *step = NULL, *otype = NULL, *json = NULL;
      for (int k = 2; k < argc - 1; k++) {
          if      (strcmp(argv[k], "--module") == 0)      module = argv[k+1];
          else if (strcmp(argv[k], "--step") == 0)        step   = argv[k+1];
          else if (strcmp(argv[k], "--object-type") == 0) otype  = argv[k+1];
          /* NOT --json. The payload flag used to be --json as well, and
           * --json already means "print the raw envelope" everywhere else,
           * so has_flag() saw it and every provider transaction came back
           * as an unrendered envelope whatever the operator asked for. One
           * flag, one meaning: the payload is --spec. */
          else if (strcmp(argv[k], "--spec") == 0)        json   = argv[k+1];
      }
      if (strcmp(argv[1], "transaction") == 0) {
          if (!module || !json) {
              fputs("provider transaction: --module and --spec are required\n",
                    stderr);
              return SR_ERR_USAGE;
          }
          op = "provider.transaction";
          req = mkreq3(op, "module", module,
                       "object_type", otype ? otype : "provider_object",
                       "json", json);
      } else if (strcmp(argv[1], "invoke") == 0) {
          if (!module || !step) {
              fputs("provider invoke: --module and --step are required\n",
                    stderr);
              return SR_ERR_USAGE;
          }
          op = "provider.invoke";
          req = mkreq3(op, "module", module, "step", step,
                       "json", json ? json : "");
      } else if (strcmp(argv[1], "step") == 0 && argc >= 3) {
          /* Shorthand for the lifecycle steps an operator reaches for by
           * name: discover, observe, verify, rollback. */
          if (!module) {
              fputs("provider step: --module is required\n", stderr);
              return SR_ERR_USAGE;
          }
          op = "provider.invoke";
          req = mkreq3(op, "module", module, "step", argv[2],
                       "json", json ? json : "");
      } else {
          fputs("provider: transaction | invoke --step <name> | step <name>\n",
                stderr);
          return SR_ERR_USAGE;
      }
    } else if (strcmp(argv[0], "capability") == 0 && argc >= 2) {
        op = "capability.check";
        req = mkreq(op, "capability", argv[1], NULL, NULL);
    } else {
        fputs("commands: login | host list|enroll|caps | module list | "
                      "provider transaction|invoke|step | capability <code>\n",
              stderr);
        return SR_ERR_USAGE;
    }

    resp = sr_api_call(sock, req, &code);
    if (!resp) { fprintf(stderr, "cannot reach the daemon at %s\n", sock);
                 return SR_ERR_FAILED; }
    (void)op;

    free(req);

    if (op && strcmp(op, "host.list") == 0)        render_hosts(resp, as_json);
    else if (op && strcmp(op, "host.caps") == 0)   render_caps(resp, as_json);
    else if (op && strcmp(op, "module.list") == 0) render_modules(resp, as_json);
    else if (op && (strcmp(op, "provider.invoke") == 0 ||
               strcmp(op, "provider.transaction") == 0))
        render_provider(resp, as_json);
    else emit(resp, as_json);

    free(resp);   /* the reply is caller-owned */
    return code;
}

