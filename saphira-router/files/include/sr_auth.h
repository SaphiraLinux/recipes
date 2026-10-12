/* sr_auth.h -- Argon2id authentication and sessions. */
#ifndef SR_AUTH_H
#define SR_AUTH_H

#include "sr.h"
#include "sr_db.h"

int sr_auth_create_user(sr_db *db, const char *username, const char *pw,
                        char **out_id, char **err);
int sr_auth_set_password(sr_db *db, const char *user_id, const char *pw,
                         char **err);

/* Returns SR_OK and the user's id + default tenant, or SR_ERR_DENIED.
 * A missing user and a wrong password are both denied identically. */
int sr_auth_verify(sr_db *db, const char *username, const char *pw,
                   char **out_user_id, char **out_tenant_id, char **err);

int sr_auth_session_create(sr_db *db, const char *user_id, const char *tenant_id,
                           const char *source_addr, char **out_token,
                           char **out_session_id, char **err);
int sr_auth_session_lookup(sr_db *db, const char *token,
                           char **out_user_id, char **out_tenant_id,
                           char **out_session_id);

#endif
