/*
 * saphira-elf-closure -- print the shared-library closure of an ELF object.
 *
 * A package-internal tool, deliberately not a documented mkinitramfs command.
 *
 * WHY THIS EXISTS. Collecting an executable's libraries normally means shelling
 * out to readelf/objdump, which would make binutils a RUNTIME dependency of
 * every installed Saphira machine purely so that machine could regenerate its
 * own initramfs. That is a bad trade: binutils is large, and an initramfs
 * generator is exactly the sort of thing that has to work on a minimal
 * installed system. So the closure logic lives here, in a few hundred lines
 * of C, and the only dependency is libc.
 *
 * OUTPUT. One absolute path per line, in discovery order, deduplicated:
 *
 *   - the PT_INTERP loader, when the object is dynamically linked;
 *   - every DT_NEEDED object, resolved and followed transitively.
 *
 * The named object itself is NOT printed: the caller already has it and wants
 * its libraries. A statically linked object prints nothing and exits 0. That
 * is a legitimate result, not a failure: /init is static musl and must pull in
 * no libraries at all.
 *
 * USAGE
 *   saphira-elf-closure BINARY [EXTRA-SEARCH-DIR]...
 *
 * Soname search order: the directory of the referring object, then each
 * EXTRA-SEARCH-DIR, then the system library directories.
 *
 * Exit 1 if a DT_NEEDED or the interpreter cannot be resolved. A silently
 * incomplete closure yields an initramfs that fails at boot with no
 * diagnostic, which is far worse than refusing to build.
 */

#define _GNU_SOURCE

#include <elf.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *const system_dirs[] = {
	"/lib", "/usr/lib", "/lib64", "/usr/lib64", "/usr/local/lib", NULL
};

/* Objects already emitted or walked. Linear scan: a closure is tens of
 * entries, not thousands, and this keeps the code obviously correct. */
static char **seen;
static size_t seen_count, seen_cap;

static int seen_has(const char *path)
{
	size_t i;

	for (i = 0; i < seen_count; i++)
		if (strcmp(seen[i], path) == 0)
			return 1;
	return 0;
}

static void seen_add(const char *path)
{
	char *copy;

	if (seen_has(path))
		return;
	if (seen_count == seen_cap) {
		char **grown = realloc(seen, seen_cap * 2 * sizeof *seen);

		if (!grown) {
			fprintf(stderr, "saphira-elf-closure: out of memory\n");
			exit(1);
		}
		seen = grown;
		seen_cap = seen_cap ? seen_cap * 2 : 32;
	}
	copy = strdup(path);
	if (!copy) {
		fprintf(stderr, "saphira-elf-closure: out of memory\n");
		exit(1);
	}
	seen[seen_count++] = copy;
}

static void die(const char *what, const char *detail)
{
	fprintf(stderr, "saphira-elf-closure: %s: %s\n", what, detail);
	exit(1);
}

static char *dir_of(const char *path)
{
	const char *slash = strrchr(path, '/');
	char *out;
	size_t n;

	if (!slash)
		return strdup(".");
	if (slash == path)
		return strdup("/");
	n = (size_t)(slash - path);
	out = malloc(n + 1);
	if (!out) {
		fprintf(stderr, "saphira-elf-closure: out of memory\n");
		exit(1);
	}
	memcpy(out, path, n);
	out[n] = '\0';
	return out;
}

static int try_path(const char *dir, const char *name, char *out, size_t outlen)
{
	snprintf(out, outlen, "%s/%s", dir, name);
	return access(out, F_OK) == 0;
}

static char *resolve_soname(const char *soname, const char *referrer,
			    char *const *extra_dirs, size_t extra_count)
{
	char candidate[PATH_MAX];
	char *referrer_dir;
	size_t i;

	if (strchr(soname, '/')) {
		/* A DT_NEEDED carrying a path is used as given. */
		if (access(soname, F_OK) == 0)
			return strdup(soname);
		return NULL;
	}
	referrer_dir = dir_of(referrer);
	if (try_path(referrer_dir, soname, candidate, sizeof candidate)) {
		free(referrer_dir);
		return strdup(candidate);
	}
	free(referrer_dir);
	for (i = 0; i < extra_count; i++)
		if (try_path(extra_dirs[i], soname, candidate, sizeof candidate))
			return strdup(candidate);
	for (i = 0; system_dirs[i]; i++)
		if (try_path(system_dirs[i], soname, candidate, sizeof candidate))
			return strdup(candidate);
	return NULL;
}

static char *slurp(const char *path, size_t *len_out)
{
	FILE *f = fopen(path, "rb");
	struct stat st;
	char *buf;

	if (!f)
		return NULL;
	if (fstat(fileno(f), &st) != 0 || st.st_size <= 0) {
		fclose(f);
		return NULL;
	}
	buf = malloc((size_t)st.st_size);
	if (!buf) {
		fclose(f);
		return NULL;
	}
	if (fread(buf, 1, (size_t)st.st_size, f) != (size_t)st.st_size) {
		free(buf);
		fclose(f);
		return NULL;
	}
	fclose(f);
	*len_out = (size_t)st.st_size;
	return buf;
}

/* Emit one discovered object unless already known, and return whether it was
 * new. New objects are appended to seen; the caller recurses over the ones
 * that were new, which is what makes the walk transitive. */
static int discover(const char *path)
{
	if (seen_has(path))
		return 0;
	puts(path);
	seen_add(path);
	return 1;
}

static void walk(const char *path, char *const *extra_dirs, size_t extra_count);

/* Append to the per-object discovery list.
 *
 * The capacity test comes FIRST and the allocation is unconditional inside it.
 * The obvious alternative -- realloc(found, found_cap * 2 * ...) -- asks
 * realloc for zero bytes on the first append, and realloc(NULL, 0) is
 * permitted to return NULL, which the out-of-memory check then reports as
 * failure on the very first library found. */
static void add_found(char ***list, size_t *count, size_t *cap, char *item)
{
	if (*count == *cap) {
		size_t want = *cap ? *cap * 2 : 8;
		char **grown = realloc(*list, want * sizeof **list);

		if (!grown)
			die("out of memory", "growing the discovery list");
		*list = grown;
		*cap = want;
	}
	(*list)[(*count)++] = item;
}

static void descend(char *const *new_items, size_t count,
		    char *const *extra_dirs, size_t extra_count)
{
	size_t i;

	for (i = 0; i < count; i++) {
		char *copy = strdup(new_items[i]);

		if (!copy)
			die("out of memory", "");
		walk(copy, extra_dirs, extra_count);
		free(copy);
	}
}

static void walk(const char *path, char *const *extra_dirs, size_t extra_count)
{
	char *buf;
	size_t len, i, mark;
	const Elf64_Ehdr *eh;
	char interp[PATH_MAX];
	int have_interp = 0;
	const Elf64_Shdr *sh = NULL;
	size_t shnum = 0;
	const Elf64_Shdr *dyn = NULL, *dynstr = NULL;
	char **found = NULL;
	size_t found_count = 0, found_cap = 0;

	if (seen_has(path) && strcmp(path, "") != 0) {
		/* Already emitted and walked by an earlier branch. */
	}
	buf = slurp(path, &len);
	if (!buf)
		die("cannot read", path);
	if (len < sizeof(Elf64_Ehdr) || memcmp(buf, ELFMAG, SELFMAG) != 0)
		die("not an ELF object", path);
	eh = (const Elf64_Ehdr *)buf;
	if (eh->e_ident[EI_CLASS] != ELFCLASS64)
		die("not ELF64", path);


	/* PT_INTERP, from the program headers. */
	if (eh->e_phoff && eh->e_phnum) {
		const Elf64_Phdr *ph = (const Elf64_Phdr *)(buf + eh->e_phoff);

		for (i = 0; i < eh->e_phnum; i++) {
			if (ph[i].p_type == PT_INTERP && ph[i].p_filesz > 0 &&
			    ph[i].p_filesz < sizeof interp) {
				memcpy(interp, buf + ph[i].p_offset, ph[i].p_filesz);
				interp[ph[i].p_filesz] = '\0';
				have_interp = 1;
			}
		}
	}

	/* .dynamic and its string table, from the section headers. Using the
	 * section header's own strtab avoids converting DT_STRTAB's vaddr back
	 * into a file offset. */
	if (eh->e_shoff && eh->e_shnum && eh->e_shentsize >= sizeof(Elf64_Shdr)) {
		sh = (const Elf64_Shdr *)(buf + eh->e_shoff);
		shnum = eh->e_shnum;
		for (i = 0; i < shnum; i++) {
			if (sh[i].sh_type != SHT_DYNAMIC)
				continue;
			dyn = &sh[i];
			if (dyn->sh_link < shnum)
				dynstr = &sh[dyn->sh_link];
			break;
		}
	}

	if (have_interp) {
		char *resolved = resolve_soname(interp, path, extra_dirs, extra_count);

		if (!resolved) {
			char detail[PATH_MAX + 64];

			snprintf(detail, sizeof detail, "cannot resolve interpreter '%s'", interp);
			free(buf);
			die(detail, path);
		}
		add_found(&found, &found_count, &found_cap, resolved);
	}

	if (dyn && dynstr) {
		const Elf64_Dyn *d = (const Elf64_Dyn *)(buf + dyn->sh_offset);
		size_t n = dyn->sh_size / sizeof(Elf64_Dyn);
		const char *strs = buf + dynstr->sh_offset;
		size_t strs_size = dynstr->sh_size;

		for (i = 0; i < n; i++) {
			char *resolved;

			if (d[i].d_tag == DT_NULL)
				break;
			if (d[i].d_tag != DT_NEEDED)
				continue;
			if (d[i].d_un.d_val >= strs_size) {
				free(buf);
				die("bad DT_NEEDED offset", path);
			}
			resolved = resolve_soname(strs + d[i].d_un.d_val, path,
						  extra_dirs, extra_count);
			if (!resolved) {
				char detail[512];

				snprintf(detail, sizeof detail, "cannot resolve '%s'",
					 strs + d[i].d_un.d_val);
				free(buf);
				die(detail, path);
			}
			add_found(&found, &found_count, &found_cap, resolved);
		}
	}

	/*
	 * Emit whatever is new, then recurse into exactly those.
	 *
	 * Ownership note, because getting it wrong is a double free rather than
	 * a wrong answer: found[] entries are freed EXACTLY ONCE, here. An
	 * earlier version also freed the ones discover() reported as already
	 * seen, then fell through to this loop and freed them again -- which
	 * segfaulted as soon as a library named a dependency that had already
	 * been recorded, i.e. on almost any real binary. A pipelined run hid
	 * the crash, because the exit status was the pipeline's.
	 */
	mark = seen_count;
	for (i = 0; i < found_count; i++)
		discover(found[i]);
	for (i = 0; i < found_count; i++)
		free(found[i]);
	free(found);

	/* Everything from mark onwards was newly discovered and needs walking. */
	{
		size_t total = seen_count - mark;
		char **batch;
		size_t k;

		if (total == 0) {
			free(buf);
			return;
		}
		batch = malloc(total * sizeof *batch);
		if (!batch)
			die("out of memory", "building the walk batch");
		for (k = 0; k < total; k++) {
			batch[k] = strdup(seen[mark + k]);
			if (!batch[k])
				die("out of memory", "building the walk batch");
		}
		descend(batch, total, extra_dirs, extra_count);
		for (k = 0; k < total; k++)
			free(batch[k]);
		free(batch);
	}
	free(buf);
}

int main(int argc, char **argv)
{
	char target[PATH_MAX];
	char *const *extra;
	size_t extra_count;
	char resolved[PATH_MAX];

	if (argc < 2) {
		fprintf(stderr, "usage: %s BINARY [EXTRA-SEARCH-DIR]...\n", argv[0]);
		return 2;
	}
	if (argv[1][0] == '/')
		snprintf(target, sizeof target, "%s", argv[1]);
	else {
		char cwd[PATH_MAX];

		if (!getcwd(cwd, sizeof cwd))
			die("cannot determine the working directory", "");
		if (snprintf(target, sizeof target, "%s/%s", cwd, argv[1]) >=
		    (int)sizeof target)
			die("path is too long", argv[1]);
	}
	if (access(target, F_OK) != 0)
		die("no such file", target);
	snprintf(resolved, sizeof resolved, "%s", target);

	extra = argc > 2 ? &argv[2] : NULL;
	extra_count = argc > 2 ? (size_t)(argc - 2) : 0;

	/* Mark the target so it is walked but never printed: the caller already
	 * has that object and asked only for its libraries. */
	seen_add(resolved);
	walk(resolved, extra, extra_count);
	return 0;
}
