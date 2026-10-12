/* auth.c -- Argon2id password hashing and session-scoped identity.
 *
 * Argon2id only, via the packaged reference implementation. No plaintext
 * storage, no reversible passwords, no application-rolled hash (D3 3).
 */

#include "sr_auth.h"
#include "sr_db.h"

#include <argon2.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Argon2id parameters. A floor exists so a stored credential whose
 * parameters fall below it is rejected and must be re-registered (D3 3). */
#define SR_ARGON2_T_COST 3
#define SR_ARGON2_M_COST (64 * 1024)   /* 64 MiB */
#define SR_ARGON2_P_COST 2
#define SR_ARGON2_SALT_LEN 16
#define SR_ARGON2_HASH_LEN 32
#define SR_ARGON2_FLOOR_M_COST (8 * 1024)
#define SR_ARGON2_MAX_ATTEMPTS 5
#define SR_ARGON2_LOCK_SECONDS 300

/* PHC encoding and verification are delegated to the packaged reference
 * implementation rather than hand-rolled: argon2id_hash_encoded produces the
 * canonical string and argon2id_verify checks it in constant time. */
static int hash_password(const char *pw, char **out_encoded)
{
    size_t need = argon2_encodedlen(SR_ARGON2_T_COST, SR_ARGON2_M_COST,
                                    SR_ARGON2_P_COST, SR_ARGON2_SALT_LEN,
                                    SR_ARGON2_HASH_LEN, Argon2_id);
    if (need < 32 || need > 1024) return -1;

    char *enc = malloc(need);
    if (!enc) return -1;

    /* The reference implementation does not generate a salt for us, so we
     * supply one from the kernel CSPRNG. Everything else -- PHC encoding,
     * base64, padding -- is still the reference implementation's job, so we
     * never hand-roll an encoding. */
    unsigned char salt[SR_ARGON2_SALT_LEN];
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f) { free(enc); return -1; }
    if (fread(salt, 1, sizeof salt, f) != sizeof salt) {
        fclose(f); free(enc); return -1;
    }
    fclose(f);

    int rc = argon2id_hash_encoded(SR_ARGON2_T_COST, SR_ARGON2_M_COST,
                                   SR_ARGON2_P_COST, pw, strlen(pw),
                                   salt, sizeof salt,
                                   SR_ARGON2_HASH_LEN, enc, need);
    explicit_bzero(salt, sizeof salt);
    if (rc != ARGON2_OK) {
        sr_log(SR_LOG_ERROR, "argon2id_hash_encoded failed: %s",
               argon2_error_message(rc));
        free(enc);
        return -1;
    }
    *out_encoded = enc;
    return 0;
}

/* Returns 1 match, 0 no match, -1 malformed or below the cost floor. */
static int verify_password(const char *pw, const char *encoded)
{
    if (!encoded || strncmp(encoded, "$argon2id$", 10) != 0) return -1;

    /* Enforce the parameter floor: a stored credential below it is rejected
     * outright rather than verified, so it must be re-registered (D3 3). */
    unsigned t = 0, m = 0, p = 0;
    if (sscanf(encoded, "$argon2id$v=19$m=%u,t=%u,p=%u$", &m, &t, &p) != 3)
        return -1;
    if (m < (unsigned)SR_ARGON2_FLOOR_M_COST) return -1;

    int rc = argon2id_verify(encoded, pw, strlen(pw));
    if (rc == ARGON2_OK) return 1;
    if (rc == ARGON2_VERIFY_MISMATCH) return 0;
    return -1; /* malformed */
}

int sr_auth_set_password(sr_db *db, const char *user_id, const char *pw,
                         char **err)
{
    char *encoded = NULL;
    if (hash_password(pw, &encoded) < 0) {
        if (err) *err = sr_xstrdup("password hashing failed");
        return -1;
    }
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "UPDATE app_user SET password_hash=?, password_algo='argon2id',"
        " updated_at=datetime('now') WHERE id=?;", &st, err) < 0) {
        free(encoded);
        return -1;
    }
    sqlite3_bind_text(st, 1, encoded, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, user_id, -1, SQLITE_STATIC);
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    /* Zero the plaintext-adjacent buffer before releasing it. */
    explicit_bzero(encoded, strlen(encoded));
    free(encoded);
    return rc == SQLITE_DONE ? 0 : -1;
}

int sr_auth_verify(sr_db *db, const char *username, const char *pw,
                   char **out_user_id, char **out_tenant_id, char **err)
{
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "SELECT id, password_hash, failed_attempts, locked_until "
        "FROM app_user WHERE username=? AND status='active';",
        &st, err) < 0) return -1;

    sqlite3_bind_text(st, 1, username, -1, SQLITE_STATIC);
    if (sqlite3_step(st) != SQLITE_ROW) {
        sqlite3_finalize(st);
        return SR_ERR_DENIED; /* no user: deny, do not distinguish */
    }
    char *uid = sr_xstrdup((const char *)sqlite3_column_text(st, 0));
    /* sqlite3_column_text returns storage owned by the statement, so the
     * hash MUST be copied before finalize. Reading it afterwards would be a
     * use-after-free that happens to work often enough to be dangerous. */
    const unsigned char *enc_p = sqlite3_column_text(st, 1);
    char *enc = enc_p ? sr_xstrdup((const char *)enc_p) : NULL;
    int fails = sqlite3_column_int(st, 2);
    const unsigned char *locked_p = sqlite3_column_text(st, 3);
    char *locked = locked_p ? sr_xstrdup((const char *)locked_p) : NULL;
    sqlite3_finalize(st);

    if (locked && locked[0]) {
        char now[32];
        time_t t = time(NULL);
        struct tm tm; gmtime_r(&t, &tm);
        strftime(now, sizeof now, "%Y-%m-%dT%H:%M:%SZ", &tm);
        if (strcmp(now, locked) < 0) {
            free(uid); free(enc); free(locked);
            return SR_ERR_DENIED;
        }
    }
    free(locked);

    int ok = enc ? verify_password(pw, enc) : -1;
    if (ok != 1) {
        fails++;
        sqlite3_stmt *up = NULL;
        if (sr_db_prepare(db,
            "UPDATE app_user SET failed_attempts=?, "
            "locked_until=CASE WHEN ?>=? THEN datetime('now',?) ELSE locked_until END "
            "WHERE id=?;", &up, NULL) == 0) {
            sqlite3_bind_int(up, 1, fails);
            sqlite3_bind_int(up, 2, SR_ARGON2_MAX_ATTEMPTS);
            sqlite3_bind_int(up, 3, SR_ARGON2_MAX_ATTEMPTS);
            sqlite3_bind_text(up, 4, SR_ARGON2_LOCK_SECONDS ? "300 seconds" : "", -1, SQLITE_STATIC);
            sqlite3_bind_text(up, 5, uid, -1, SQLITE_STATIC);
            sqlite3_step(up);
            sqlite3_finalize(up);
        }
        free(uid);
        if (enc) { explicit_bzero(enc, strlen(enc)); free(enc); }
        return SR_ERR_DENIED;
    }
    if (enc) { explicit_bzero(enc, strlen(enc)); free(enc); }

    /* Pick the default tenant context. This MUST be a bound statement:
     * sr_db_query_text() cannot bind parameters, so using it here would
     * read an unbound column as NULL and deny every login. */
    char *tid = NULL;
    sqlite3_stmt *ts = NULL;
    if (sr_db_prepare(db,
            "SELECT tenant_id FROM user_role WHERE user_id=? "
            "ORDER BY tenant_id LIMIT 1;", &ts, err) < 0) {
        free(uid);
        return -1;
    }
    sqlite3_bind_text(ts, 1, uid, -1, SQLITE_STATIC);
    if (sqlite3_step(ts) == SQLITE_ROW) {
        const unsigned char *t = sqlite3_column_text(ts, 0);
        if (t) tid = sr_xstrdup((const char *)t);
    }
    sqlite3_finalize(ts);
    if (!tid) {
        /* A correct password but no tenant context: the user cannot act, so
         * this is a denial, not a success with an empty context. */
        free(uid);
        return SR_ERR_DENIED;
    }
    *out_user_id = uid;
    *out_tenant_id = tid;
    return SR_OK;
}

int sr_auth_create_user(sr_db *db, const char *username, const char *pw,
                        char **out_id, char **err)
{
    char id[SR_MAX_ID];
    sr_gen_id(id, sizeof id);
    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO app_user(id,username,password_hash,password_algo,"
        "created_at,updated_at) VALUES(?,?,'!','argon2id',datetime('now'),datetime('now'));",
        &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, username, -1, SQLITE_STATIC);
    if (sqlite3_step(st) != SQLITE_DONE) { sqlite3_finalize(st);
        if (err) *err = sr_xstrdup("cannot create user (duplicate username?)");
        return -1; }
    sqlite3_finalize(st);

    if (sr_auth_set_password(db, id, pw, err) < 0) return -1;
    *out_id = sr_xstrdup(id);
    return 0;
}

/* ------------------------------------------------------- sessions */

/* Session tokens: 256 bits of entropy, returned once in plaintext and
 * stored only as a SHA-256 hash, so a database read does not yield usable
 * tokens (D3 3). Sessions are bound to (user, tenant). */
static void sha256_hex(const char *in, char out[65])
{
    unsigned char md[EVP_MAX_MD_SIZE];
    EVP_Digest(in, strlen(in), md, NULL, EVP_sha256(), NULL);
    static const char hx[] = "0123456789abcdef";
    for (unsigned i = 0; i < 32u; i++) {   /* SHA-256 -> 32 bytes */
        out[i * 2]     = hx[md[i] >> 4];
        out[i * 2 + 1] = hx[md[i] & 0xf];
    }
    out[64] = '\0';
}

int sr_auth_session_create(sr_db *db, const char *user_id, const char *tenant_id,
                           const char *source_addr, char **out_token,
                           char **out_session_id, char **err)
{
    char token[65];
    sr_gen_id(token, sizeof token);      /* 128 bits */
    char token2[65];
    sr_gen_id(token2, sizeof token2);    /* 128 bits */
    char full[130];
    snprintf(full, sizeof full, "%s%s", token, token2);

    char hash[65];
    sha256_hex(full, hash);

    char sid[SR_MAX_ID];
    sr_gen_id(sid, sizeof sid);

    sqlite3_stmt *st = NULL;
    if (sr_db_prepare(db,
        "INSERT INTO session(id,user_id,tenant_id,token_hash,source_addr,"
        "created_at,expires_at,last_seen_at) "
        "VALUES(?,?,?,?,?,datetime('now'),datetime('now','+8 hours'),datetime('now'));",
        &st, err) < 0) return -1;
    sqlite3_bind_text(st, 1, sid, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 2, user_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 3, tenant_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(st, 4, hash, -1, SQLITE_STATIC);
    if (source_addr) sqlite3_bind_text(st, 5, source_addr, -1, SQLITE_STATIC);
    else sqlite3_bind_null(st, 5);
    if (sqlite3_step(st) != SQLITE_DONE) {
        char *m = sr_xstrdup(sqlite3_errmsg(sr_db_handle(db)));
        sqlite3_finalize(st);
        if (err) *err = m; else free(m);
        return -1;
    }
    sqlite3_finalize(st);

    *out_token = sr_xstrdup(full);
    *out_session_id = sr_xstrdup(sid);
    return 0;
}

int sr_auth_session_lookup(sr_db *db, const char *token,
                           char **out_user_id, char **out_tenant_id,
                           char **out_session_id)
{
    sqlite3_stmt *st = NULL;
    *out_user_id = *out_tenant_id = *out_session_id = NULL;
    if (sr_db_prepare(db,
        "SELECT s.id, s.user_id, s.tenant_id FROM session s "
        "JOIN app_user u ON u.id=s.user_id "
        "WHERE s.token_hash=? AND s.revoked_at IS NULL "
        "AND s.expires_at > datetime('now') AND u.status='active';",
        &st, NULL) < 0) return -1;
    char hash[65];
    sha256_hex(token, hash);
    sqlite3_bind_text(st, 1, hash, -1, SQLITE_STATIC);
    int rc = -1;
    if (sqlite3_step(st) == SQLITE_ROW) {
        *out_session_id = sr_xstrdup((const char *)sqlite3_column_text(st, 0));
        *out_user_id    = sr_xstrdup((const char *)sqlite3_column_text(st, 1));
        *out_tenant_id  = sr_xstrdup((const char *)sqlite3_column_text(st, 2));
        rc = 0;
    }
    sqlite3_finalize(st);
    return rc;
}
