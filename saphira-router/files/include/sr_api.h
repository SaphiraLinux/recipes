/* sr_api.h -- the single control surface (local Unix-domain IPC). */
#ifndef SR_API_H
#define SR_API_H

#include "sr.h"
#include "sr_db.h"

/* Serve until *stopflag becomes non-zero. Local, owner-private socket. */
int  sr_api_serve(sr_db *db, const char *socket_path, volatile int *stopflag);

/* Send one newline-delimited JSON request.
 *
 * OWNERSHIP: the returned reply is a malloc'd buffer the CALLER MUST free.
 * It returns NULL if the daemon is unreachable. out_code, if given, receives
 * the caller's exit-semantics code so denied/failed/partial stay
 * distinguishable (D9 4).
 *
 * This was a static buffer once, and the TUI screens freed it -- a crash the
 * interactive pty test caught and a unit test would not have. An explicit
 * ownership contract is the fix; the static buffer was the trap.
 */
char *sr_api_call(const char *socket_path, const char *req, int *out_code);

/* Convenience login. On success *out_token receives the session token.
 * The returned reply is also caller-owned. */
char *sr_api_login(const char *socket_path, const char *user, const char *pw,
                   char **out_token, int *out_code);

#endif
