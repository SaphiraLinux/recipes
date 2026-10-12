/* sr_module.h -- saphira-router module ABI, version 1.
 *
 * This is the contract from D2. A module exports exactly one symbol:
 *
 *     const sr_module_descriptor *sr_module_descriptor_get(void);
 *
 * Everything a module touches in the core is opaque: modules receive no
 * database handle and are given service function tables instead (see
 * sr_ctx below). The supported path for authority, state, secrets and
 * audit is core-mediated; see docs/03-security-model.md section 2.
 *
 * IMPORTANT, restated so nobody misreads it: an in-process .so is trusted
 * first-party code sharing the core process. It is NOT a sandbox. A
 * malicious or buggy module can reach memory, syscalls and files. The ABI
 * makes the core-mediated path the supported and only-documented one; it
 * does not, and cannot, make in-process isolation.
 */

#ifndef SR_MODULE_H
#define SR_MODULE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------- ABI */

#define SR_MODULE_ABI_VERSION 1

/* Capability bits: what a module actually provides. Declared, not assumed.
 * A consumer MUST check these before calling an operation. */
enum {
    SR_PROVIDES_INIT     = 1ull << 0,
    SR_PROVIDES_SHUTDOWN = 1ull << 1,
    SR_PROVIDES_DESCRIBE = 1ull << 2,  /* the declarative description layer  */
    SR_PROVIDES_VALIDATE = 1ull << 3,
    SR_PROVIDES_DISCOVER = 1ull << 4,
    SR_PROVIDES_OBSERVE  = 1ull << 5,
    SR_PROVIDES_RENDER   = 1ull << 6,
    SR_PROVIDES_STAGE    = 1ull << 7,
    SR_PROVIDES_APPLY    = 1ull << 8,
    SR_PROVIDES_VERIFY   = 1ull << 9,
    SR_PROVIDES_ROLLBACK = 1ull << 10
};

/* Host capabilities a module requires to be useful. These are *capability
 * names* (matching host_capability.capability in the DB), not ABI bits. */
typedef struct {
    const char *const *names;   /* NULL-terminated */
} sr_capability_requires;

/* ------------------------------------------------------- value passing
 *
 * Values cross the boundary as data, never as core pointers. sr_value is a
 * small tagged union; no ownership transfers -- strings are borrowed for the
 * duration of the call.
 */
typedef enum {
    SR_VAL_NONE = 0,
    SR_VAL_STR,
    SR_VAL_INT,
    SR_VAL_BOOL,
    SR_VAL_LIST,
    SR_VAL_MAP,
    SR_VAL_SECREF   /* a reference to a secret, never its value */
} sr_value_type;

typedef struct sr_value {
    sr_value_type type;
    const char    *key;      /* for map entries */
    const char    *sval;     /* SR_VAL_STR, SR_VAL_SECREF, serialized SR_VAL_LIST/MAP */
    int64_t        ival;     /* SR_VAL_INT */
    int            bval;     /* SR_VAL_BOOL */
    size_t         count;    /* SR_VAL_LIST element count */
} sr_value;

/* ------------------------------------------------- description layer
 *
 * describe() is DATA, not drawing. A module declares object types, their
 * fields, and the actions available on them. The TUI renders generically.
 * Modules must not draw terminal UI or emit escape sequences (D2 4.2).
 */

/* How a field should be presented. A generic renderer honours these. */
typedef enum {
    SR_FIELD_TEXT = 0,
    SR_FIELD_INT,
    SR_FIELD_BOOL,
    SR_FIELD_ENUM,
    SR_FIELD_ADDR,        /* an address (v4 or v6 literal) */
    SR_FIELD_ADDR_PAIR,   /* separate v4/v6 columns */
    SR_FIELD_WEIGHT,      /* integer with weight semantics */
    SR_FIELD_SECREF       /* reference to a secret; never render a value */
} sr_field_kind;

typedef struct {
    const char    *name;
    sr_field_kind  kind;
    int            required;
    const char    *default_value;  /* NULL if none */
    const char    *enum_values;    /* comma-separated for SR_FIELD_ENUM */
    const char    *help;
} sr_field;

typedef enum {
    SR_ACTION_VIEW = 0,
    SR_ACTION_CREATE,
    SR_ACTION_EDIT,
    SR_ACTION_DELETE,
    SR_ACTION_VALIDATE,
    SR_ACTION_PROVIDER   /* module-specific verb */
} sr_action_kind;

typedef struct {
    const char    *name;
    sr_action_kind kind;
    const char    *capability;   /* required capability code to invoke */
} sr_action;

/* One object type a module contributes. */
typedef struct {
    const char  *type;        /* e.g. "haproxy_frontend" */
    const char  *label;       /* human label for the TUI, e.g. "HAProxy Frontend" */
    const sr_field *fields;   /* NULL-terminated by name==NULL */
    const sr_action *actions; /* NULL-terminated by name==NULL */
    const char  *section;     /* TUI section it appears under, e.g. "haproxy" */
} sr_object_type;

/* The description a module contributes, gathered by describe(). */
typedef struct {
    const sr_object_type *objects;  /* NULL-terminated by type==NULL */
    const char *const *capability_codes; /* NULL-terminated; may be NULL */
} sr_description;

/* ------------------------------------------------------- core services
 *
 * Handed to a module at init(). These are the ONLY sanctioned routes to
 * authority, state, secrets, audit and the module registry. There is
 * deliberately no sqlite3* anywhere in this struct.
 */
typedef struct sr_ctx {
    /* Authorization: check a capability for the calling actor/tenant. */
    int (*authorize)(void *ctx, const char *capability, const char **reason);

    /* Desired state (core-mediated; the only supported way to change it). */
    int (*state_get)(void *ctx, const char *object_type, const char *object_id,
                     char **out_json, int *out_len);
    int (*state_put)(void *ctx, const char *object_type, const char *object_id,
                     const char *desired_json);

    /* Observed state, written with provenance. */
    int (*observe_put)(void *ctx, const char *object_type, const char *object_id,
                       const char *health, const char *source,
                       const char *observed_json);

    /* Audit. */
    int (*audit)(void *ctx, const char *action, const char *object_type,
                 const char *object_id, const char *outcome);

    /* Secrets: returns a REFERENCE, never a plaintext value. */
    int (*secret_ref)(void *ctx, const char *kind, const char *name,
                      char **out_ref);

    /* Contribution to the description layer consumed by the TUI. */
    int (*register_description)(void *ctx, const sr_description *desc);

    /* Host capability probe result, as recorded by discovery. */
    int (*host_capability)(void *ctx, const char *host_id, const char *capability,
                           char *out_state /* sr_capability_state */);

    /* Structured logging into the event system. */
    void (*log)(void *ctx, int level, const char *fmt, ...);

    /* Opaque core handle, for the functions above only. */
    void *core;
} sr_ctx;

/* ------------------------------------------------- operation signatures
 *
 * Not every module implements every operation; the descriptor's provides
 * mask says which. A module that does not provide an operation must not
 * advertise it, and the core must refuse to call it with a clear error.
 */
typedef struct sr_module_ops {
    int (*init)(sr_ctx *ctx, char **err);
    void (*shutdown)(sr_ctx *ctx);

    /* Gather the module's declarative description. */
    int (*describe)(sr_ctx *ctx, const sr_description **out);

    int (*validate)(sr_ctx *ctx, const char *object_type, const char *json,
                    char **report);
    int (*discover)(sr_ctx *ctx, const char *host_id);
    int (*observe)(sr_ctx *ctx, const char *host_id, char **out_json);
    int (*render)(sr_ctx *ctx, const char *object_type, const char *json,
                  char **out_text);
    int (*stage)(sr_ctx *ctx, const char *host_id, const char *text);
    int (*apply)(sr_ctx *ctx, const char *host_id);
    int (*verify)(sr_ctx *ctx, const char *host_id, char **report);
    int (*rollback)(sr_ctx *ctx, const char *host_id);
} sr_module_ops;

/* ---------------------------------------------------------- descriptor */

typedef struct sr_module_descriptor {
    uint32_t           abi_version;   /* must equal SR_MODULE_ABI_VERSION */
    const char        *name;          /* "haproxy", "ovs", "gredist", ... */
    const char        *version;
    const char        *summary;       /* one line, shown by the TUI */
    uint64_t           provides;      /* SR_PROVIDES_* mask */
    uint64_t           requires;      /* reserved for module-level requires */
    sr_capability_requires capability_requires; /* host capability names */
    const char *const *dependencies;  /* other module names, NULL-term, or NULL */
    const sr_module_ops *ops;
} sr_module_descriptor;

/* Capability states, matching host_capability.state in the DB (D6 3).
 * A capability is granted at the highest state actually proven by a direct
 * feature probe -- never inferred from a proxy signal. */
typedef enum {
    SR_CAP_UNESTABLISHED = 0, /* no probe was run            */
    SR_CAP_UNAVAILABLE,       /* probed: definitively absent */
    SR_CAP_INSTALLED,         /* package present             */
    SR_CAP_AVAILABLE,         /* service can be invoked      */
    SR_CAP_USABLE,            /* the specific feature works  */
    SR_CAP_HEALTHY            /* running and responding      */
} sr_capability_state;

const char *sr_capability_state_name(sr_capability_state s);

/* The single exported symbol every module must provide. */
typedef const sr_module_descriptor *(*sr_module_descriptor_get_fn)(void);

#ifdef __cplusplus
}
#endif

#endif /* SR_MODULE_H */
