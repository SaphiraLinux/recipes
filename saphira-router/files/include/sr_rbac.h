/* sr_rbac.h -- explicit, namespaced, deny-by-default capabilities.
 *
 * Authorization NEVER inspects a role name. The check is always "is this
 * capability in the effective set for (user, tenant)?" (D5 3).
 */
#ifndef SR_RBAC_H
#define SR_RBAC_H

#include "sr.h"
#include "sr_db.h"

/* 1 = allowed, 0 = denied. *reason is a malloc'd explanation, or NULL. */
int sr_rbac_authorize(sr_db *db, const char *user_id, const char *tenant_id,
                      const char *capability, char **reason);

int sr_rbac_grant(sr_db *db, const char *role_id, const char *capability,
                  char **err);
int sr_rbac_revoke(sr_db *db, const char *role_id, const char *capability,
                   char **err);

int sr_rbac_create_role(sr_db *db, const char *tenant_id, const char *name,
                        const char *description, char **out_id, char **err);
int sr_rbac_assign(sr_db *db, const char *user_id, const char *role_id,
                   const char *tenant_id, char **err);

/* Count of capabilities in the effective set, for tests and diagnostics. */
int sr_rbac_effective_count(sr_db *db, const char *user_id,
                            const char *tenant_id);

#endif
