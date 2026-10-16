/*
 * saphira-agents - install coding agents and provider SDKs from npm.
 *
 * Saphira edition. Two scopes, chosen up front (per-user is the
 * default):
 *
 *   per-user  run as yourself; installs under $HOME/.local via the
 *             npm_config_prefix environment override (bins land in
 *             ~/.local/bin, libraries in ~/.local/lib/node_modules).
 *             No root, no configuration files touched.
 *
 *   global    run under sudo; installs into /usr via an explicit
 *             npm_config_prefix=/usr (npm's compiled-in default is
 *             /usr/local, whose bin is not on Saphira's PATH).
 *             Root-owned, machine-wide; ordinary users execute but
 *             cannot replace or update the packages. The npm cache is
 *             pinned to /root/.npm-cache so a sudo run never writes
 *             root-owned files into a user's cache directory.
 *
 * Per-package install policy lives in the static table below: some
 * packages need a narrowly-scoped lifecycle approval
 * (--allow-scripts=<name>) because their postinstall selects or
 * links the native binary. Approvals are encoded only where the
 * upstream tarball was inspected and proven to need them; there is
 * deliberately no blanket script approval anywhere in this source.
 * --update reinstalls with the identical per-package policy.
 *
 * Per-package scope policy lives in the same table: a package whose
 * upstream guidance forbids a scope (Claude Code: Anthropic says not
 * to install with sudo npm install -g) is offered only where it is
 * allowed. The UI never presents a choice we know we should not run.
 *
 * State records what was installed (selection, package, version,
 * scope, timestamp) so --installed and --update can audit it. No
 * credentials, tokens, keys or environment values are ever stored,
 * and no login or provider configuration is performed.
 *
 * Release invariant (Saphira Node policy): Node.js comes from the
 * Saphira nodejs APK only. saphira-agents installs npm *application*
 * packages, never the Node/npm runtime itself: no Node downloads,
 * no version managers, no npm self-installs, no runtime replacement.
 * The static table below is the only source of installable names
 * and carries no runtime entries; install_pkg additionally refuses
 * them fail-closed (see the guard there).
 *
 * Licensed under the Business Source License 1.1, see LICENSE.
 */

#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <pwd.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/* nodejs runtime backing the npm backend (preflight in main). */
#define NODE_ABS "/usr/bin/node"
#define NPM_CLI "/usr/lib/node_modules/npm/bin/npm-cli.js"

#define GLOBAL_STATE "/var/lib/saphira-agents/state"
#define USER_STATE_REL ".local/share/saphira-agents/state"

#define SCOPE_GLOBAL 1
#define SCOPE_USER 2

#define BACKEND_NPM 0
#define BACKEND_DIRECT 1
#define BACKEND_PIP 2

/* Direct-download vendors (one small resolver each below). */
#define VENDOR_KIRO 1
#define VENDOR_ANTIGRAVITY 2
#define VENDOR_GOOSE 3
#define VENDOR_DEVIN 4

struct pkg {
	const char *selection;	/* UI label */
	const char *npm;	/* npm backend: package name; direct: NULL */
	const char *sid;	/* state identity (npm name, or direct id) */
	const char *kind;	/* "agent" or "sdk" */
	const char *allow_scripts; /* npm only: NULL or narrow package name */
	int scopes;		/* SCOPE_GLOBAL | SCOPE_USER bitmask */
	const char *conflicts;	/* npm name to remove first, or NULL */
	int backend;		/* BACKEND_NPM/DIRECT/PIP */
	/* BACKEND_DIRECT only: stable manifest resolved at runtime. */
	int vendor;		/* VENDOR_* selector for the resolver */
	const char *manifest_url;
	const char *url_base;	/* prefix for relative downloads, or NULL */
	const char *bin_path;	/* path inside the archive */
	const char *bin_name;	/* installed command name */
	/* BACKEND_PIP only: PyPI package name. */
	const char *pypi;
};

/*
 * Coding agents. Policy notes (verified 2026-10-14 against the npm
 * registry metadata):
 *
 * OpenCode tracks the current generation (@opencode/cli, v2).
 * opencode-ai is the v1 line; both provide the `opencode` command
 * and must not coexist, so installing v2 removes v1 first.
 * Its postinstall (node ./postinstall.mjs) selects the native
 * binary (linux-x64-musl is published), hence the narrow approval.
 *
 * Codex ships no lifecycle scripts at all: plain install.
 *
 * Claude Code's postinstall (node install.cjs) links the native
 * binary (linux-x64-musl published), hence the narrow approval.
 * Anthropic explicitly warns against sudo npm install -g, so it is
 * per-user-only here; the global choice is not offered for it.
 */
static const struct pkg agents[] = {
	{ "OpenCode", "@opencode/cli", "@opencode/cli", "agent",
	  "@opencode/cli", SCOPE_GLOBAL | SCOPE_USER, "opencode-ai",
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Codex", "@openai/codex", "@openai/codex", "agent",
	  NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Claude Code", "@anthropic-ai/claude-code", "@anthropic-ai/claude-code", "agent",
	  "@anthropic-ai/claude-code", SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Devin", NULL, "devin", "agent",
	  NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_DIRECT, VENDOR_DEVIN,
	  "https://static.devin.ai/cli/current/manifest.json",
	  NULL, "bin/devin", "devin", NULL },
	{ "Copilot CLI", "@github/copilot", "@github/copilot", "agent",
	  NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Kiro", NULL, "kiro-cli", "agent",
	  NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_DIRECT, VENDOR_KIRO,
	  "https://prod.download.cli.kiro.dev/stable/latest/manifest.json",
	  "https://prod.download.cli.kiro.dev/stable/",
	  "kirocli/bin/kiro-cli", "kiro-cli", NULL },
	{ "Antigravity", NULL, "agy", "agent",
	  NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_DIRECT, VENDOR_ANTIGRAVITY,
	  "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64_musl.json",
	  NULL, "antigravity", "agy", NULL },
	{ "Qwen Code", "@qwen-code/qwen-code", "@qwen-code/qwen-code", "agent",
	  "@qwen-code/audio-capture", SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Auggie", "@augmentcode/auggie", "@augmentcode/auggie", "agent",
	  "node-pty", SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Goose", NULL, "goose", "agent",
	  NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_DIRECT, VENDOR_GOOSE,
	  "https://api.github.com/repos/aaif-goose/goose/releases/latest",
	  NULL, "goose", "goose", NULL },
};

/*
 * Provider SDKs. Registry inspection showed no install/postinstall
 * scripts in any of these, so no lifecycle approval is encoded.
 * (venice-ai-sdk-provider carries only a `prepare: husky` stanza,
 * which npm does not run when installing a published tarball.)
 * Several providers share one SDK; installation deduplicates by npm
 * name so e.g. DeepSeek + NVIDIA + Z.AI install
 * @ai-sdk/openai-compatible exactly once.
 */
static const struct pkg sdks[] = {
	{ "Anthropic", "@ai-sdk/anthropic", "@ai-sdk/anthropic", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "OpenAI", "@ai-sdk/openai", "@ai-sdk/openai", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Google", "@ai-sdk/google", "@ai-sdk/google", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Azure", "@ai-sdk/azure", "@ai-sdk/azure", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "AWS Bedrock", "@ai-sdk/amazon-bedrock", "@ai-sdk/amazon-bedrock", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Google Vertex", "@ai-sdk/google-vertex", "@ai-sdk/google-vertex", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "xAI", "@ai-sdk/xai", "@ai-sdk/xai", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Meta", "@ai-sdk/openai", "@ai-sdk/openai", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Z.AI", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "DeepSeek", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "NVIDIA", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "MiniMax", "@ai-sdk/anthropic", "@ai-sdk/anthropic", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Moonshot", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Alibaba", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Cohere", "@ai-sdk/cohere", "@ai-sdk/cohere", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Baseten", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Cerebras", "@ai-sdk/cerebras", "@ai-sdk/cerebras", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Chutes", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Cloudflare AI Gateway", "ai-gateway-provider", "ai-gateway-provider", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Databricks", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "DeepInfra", "@ai-sdk/deepinfra", "@ai-sdk/deepinfra", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "DigitalOcean", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Fireworks", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Groq", "@ai-sdk/groq", "@ai-sdk/groq", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Together AI", "@ai-sdk/togetherai", "@ai-sdk/togetherai", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Thinking Machines", "@ai-sdk/anthropic", "@ai-sdk/anthropic", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Hugging Face", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Mistral", "@ai-sdk/mistral", "@ai-sdk/mistral", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "OpenRouter", "@openrouter/ai-sdk-provider", "@openrouter/ai-sdk-provider", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Poolside", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "SiliconFlow", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Vultr", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Venice AI", "venice-ai-sdk-provider", "venice-ai-sdk-provider", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Vercel AI Gateway", "@ai-sdk/gateway", "@ai-sdk/gateway", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "Xiaomi", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
	{ "LiteLLM", "@ai-sdk/openai-compatible", "@ai-sdk/openai-compatible", "sdk", NULL, SCOPE_GLOBAL | SCOPE_USER, NULL,
	  BACKEND_NPM, 0, NULL, NULL, NULL, NULL, NULL },
};

#define NAGENTS (sizeof agents / sizeof agents[0])
#define NSDKS (sizeof sdks / sizeof sdks[0])

static void die(const char *msg)
{
	fprintf(stderr, "saphira-agents: %s\n", msg);
	exit(1);
}

static void usage(FILE *f)
{
	fprintf(f,
"usage: saphira-agents [--setup | --list | --installed | --update | --help]\n"
"\n"
"  --setup        interactive installer (per-user scope by default)\n"
"  --list         show installable selections and their npm packages\n"
"  --installed    show packages recorded by saphira-agents\n"
"  --update       reinstall recorded packages at their current release\n"
"  --help         show this text\n");
}

/* mkdir -p without a shell: create each level, tolerate EEXIST. */
static int mkdir_p(const char *path)
{
	char tmp[PATH_MAX];
	size_t i, n;

	n = strlen(path);
	if (n == 0 || n >= sizeof tmp)
		return -1;
	memcpy(tmp, path, n + 1);
	for (i = 1; i <= n; i++) {
		if (tmp[i] == '/' || tmp[i] == '\0') {
			char save = tmp[i];
			tmp[i] = '\0';
			if (mkdir(tmp, 0755) != 0 && errno != EEXIST)
				return -1;
			tmp[i] = save;
		}
	}
	return 0;
}

static const char *home_dir(void)
{
	const char *h = getenv("HOME");
	if (h != NULL && h[0] != '\0')
		return h;
	{
		struct passwd *pw = getpwuid(getuid());
		if (pw != NULL && pw->pw_dir != NULL && pw->pw_dir[0] != '\0')
			return pw->pw_dir;
	}
	return NULL;
}

/* Library prefix backing an install scope: /usr globally so bins
 * land on PATH, $HOME/.local per user. */
static int scope_prefix(int scope, char *out, size_t n)
{
	if (scope == SCOPE_GLOBAL) {
		if (n < 5)
			return -1;
		memcpy(out, "/usr", 5);
		return 0;
	} else {
		const char *h = home_dir();
		if (h == NULL)
			return -1;
		if (snprintf(out, n, "%s/.local", h) >= (int)n)
			return -1;
		return 0;
	}
}

static int scope_state_path(int scope, char *out, size_t n)
{
	if (scope == SCOPE_GLOBAL) {
		if (strlen(GLOBAL_STATE) + 1 > n)
			return -1;
		strcpy(out, GLOBAL_STATE);
		return 0;
	} else {
		const char *h = home_dir();
		if (h == NULL)
			return -1;
		if (snprintf(out, n, "%s/%s", h, USER_STATE_REL) >= (int)n)
			return -1;
		return 0;
	}
}

/*
 * Run a child with an argv array via posix_spawn: no shell, no
 * command string, so selections can never inject options or
 * commands. argv[0] resolves via PATH. Returns the child's exit
 * status, or -1 when it did not exit.
 */
static int npm_run(char *const argv[])
{
	pid_t pid;
	int status;

	if (posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ) != 0) {
		fprintf(stderr, "saphira-agents: cannot execute %s: %s\n",
		    argv[0], strerror(errno));
		return -1;
	}
	while (waitpid(pid, &status, 0) < 0) {
		if (errno != EINTR) {
			fprintf(stderr, "saphira-agents: waitpid: %s\n",
			    strerror(errno));
			return -1;
		}
	}
	if (!WIFEXITED(status))
		return -1;
	return WEXITSTATUS(status);
}

/* Version recorded in an installed package's own package.json. */
static int installed_version(const char *prefix, const char *npm,
    char *out, size_t n)
{
	static char data[65536];
	char path[PATH_MAX];
	FILE *f;
	size_t len;
	char *v, *q, *e;

	if (snprintf(path, sizeof path, "%s/lib/node_modules/%s/package.json",
	    prefix, npm) >= (int)sizeof path)
		return -1;
	f = fopen(path, "r");
	if (f == NULL)
		return -1;
	len = fread(data, 1, sizeof data - 1, f);
	fclose(f);
	if (len == 0)
		return -1;
	data[len] = '\0';
	v = strstr(data, "\"version\"");
	if (v == NULL)
		return -1;
	q = strchr(v + 9, '"');
	if (q == NULL)
		return -1;
	q++;
	e = strchr(q, '"');
	if (e == NULL || (size_t)(e - q) >= n)
		return -1;
	memcpy(out, q, (size_t)(e - q));
	out[e - q] = '\0';
	return 0;
}

static int pkg_installed(const char *prefix, const char *npm)
{
	char path[PATH_MAX];
	struct stat st;

	if (snprintf(path, sizeof path, "%s/lib/node_modules/%s/package.json",
	    prefix, npm) >= (int)sizeof path)
		return 0;
	return stat(path, &st) == 0;
}

static const struct pkg *find_pkg(const char *sid);

static int pkg_present(const char *prefix, const char *sid)
{
	const struct pkg *p = find_pkg(sid);
	char path[PATH_MAX];

	if (p != NULL && p->backend == BACKEND_DIRECT) {
		if (p->bin_name == NULL)
			return 0;
		if (snprintf(path, sizeof path, "%s/bin/%s", prefix,
		    p->bin_name) >= (int)sizeof path)
			return 0;
		return access(path, X_OK) == 0;
	}
	return pkg_installed(prefix, sid);
}
static int record_install(const char *state, int scope,
    const char *identity, const char *selection, const char *version)
{
	char dir[PATH_MAX];
	char *slash;
	FILE *f;

	if (strlen(state) + 1 > sizeof dir)
		return -1;
	strcpy(dir, state);
	slash = strrchr(dir, '/');
	if (slash == NULL)
		return -1;
	*slash = '\0';
	if (mkdir_p(dir) != 0) {
		fprintf(stderr, "saphira-agents: cannot create %s: %s\n",
		    dir, strerror(errno));
		return -1;
	}
	f = fopen(state, "a");
	if (f == NULL) {
		fprintf(stderr, "saphira-agents: cannot write %s: %s\n",
		    state, strerror(errno));
		return -1;
	}
	fprintf(f, "%ld %s %s %s %s\n", (long)time(NULL),
	    scope == SCOPE_GLOBAL ? "global" : "user",
	    identity, version, selection);
	fclose(f);
	return 0;
}

/*
 * BACKEND_DIRECT: vendor standalone archives fetched at operator
 * request (the same explicit-action model as the npm backend).
 * Vendor curl-pipe installers are NEVER executed; only bare
 * artefacts named by the resolvers below are fetched, hashed
 * against vendor-published checksums, extracted with tar, and the
 * single named binary is placed in the scope prefix. All archives
 * used here are .tar.gz, so no unzip dependency exists.
 */

static int run_quiet(char *const argv[])
{
	pid_t pid;
	int status;

	if (posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ) != 0)
		return -1;
	while (waitpid(pid, &status, 0) < 0) {
		if (errno != EINTR)
			return -1;
	}
	if (!WIFEXITED(status))
		return -1;
	return WEXITSTATUS(status);
}

static int fetch_url(const char *url, const char *dest)
{
	char *argv[10];
	int argc = 0;

	argv[argc++] = "curl";
	argv[argc++] = "-fsSL";
	argv[argc++] = "--retry";
	argv[argc++] = "3";
	argv[argc++] = "--max-time";
	argv[argc++] = "600";
	argv[argc++] = "--output";
	argv[argc++] = (char *)dest;
	argv[argc++] = (char *)url;
	argv[argc] = NULL;
	return npm_run(argv);
}

/* Read a small whole file (manifests); caps at 1 MiB. */
static char *read_file(const char *path, size_t *lenp)
{
	FILE *f;
	char *buf;
	size_t len;

	f = fopen(path, "r");
	if (f == NULL)
		return NULL;
	buf = malloc(1048576 + 1);
	if (buf == NULL) {
		fclose(f);
		return NULL;
	}
	len = fread(buf, 1, 1048576, f);
	fclose(f);
	if (len == 0 && ferror(f)) {
		free(buf);
		return NULL;
	}
	(void)lenp;
	buf[len] = '\0';
	if (lenp != NULL)
		*lenp = len;
	return buf;
}

/*
 * Copy a JSON string value: find "key" at or after `from`
 * (staying within `span` bytes), then ':' then the opening quote.
 * No escape handling beyond \" (URLs and hashes never need more).
 */
static int json_string_at(const char *from, size_t span, const char *key,
    char *out, size_t n)
{
	char pat[128];
	const char *k, *c, *q, *e;
	size_t klen;

	if (snprintf(pat, sizeof pat, "\"%s\"", key) >= (int)sizeof pat)
		return -1;
	klen = strlen(pat);
	k = from;
	for (;;) {
		k = strstr(k, pat);
		if (k == NULL || (size_t)(k - from) >= span)
			return -1;
		/* key must be followed by optional space then ':' */
		c = k + klen;
		while ((size_t)(c - from) < span && (*c == ' ' || *c == '\t'))
			c++;
		if ((size_t)(c - from) < span && *c == ':')
			break;
		k++;
	}
	q = strchr(c, '"');
	if (q == NULL || (size_t)(q - from) >= span)
		return -1;
	q++;
	e = q;
	while ((size_t)(e - from) < span && *e != '\0' && *e != '"') {
		if (*e == '\\' && (size_t)(e + 1 - from) < span)
			e += 2;
		else
			e++;
	}
	if ((size_t)(e - from) >= span || *e != '"' || (size_t)(e - q) >= n)
		return -1;
	memcpy(out, q, (size_t)(e - q));
	out[e - q] = '\0';
	return 0;
}

static int json_string(const char *doc, const char *key, char *out, size_t n)
{
	return json_string_at(doc, strlen(doc), key, out, n);
}

/* Scratch work directory under TMPDIR (never the package payload). */
static int make_workdir(char *out, size_t n)
{
	const char *tmp = getenv("TMPDIR");
	static unsigned counter = 0;
	int i;

	if (tmp == NULL || tmp[0] == '\0')
		tmp = "/tmp";
	for (i = 0; i < 100; i++) {
		if (snprintf(out, n, "%s/saphira-agents-%ld-%u-%d", tmp,
		    (long)getpid(), counter++, i) >= (int)n)
			return -1;
		if (mkdir(out, 0700) == 0)
			return 0;
		if (errno != EEXIST)
			return -1;
	}
	return -1;
}

static int copy_file(const char *src, const char *dst)
{
	char buf[65536];
	FILE *in, *out;
	size_t n;

	in = fopen(src, "rb");
	if (in == NULL)
		return -1;
	out = fopen(dst, "wb");
	if (out == NULL) {
		fclose(in);
		return -1;
	}
	while ((n = fread(buf, 1, sizeof buf, in)) > 0) {
		if (fwrite(buf, 1, n, out) != n) {
			fclose(in);
			fclose(out);
			return -1;
		}
	}
	if (ferror(in)) {
		fclose(in);
		fclose(out);
		return -1;
	}
	fclose(in);
	if (fchmod(fileno(out), 0755) != 0) {
		fclose(out);
		return -1;
	}
	fclose(out);
	return 0;
}

/* Resolved artefact: versioned URL, hash, and upstream version. */
struct artefact {
	char url[1024];
	char algo[16];	/* "sha256" or "sha512" */
	char hash[256];
	char version[64];
};

/*
 * One resolver per vendor (explicit small parsers beat one clever
 * generic engine that silently resolves the wrong entry). Each
 * fetches the stable pointer and fills url/hash/version. Return 0
 * on success, 1 on any failure (fail closed: nothing installs).
 */

static int resolve_kiro(const struct pkg *p, struct artefact *a)
{
	char man[PATH_MAX], *doc, *hit;
	char rel[1024], hash[256], version[64];
	char base[512];
	(void)p;

	if (make_workdir(man, sizeof man) != 0)
		return 1;
	if (strlen(man) + 10 >= sizeof man)
		return 1;
	strcat(man, "/manifest.json");
	if (fetch_url("https://prod.download.cli.kiro.dev/stable/latest/manifest.json",
	    man) != 0)
		return 1;
	doc = read_file(man, NULL);
	if (doc == NULL)
		return 1;
	/* Walk musl entries; keep the tarGz one (no unzip dependency).
	 * Entry-bounded parsing: the fileType/download/sha256 keys must
	 * come from the SAME object as the matched targetTriple, never
	 * from a neighbour (a fixed window bleeds across entries). */
	hit = doc;
	rel[0] = '\0';
	for (;;) {
		const char *es, *ee;
		char ftype[64];
		size_t span;
		hit = strstr(hit,
		    "\"targetTriple\": \"x86_64-unknown-linux-musl\"");
		if (hit == NULL)
			break;
		es = hit;
		while (es > doc) {
			if (es[0] == '\n' && strncmp(es + 1, "    {\n", 6) == 0) {
				es++;
				break;
			}
			es--;
		}
		ee = strstr(hit, "\n    }");
		if (ee == NULL)
			break;
		span = (size_t)(ee + 5 - es);
		if (json_string_at(es, span, "fileType", ftype,
		    sizeof ftype) == 0 && strcmp(ftype, "tarGz") == 0 &&
		    json_string_at(es, span, "download", rel,
		    sizeof rel) == 0 &&
		    json_string_at(es, span, "sha256", hash,
		    sizeof hash) == 0)
			break;
		rel[0] = '\0';
		hit++;
	}
	if (rel[0] == '\0' || json_string(doc, "version", version,
	    sizeof version) != 0) {
		free(doc);
		return 1;
	}
	free(doc);
	snprintf(base, sizeof base, "%s",
	    "https://prod.download.cli.kiro.dev/stable/");
	if (snprintf(a->url, sizeof a->url, "%s%s", base, rel) >= (int)sizeof a->url)
		return 1;
	strcpy(a->algo, "sha256");
	strcpy(a->hash, hash);
	strcpy(a->version, version);
	return 0;
}

static int resolve_antigravity(const struct pkg *p, struct artefact *a)
{
	char man[PATH_MAX], *doc;
	char url[1024], hash[256], version[64];
	(void)p;

	if (make_workdir(man, sizeof man) != 0)
		return 1;
	strcat(man, "/manifest.json");
	if (fetch_url(p->manifest_url, man) != 0)
		return 1;
	doc = read_file(man, NULL);
	if (doc == NULL)
		return 1;
	if (json_string(doc, "url", url, sizeof url) != 0 ||
	    json_string(doc, "sha512", hash, sizeof hash) != 0 ||
	    json_string(doc, "version", version, sizeof version) != 0) {
		free(doc);
		return 1;
	}
	free(doc);
	strcpy(a->url, url);
	strcpy(a->algo, "sha512");
	strcpy(a->hash, hash);
	strcpy(a->version, version);
	return 0;
}

static int resolve_goose(const struct pkg *p, struct artefact *a)
{
	char man[PATH_MAX], *doc, *hit;
	char url[1024], digest[256], tag[64];
	(void)p;

	if (make_workdir(man, sizeof man) != 0)
		return 1;
	strcat(man, "/release.json");
	if (fetch_url(p->manifest_url, man) != 0)
		return 1;
	doc = read_file(man, NULL);
	if (doc == NULL)
		return 1;
	/* Asset entries list name before browser_download_url/digest. */
	hit = strstr(doc, "goose-x86_64-unknown-linux-musl.tar.gz");
	if (hit == NULL) {
		free(doc);
		return 1;
	}
	if (json_string_at(hit, 4000, "browser_download_url", url,
	    sizeof url) != 0 ||
	    json_string_at(hit, 4000, "digest", digest, sizeof digest) != 0 ||
	    json_string(doc, "tag_name", tag, sizeof tag) != 0) {
		free(doc);
		return 1;
	}
	free(doc);
	if (strncmp(digest, "sha256:", 7) != 0)
		return 1;
	strcpy(a->url, url);
	strcpy(a->algo, "sha256");
	strcpy(a->hash, digest + 7);
	if (tag[0] == 'v')
		memmove(tag, tag + 1, strlen(tag));
	strcpy(a->version, tag);
	return 0;
}

static int resolve_devin(const struct pkg *p, struct artefact *a)
{
	char man[PATH_MAX], *doc, *hit;
	char url[1024], hash[256], version[64];
	(void)p;

	if (make_workdir(man, sizeof man) != 0)
		return 1;
	strcat(man, "/manifest.json");
	if (fetch_url(p->manifest_url, man) != 0)
		return 1;
	doc = read_file(man, NULL);
	if (doc == NULL)
		return 1;
	hit = strstr(doc, "\"x86_64-unknown-linux-musl\"");
	if (hit == NULL) {
		free(doc);
		return 1;
	}
	if (json_string_at(hit, 2000, "url", url, sizeof url) != 0 ||
	    json_string_at(hit, 2000, "sha256", hash, sizeof hash) != 0 ||
	    json_string(doc, "version", version, sizeof version) != 0) {
		free(doc);
		return 1;
	}
	free(doc);
	strcpy(a->url, url);
	strcpy(a->algo, "sha256");
	strcpy(a->hash, hash);
	strcpy(a->version, version);
	return 0;
}

static int resolve_artefact(const struct pkg *p, struct artefact *a)
{
	switch (p->vendor) {
	case VENDOR_KIRO:
		return resolve_kiro(p, a);
	case VENDOR_ANTIGRAVITY:
		return resolve_antigravity(p, a);
	case VENDOR_GOOSE:
		return resolve_goose(p, a);
	case VENDOR_DEVIN:
		return resolve_devin(p, a);
	default:
		return 1;
	}
}

/* Verify archive bytes against the vendor hash via coreutils. */
static int verify_hash(const char *algo, const char *hash, const char *file)
{
	char chk[PATH_MAX], sum[32];
	char *argv[4];
	FILE *f;

	if (strcmp(algo, "sha256") == 0)
		strcpy(sum, "sha256sum");
	else if (strcmp(algo, "sha512") == 0)
		strcpy(sum, "sha512sum");
	else
		return 1;
	if (snprintf(chk, sizeof chk, "%s.check", file) >= (int)sizeof chk)
		return 1;
	f = fopen(chk, "w");
	if (f == NULL)
		return 1;
	fputs(hash, f);
	fputs("  ", f);
	fputs(file, f);
	fputs("\n", f);
	fclose(f);
	argv[0] = sum;
	argv[1] = "-c";
	argv[2] = chk;
	argv[3] = NULL;
	return run_quiet(argv);
}

static int install_direct(int scope, const char *prefix, const char *state,
    const struct pkg *p)
{
	struct artefact a;
	char work[PATH_MAX], archive[PATH_MAX], src[PATH_MAX], dst[PATH_MAX];
	char *argv[6];
	int rc;

	if (access("/usr/bin/curl", X_OK) != 0 || access("/usr/bin/tar", X_OK) != 0) {
		fprintf(stderr,
		    "saphira-agents: direct installs need curl and tar\n");
		return 1;
	}
	if (p->manifest_url == NULL || p->bin_path == NULL || p->bin_name == NULL)
		return 1;
	printf("%s: resolving current release\n", p->selection);
	if (resolve_artefact(p, &a) != 0) {
		fprintf(stderr,
		    "saphira-agents: cannot resolve %s release info\n",
		    p->selection);
		return 1;
	}
	if (make_workdir(work, sizeof work) != 0)
		return 1;
	if (snprintf(archive, sizeof archive, "%s/archive.tar.gz",
	    work) >= (int)sizeof archive)
		return 1;
	printf("%s: fetching %s\n", p->selection, a.url);
	if (fetch_url(a.url, archive) != 0) {
		fprintf(stderr, "saphira-agents: download failed for %s\n",
		    p->selection);
		return 1;
	}
	if (verify_hash(a.algo, a.hash, archive) != 0) {
		fprintf(stderr,
		    "saphira-agents: CHECKSUM MISMATCH for %s; aborting\n",
		    p->selection);
		return 1;
	}
	argv[0] = "tar";
	argv[1] = "-xzf";
	argv[2] = archive;
	argv[3] = "-C";
	argv[4] = work;
	argv[5] = NULL;
	if (npm_run(argv) != 0) {
		fprintf(stderr, "saphira-agents: extraction failed for %s\n",
		    p->selection);
		return 1;
	}
	if (snprintf(src, sizeof src, "%s/%s", work,
	    p->bin_path) >= (int)sizeof src)
		return 1;
	if (snprintf(dst, sizeof dst, "%s/bin/%s", prefix,
	    p->bin_name) >= (int)sizeof dst)
		return 1;
	{
		char bindir[PATH_MAX];
		char *slash;
		if (strlen(dst) + 1 > sizeof bindir)
			return 1;
		strcpy(bindir, dst);
		slash = strrchr(bindir, '/');
		if (slash == NULL)
			return 1;
		*slash = '\0';
		if (mkdir_p(bindir) != 0) {
			fprintf(stderr,
			    "saphira-agents: cannot create %s\n", bindir);
			return 1;
		}
	}
	if (copy_file(src, dst) != 0) {
		fprintf(stderr,
		    "saphira-agents: cannot install %s binary\n", p->selection);
		return 1;
	}
	argv[0] = "rm";
	argv[1] = "-rf";
	argv[2] = work;
	argv[3] = NULL;
	rc = npm_run(argv);
	(void)rc;
	printf("%s: installed %s %s\n", p->selection, p->bin_name, a.version);
	return record_install(state, scope, p->sid, p->selection, a.version);
}

/*
 * BACKEND_PIP: PyPI packages installed with --only-binary (fail
 * closed instead of compiling native deps at install time) into an
 * isolated target tree; the entry-point script is symlinked into
 * the scope bin. Same explicit-operator-action model as the rest.
 */
static int pip_version(const char *target, const char *pypi,
    char *out, size_t n)
{
	/* dist-info dir: <name>-<version>.dist-info, '-' for runs of [-_.] */
	char pre[256], metapath[PATH_MAX];
	DIR *d;
	struct dirent *e;
	size_t i, j;

	for (i = 0, j = 0; pypi[i] != '\0' && j + 1 < sizeof pre; i++) {
		if (pypi[i] == '-' || pypi[i] == '_' || pypi[i] == '.') {
			if (j == 0 || pre[j - 1] != '-')
				pre[j++] = '-';
		} else {
			pre[j++] = (char)tolower((unsigned char)pypi[i]);
		}
	}
	pre[j] = '\0';
	d = opendir(target);
	if (d == NULL)
		return -1;
	while ((e = readdir(d)) != NULL) {
		FILE *f;
		char line[256];
		if (strncmp(e->d_name, pre, strlen(pre)) != 0)
			continue;
		if (strstr(e->d_name, ".dist-info") == NULL)
			continue;
		if (snprintf(metapath, sizeof metapath, "%s/%s/METADATA",
		    target, e->d_name) >= (int)sizeof metapath) {
			closedir(d);
			return -1;
		}
		f = fopen(metapath, "r");
		if (f == NULL) {
			closedir(d);
			return -1;
		}
		while (fgets(line, sizeof line, f) != NULL) {
			if (strncmp(line, "Version: ", 9) == 0) {
				char *nl = strpbrk(line, "\r\n");
				if (nl != NULL)
					*nl = '\0';
				if (strlen(line + 9) + 1 > n) {
					fclose(f);
					closedir(d);
					return -1;
				}
				strcpy(out, line + 9);
				fclose(f);
				closedir(d);
				return 0;
			}
		}
		fclose(f);
		closedir(d);
		return -1;
	}
	closedir(d);
	return -1;
}

static int install_pip(int scope, const char *prefix, const char *state,
    const struct pkg *p)
{
	char target[PATH_MAX], bin[PATH_MAX], link[PATH_MAX];
	char version[64];
	char *argv[12];
	int argc = 0;

	if (p->pypi == NULL || p->bin_name == NULL)
		return 1;
	if (access("/usr/bin/python3", X_OK) != 0) {
		fprintf(stderr,
		    "saphira-agents: pip installs need python3\n");
		return 1;
	}
	if (snprintf(target, sizeof target, "%s/lib/saphira-agents/python",
	    prefix) >= (int)sizeof target)
		return 1;
	if (mkdir_p(target) != 0)
		return 1;
	argv[argc++] = "python3";
	argv[argc++] = "-m";
	argv[argc++] = "pip";
	argv[argc++] = "install";
	argv[argc++] = "--disable-pip-version-check";
	argv[argc++] = "--only-binary";
	argv[argc++] = ":all:";
	argv[argc++] = "--target";
	argv[argc++] = target;
	argv[argc++] = (char *)p->pypi;
	argv[argc] = NULL;
	printf("%s: pip install %s\n", p->selection, p->pypi);
	if (npm_run(argv) != 0) {
		fprintf(stderr, "saphira-agents: pip install failed for %s\n",
		    p->pypi);
		return 1;
	}
	if (snprintf(bin, sizeof bin, "%s/bin/%s", target,
	    p->bin_name) >= (int)sizeof bin)
		return 1;
	if (snprintf(link, sizeof link, "%s/bin/%s", prefix,
	    p->bin_name) >= (int)sizeof link)
		return 1;
	unlink(link);
	if (symlink(bin, link) != 0) {
		fprintf(stderr, "saphira-agents: cannot link %s\n", link);
		return 1;
	}
	if (pip_version(target, p->pypi, version, sizeof version) != 0) {
		fprintf(stderr,
		    "saphira-agents: installed %s but cannot read its version\n",
		    p->pypi);
		return 1;
	}
	printf("%s: installed %s %s\n", p->selection, p->pypi, version);
	return record_install(state, scope, p->sid, p->selection, version);
}

/*
 * Install one table entry into a scope. Backend dispatch lives here
 * and only here, so --update and interactive install cannot drift
 * apart: both call this function.
 */
static int install_npm(int scope, const char *prefix, const char *state,
    const struct pkg *p);

static int install_pkg(int scope, const char *prefix, const char *state,
    const struct pkg *p)
{
	if (p->backend == BACKEND_DIRECT)
		return install_direct(scope, prefix, state, p);
	if (p->backend == BACKEND_PIP)
		return install_pip(scope, prefix, state, p);
	return install_npm(scope, prefix, state, p);
}

/*
 * Install one npm table entry into a scope. Per-package policy is
 * built here and only here for BACKEND_NPM entries.
 */
static int install_npm(int scope, const char *prefix, const char *state,
    const struct pkg *p)
{
	char spec[256];
	char allow[256];
	char *argv[8];
	int argc = 0;
	char version[64];
	int rc;

	/*
	 * Release invariant: never install the Node/npm runtime itself.
	 * Only the static table above can reach this function and it
	 * holds no runtime entries, but a careless future table edit
	 * must fail closed here rather than replace /usr/bin/node or
	 * /usr/bin/npm out from under the Saphira nodejs APK.
	 */
	if (p->npm != NULL &&
	    (strcmp(p->npm, "npm") == 0 || strcmp(p->npm, "node") == 0)) {
		fprintf(stderr,
		    "saphira-agents: refusing to install runtime package %s\n",
		    p->npm);
		return 1;
	}
	if (p->conflicts != NULL && pkg_installed(prefix, p->conflicts)) {
		char *rm_argv[5];
		printf("%s: removing conflicting %s first\n",
		    p->selection, p->conflicts);
		rm_argv[0] = "npm";
		rm_argv[1] = "uninstall";
		rm_argv[2] = "-g";
		rm_argv[3] = (char *)p->conflicts;
		rm_argv[4] = NULL;
		if (npm_run(rm_argv) != 0) {
			fprintf(stderr,
			    "saphira-agents: cannot remove %s; aborting %s\n",
			    p->conflicts, p->selection);
			return 1;
		}
	}
	if (snprintf(spec, sizeof spec, "%s@latest", p->npm) >= (int)sizeof spec)
		return 1;
	argv[argc++] = "npm";
	argv[argc++] = "install";
	argv[argc++] = "-g";
	if (p->allow_scripts != NULL) {
		if (snprintf(allow, sizeof allow, "--allow-scripts=%s",
		    p->allow_scripts) >= (int)sizeof allow)
			return 1;
		argv[argc++] = allow;
	}
	argv[argc++] = spec;
	argv[argc] = NULL;
	printf("%s: npm install -g%s%s %s\n", p->selection,
	    p->allow_scripts != NULL ? " " : "",
	    p->allow_scripts != NULL ? allow : "", spec);
	rc = npm_run(argv);
	if (rc != 0) {
		fprintf(stderr, "saphira-agents: install failed for %s (rc=%d)\n",
		    p->npm, rc);
		return 1;
	}
	if (installed_version(prefix, p->npm, version, sizeof version) != 0) {
		fprintf(stderr,
		    "saphira-agents: installed %s but cannot read its version\n",
		    p->npm);
		return 1;
	}
	printf("%s: installed %s@%s\n", p->selection, p->npm, version);
	return record_install(state, scope, p->sid, p->selection, version);
}

static const struct pkg *find_pkg(const char *sid)
{
	size_t i;

	for (i = 0; i < NAGENTS; i++) {
		if (strcmp(agents[i].sid, sid) == 0)
			return &agents[i];
	}
	for (i = 0; i < NSDKS; i++) {
		if (strcmp(sdks[i].sid, sid) == 0)
			return &sdks[i];
	}
	return NULL;
}

static void print_scopes(int scopes)
{
	if ((scopes & SCOPE_GLOBAL) && (scopes & SCOPE_USER))
		printf("user, global");
	else if (scopes & SCOPE_USER)
		printf("user-only");
	else
		printf("global-only");
}

/* Display source: npm name, or the direct binary name. */
static const char *pkg_source(const struct pkg *p)
{
	static char direct[80];

	if (p->npm != NULL)
		return p->npm;
	snprintf(direct, sizeof direct, "direct:%s", p->bin_name);
	return direct;
}

static int cmd_list(void)
{
	size_t i;

	printf("Coding agents\n");
	for (i = 0; i < NAGENTS; i++) {
		printf("  %-12s %-32s [", agents[i].selection,
		    pkg_source(&agents[i]));
		print_scopes(agents[i].scopes);
		printf("]%s\n", agents[i].allow_scripts != NULL ?
		    " (narrow script approval)" : "");
	}
	printf("Provider SDKs\n");
	for (i = 0; i < NSDKS; i++) {
		printf("  %-22s %-32s [", sdks[i].selection, sdks[i].npm);
		print_scopes(sdks[i].scopes);
		printf("]\n");
	}
	return 0;
}

/* Show recorded installs; only the latest record per package is
 * shown (updates append, so history is preserved in the file).
 * Each entry is cross-checked against the prefix so a manually
 * removed package reads "(missing)" instead of lying. */
static int show_state_file(const char *label, const char *state,
    const char *prefix)
{
	FILE *f = fopen(state, "r");
	char *line = NULL;
	size_t cap = 0;
	ssize_t len;
	char (*rows)[512];
	size_t count = 0, alloc = 0, i, k;

	printf("%s (%s)\n", label, state);
	if (f == NULL) {
		printf("  (none recorded)\n");
		return 0;
	}
	rows = NULL;
	while ((len = getline(&line, &cap, f)) > 0) {
		long epoch;
		char scope[16], npm[128], version[64], sel[128];
		if (sscanf(line, "%ld %15s %127s %63s %127[^\n]", &epoch,
		    scope, npm, version, sel) != 5)
			continue;
		if (count >= alloc) {
			size_t nalloc = alloc == 0 ? 16 : alloc * 2;
			char (*n)[512];
			n = realloc(rows, nalloc * 512);
			if (n == NULL) {
				free(rows);
				free(line);
				fclose(f);
				die("out of memory");
			}
			rows = n;
			alloc = nalloc;
		}
		if (snprintf(rows[count], 512, "%ld %s %s %s %s",
		    epoch, scope, npm, version, sel) >= 512) {
			free(rows);
			free(line);
			fclose(f);
			die("state record is too long");
		}
		count++;
	}
	free(line);
	fclose(f);
	for (i = 0; i < count; i++) {
		long epoch;
		char scope[16], npm[128], version[64], sel[128];
		int superseded = 0;
		if (sscanf(rows[i], "%ld %15s %127s %63s %127[^\n]", &epoch,
		    scope, npm, version, sel) != 5)
			continue;
		for (k = i + 1; k < count; k++) {
			long e2;
			char s2[16], n2[128], v2[64], x2[128];
			if (sscanf(rows[k], "%ld %15s %127s %63s %127[^\n]", &e2,
			    s2, n2, v2, x2) != 5)
				continue;
			if (strcmp(n2, npm) == 0) {
				superseded = 1;
				break;
			}
		}
		if (!superseded)
			printf("  %-22s %-32s %-12s %s%s\n", sel, npm, version,
			    scope, pkg_present(prefix, npm) ? "" : " (missing)");
	}
	free(rows);
	if (count == 0)
		printf("  (none recorded)\n");
	return 0;
}

static int cmd_installed(void)
{
	char prefix[PATH_MAX], state[PATH_MAX];
	char uprefix[PATH_MAX], ustate[PATH_MAX];
	int global_ok = scope_prefix(SCOPE_GLOBAL, prefix, sizeof prefix) == 0 &&
	    scope_state_path(SCOPE_GLOBAL, state, sizeof state) == 0;
	int user_ok = scope_prefix(SCOPE_USER, uprefix, sizeof uprefix) == 0 &&
	    scope_state_path(SCOPE_USER, ustate, sizeof ustate) == 0;

	if (global_ok && access(state, R_OK) == 0)
		show_state_file("global", state, prefix);
	else
		printf("global (/var/lib/saphira-agents/state)\n  (none recorded)\n");
	if (user_ok)
		show_state_file("per-user", ustate, uprefix);
	else
		printf("per-user\n  (unavailable: HOME is not set)\n");
	return 0;
}

/*
 * Reinstall every package recorded in the current context's state
 * file (root: global, otherwise per-user) with its table policy.
 * Records are rewritten with the new versions.
 */
static int cmd_update(void)
{
	int scope = geteuid() == 0 ? SCOPE_GLOBAL : SCOPE_USER;
	char prefix[PATH_MAX], state[PATH_MAX];
	FILE *f;
	char *line = NULL;
	size_t cap = 0;
	ssize_t len;
	char (*npms)[128];
	char (*vers)[64];
	size_t count = 0, alloc = 0, i;
	int failures = 0;

	if (scope_prefix(scope, prefix, sizeof prefix) != 0 ||
	    scope_state_path(scope, state, sizeof state) != 0)
		die("cannot resolve install scope (HOME is not set)");
	f = fopen(state, "r");
	if (f == NULL) {
		printf("saphira-agents: nothing recorded in %s\n", state);
		return 0;
	}
	npms = NULL;
	vers = NULL;
	while ((len = getline(&line, &cap, f)) > 0) {
		long epoch;
		char fscope[16], npm[128], version[64], sel[128];
		size_t k;
		int seen = -1;
		if (sscanf(line, "%ld %15s %127s %63s %127[^\n]", &epoch,
		    fscope, npm, version, sel) != 5)
			continue;
		/* Keep the latest record per identity (updates append). */
		for (k = 0; k < count; k++) {
			if (strcmp(npms[k], npm) == 0) {
				seen = (int)k;
				break;
			}
		}
		if (seen >= 0) {
			strcpy(vers[seen], version);
			continue;
		}
		if (count >= alloc) {
			size_t nalloc = alloc == 0 ? 16 : alloc * 2;
			char (*n)[128];
			char (*v)[64];
			n = realloc(npms, nalloc * 128);
			if (n == NULL) {
				free(npms);
				free(vers);
				free(line);
				fclose(f);
				die("out of memory");
			}
			npms = n;
			v = realloc(vers, nalloc * 64);
			if (v == NULL) {
				free(npms);
				free(vers);
				free(line);
				fclose(f);
				die("out of memory");
			}
			vers = v;
			alloc = nalloc;
		}
		strcpy(npms[count], npm);
		strcpy(vers[count], version);
		count++;
	}
	free(line);
	fclose(f);
	if (count == 0) {
		free(npms);
		free(vers);
		printf("saphira-agents: nothing recorded in %s\n", state);
		return 0;
	}
	for (i = 0; i < count; i++) {
		const struct pkg *p = find_pkg(npms[i]);
		if (p == NULL) {
			fprintf(stderr,
			    "saphira-agents: %s is no longer offered; skipping\n",
			    npms[i]);
			continue;
		}
		if (p->backend == BACKEND_DIRECT) {
			struct artefact a;
			if (resolve_artefact(p, &a) != 0) {
				fprintf(stderr,
				    "saphira-agents: cannot resolve %s release info\n",
				    p->selection);
				failures++;
				continue;
			}
			if (strcmp(a.version, vers[i]) == 0) {
				printf("%s: already current (%s)\n",
				    p->selection, vers[i]);
				continue;
			}
			printf("%s: %s -> %s\n",
			    p->selection, vers[i], a.version);
		}
		if (install_pkg(scope, prefix, state, p) != 0)
			failures++;
	}
	free(npms);
	free(vers);
	if (failures != 0) {
		fprintf(stderr, "saphira-agents: %d update(s) failed\n", failures);
		return 1;
	}
	printf("saphira-agents: all recorded packages are current\n");
	return 0;
}

static int read_line(const char *prompt, char *out, size_t n)
{
	size_t len;

	printf("%s", prompt);
	fflush(stdout);
	if (fgets(out, (int)n, stdin) == NULL)
		return -1;
	len = strlen(out);
	while (len > 0 && (out[len - 1] == '\n' || out[len - 1] == '\r'))
		out[--len] = '\0';
	return 0;
}

/* Parse "1 3 5" into table indices; rejects junk instead of guessing. */
static int parse_picks(const char *in, size_t n,
    size_t *picks, size_t max, size_t *npicks)
{
	const char *s = in;
	*npicks = 0;

	for (;;) {
		char *end;
		long v;
		size_t k;
		int dup;
		while (*s != '\0' && isspace((unsigned char)*s))
			s++;
		if (*s == '\0')
			return 0;
		if (!isdigit((unsigned char)*s))
			return -1;
		v = strtol(s, &end, 10);
		if (v < 1 || v > (long)n)
			return -1;
		dup = 0;
		for (k = 0; k < *npicks; k++) {
			if (picks[k] == (size_t)(v - 1)) {
				dup = 1;
				break;
			}
		}
		if (!dup) {
			if (*npicks >= max)
				return -1;
			picks[*npicks] = (size_t)(v - 1);
			(*npicks)++;
		}
		s = end;
	}
}

static int pick_section(const char *title, const struct pkg *table, size_t n,
    size_t *picks, size_t max, size_t *npicks)
{
	char in[1024];
	size_t i;

	printf("\n%s\n", title);
	for (i = 0; i < n; i++) {
		printf("  [%2zu] %-22s %-30s [", i + 1,
		    table[i].selection, pkg_source(&table[i]));
		print_scopes(table[i].scopes);
		printf("]\n");
	}
	if (read_line("Select (numbers, space-separated, empty for none): ",
	    in, sizeof in) != 0)
		return -1;
	if (in[0] == '\0') {
		*npicks = 0;
		return 0;
	}
	if (parse_picks(in, n, picks, max, npicks) != 0) {
		fprintf(stderr, "saphira-agents: bad selection: %s\n", in);
		return -1;
	}
	return 0;
}

static int interactive(void)
{
	static size_t apicks[8], spicks[64];
	size_t na = 0, ns = 0, i;
	int scope = SCOPE_USER;
	char in[64];
	char prefix[PATH_MAX], state[PATH_MAX];
	const struct pkg *plan[72];
	size_t nplan = 0, k;
	int failures = 0;

	if (pick_section("Coding agents", agents, NAGENTS,
	    apicks, 8, &na) != 0)
		return 1;
	if (pick_section("Provider SDKs", sdks, NSDKS,
	    spicks, 64, &ns) != 0)
		return 1;
	if (na == 0 && ns == 0) {
		printf("saphira-agents: nothing selected\n");
		return 0;
	}
	if (read_line("Scope [user/global] (default user): ", in, sizeof in) != 0)
		return 1;
	if (in[0] == '\0' || strcmp(in, "user") == 0)
		scope = SCOPE_USER;
	else if (strcmp(in, "global") == 0)
		scope = SCOPE_GLOBAL;
	else {
		fprintf(stderr, "saphira-agents: scope must be user or global\n");
		return 1;
	}
	if (scope == SCOPE_GLOBAL && geteuid() != 0) {
		fprintf(stderr,
		    "saphira-agents: global installs need root; rerun under sudo\n"
		    "  (or choose per-user scope)\n");
		return 1;
	}
	/* Validate the whole plan before installing anything. */
	for (i = 0; i < na; i++)
		plan[nplan++] = &agents[apicks[i]];
	for (i = 0; i < ns; i++) {
		int dup = 0;
		for (k = 0; k < nplan; k++) {
			if (strcmp(plan[k]->npm, sdks[spicks[i]].npm) == 0) {
				dup = 1;
				break;
			}
		}
		if (!dup)
			plan[nplan++] = &sdks[spicks[i]];
	}
	for (k = 0; k < nplan; k++) {
		if (!(plan[k]->scopes & scope)) {
			fprintf(stderr,
			    "saphira-agents: %s is %s; %s scope is not offered for it\n",
			    plan[k]->selection,
			    (plan[k]->scopes & SCOPE_USER) ? "per-user-only" : "global-only",
			    scope == SCOPE_GLOBAL ? "global" : "per-user");
			return 1;
		}
	}
	if (scope_prefix(scope, prefix, sizeof prefix) != 0 ||
	    scope_state_path(scope, state, sizeof state) != 0)
		die("cannot resolve install scope (HOME is not set)");
	if (scope == SCOPE_GLOBAL) {
		setenv("npm_config_prefix", "/usr", 1);
		setenv("npm_config_cache", "/root/.npm-cache", 1);
	} else {
		char uprefix[PATH_MAX];
		if (snprintf(uprefix, sizeof uprefix, "%s/.local",
		    home_dir()) >= (int)sizeof uprefix)
			die("home directory path is too long");
		setenv("npm_config_prefix", uprefix, 1);
	}
	for (k = 0; k < nplan; k++) {
		if (install_pkg(scope, prefix, state, plan[k]) != 0)
			failures++;
	}
	if (failures != 0) {
		fprintf(stderr, "saphira-agents: %d install(s) failed\n", failures);
		return 1;
	}
	printf("saphira-agents: done (%s scope)\n",
	    scope == SCOPE_GLOBAL ? "global" : "per-user");
	return 0;
}

int main(int argc, char **argv)
{
	if (access(NODE_ABS, X_OK) != 0 || access(NPM_CLI, R_OK) != 0) {
		fprintf(stderr,
		    "saphira-agents: nodejs runtime with bundled npm is required\n");
		return 1;
	}
	if (argc == 1) {
		usage(stdout);
		return 0;
	}
	if (argc == 2 && strcmp(argv[1], "--setup") == 0)
		return interactive();
	if (argc == 2 && strcmp(argv[1], "--list") == 0)
		return cmd_list();
	if (argc == 2 && strcmp(argv[1], "--installed") == 0)
		return cmd_installed();
	if (argc == 2 && strcmp(argv[1], "--update") == 0) {
		if (geteuid() == 0) {
			setenv("npm_config_prefix", "/usr", 1);
			setenv("npm_config_cache", "/root/.npm-cache", 1);
		} else {
			const char *h = home_dir();
			char uprefix[PATH_MAX];
			if (h == NULL)
				die("HOME is not set");
			if (snprintf(uprefix, sizeof uprefix, "%s/.local",
			    h) >= (int)sizeof uprefix)
				die("home directory path is too long");
			setenv("npm_config_prefix", uprefix, 1);
		}
		return cmd_update();
	}
	if (argc == 2 &&
	    (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
		usage(stdout);
		return 0;
	}
	usage(stderr);
	return 1;
}
