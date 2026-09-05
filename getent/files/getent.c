/*
 * getent - look up entries in the local system credential files.
 *
 * Saphira edition: reads /etc/passwd, /etc/group and /etc/shadow
 * directly. No NSS, no caching daemons - the files are the database,
 * which keeps behaviour inspectable on a non-usrmerged musl system.
 *
 * Usage: getent <passwd|group|shadow> [key ...]
 * A key matches the entry name, or (passwd/group) a numeric id.
 * Exit status: 0 = at least one entry printed, 2 = none.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *dbfile(const char *db)
{
	if (strcmp(db, "passwd") == 0) return "/etc/passwd";
	if (strcmp(db, "group")  == 0) return "/etc/group";
	if (strcmp(db, "shadow") == 0) return "/etc/shadow";
	return NULL;
}

/* Print the entry whose first field equals key. name_only restricts
 * matching to the first field (used for shadow); otherwise a pure
 * numeric key also matches the third field (uid/gid). */
static int emit(FILE *f, const char *key, int name_only)
{
	char line[4096];
	int found = 0;

	rewind(f);
	while (fgets(line, sizeof line, f)) {
		char *nl = strpbrk(line, "\r\n");
		char *c1, *c3, save1, save3 = 0;
		size_t n = strlen(line);
		if (n && (line[n-1] == '\n' || line[n-1] == '\r'))
			line[n-1] = '\0';
		if (!line[0] || line[0] == '#')
			continue;
		c1 = strchr(line, ':');
		if (!c1)
			continue;
		save1 = *c1; *c1 = '\0';
		if (strcmp(line, key) == 0) {
			*c1 = save1;
			printf("%s\n", line);
			found = 1;
			continue;
		}
		if (name_only)
			continue;
		c3 = strchr(c1 + 1, ':');
		if (!c3)
			continue;
		c3 = strchr(c3 + 1, ':');
		if (!c3)
			continue;
		save3 = *c3; *c3 = '\0';
		if (strcmp(c1 + 1, key) == 0) {
			*c3 = save3;
			printf("%s\n", line);
			found = 1;
			continue;
		}
		*c3 = save3; *c1 = save1;
	}
	return found;
}

int main(int argc, char **argv)
{
	const char *file;
	FILE *f;
	int i, found = 0, name_only;

	if (argc < 2) {
		fprintf(stderr, "usage: %s {passwd|group|shadow} [key ...]\n",
			argv[0]);
		return 2;
	}
	file = dbfile(argv[1]);
	if (!file) {
		fprintf(stderr, "%s: unknown database: %s\n", argv[0], argv[1]);
		return 2;
	}
	name_only = strcmp(argv[1], "shadow") == 0;

	f = fopen(file, "r");
	if (!f) {
		fprintf(stderr, "%s: cannot open %s\n", argv[0], file);
		return 2;
	}

	if (argc == 2) {
		found = emit(f, "", 0) || found;
		/* enumerate: print every entry */
		rewind(f);
		{
			char line[4096];
			while (fgets(line, sizeof line, f))
				fputs(line, stdout);
		}
		fclose(f);
		return 0;
	}

	for (i = 2; i < argc; i++)
		found = emit(f, argv[i], name_only) || found;

	fclose(f);
	return found ? 0 : 2;
}
