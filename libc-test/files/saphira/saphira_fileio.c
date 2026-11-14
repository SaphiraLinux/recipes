/* Saphira file I/O: tmpfile + named temp file round trip.
 * Hermetic: files live in TMPDIR (or /tmp) and are removed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "test.h"


int main(void)
{
	FILE *f;
	char buf[64];
	size_t n;
	long pos;

	/* tmpfile round trip */
	f = tmpfile();
	if (!f) {
		t_error("tmpfile failed\n");
		return 1;
	}
	if (fputs("hello-saphira\n", f) < 0) {
		t_error("fputs failed\n");
		return 1;
	}
	rewind(f);
	if (!fgets(buf, sizeof buf, f) || strcmp(buf, "hello-saphira\n")) {
		t_error("tmpfile content wrong: %s\n", buf);
		fclose(f);
		return 1;
	}
	pos = ftell(f);
	if (pos != 14) {
		t_error("ftell %ld\n", pos);
		fclose(f);
		return 1;
	}
	fclose(f);

	/* named temp file round trip */
	{
		char path[256];
		const char *td = getenv("TMPDIR");
		if (td && *td) {
			if (strlen(td) + 24 >= sizeof path) {
				t_error("TMPDIR too long\n");
				return 1;
			}
			strcpy(path, td);
			strcat(path, "/saphira-io-XXXXXX");
		} else {
			strcpy(path, "/tmp/saphira-io-XXXXXX");
		}
		int fd = mkstemp(path);
		if (fd < 0) {
			t_error("mkstemp failed\n");
			return 1;
		}
		f = fdopen(fd, "w+");
		if (!f) {
			t_error("fdopen failed\n");
			close(fd);
			return 1;
		}
		n = fwrite("0123456789abcdef", 1, 16, f);
		if (n != 16) {
			t_error("short fwrite\n");
			fclose(f);
			unlink(path);
			return 1;
		}
		if (fseek(f, 4, SEEK_SET)) {
			t_error("fseek failed\n");
			fclose(f);
			unlink(path);
			return 1;
		}
		n = fread(buf, 1, 4, f);
		if (n != 4 || memcmp(buf, "4567", 4)) {
			t_error("fread content wrong\n");
			fclose(f);
			unlink(path);
			return 1;
		}
		fclose(f);
		if (unlink(path)) {
			t_error("cleanup unlink failed\n");
			return 1;
		}
	}
	return t_status;
}
