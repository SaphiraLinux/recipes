/* mod_fixture.c -- a deliberately boring provider module.
 *
 * Its entire job is to make the architecture testable: it declares object
 * types through describe(), and the TUI must gain a section because of that
 * alone. Installing it makes functionality APPEAR; removing it makes it
 * disappear cleanly, with no interface change (D2 8, D2 9).
 *
 * It draws nothing and emits no escape sequences -- modules describe, the
 * TUI renders (D2 4.2).
 */
#include "sr_module.h"
#include <string.h>

static const sr_field fields_demo[] = {
    { "name",     SR_FIELD_TEXT, 1, NULL, NULL, "Identifier for this object" },
    { "endpoint", SR_FIELD_ADDR, 1, NULL, NULL, "IPv4 or IPv6 literal" },
    { "port",     SR_FIELD_INT,  1, "8080", NULL, "TCP port" },
    { "weight",   SR_FIELD_WEIGHT, 0, "1", NULL, "Backend weight" },
    { "enabled",  SR_FIELD_BOOL, 0, "true", NULL, "Desired enabled state" },
    { "label",    SR_FIELD_TEXT, 0, NULL, NULL, "Optional human label" },
    { NULL, 0, 0, NULL, NULL, NULL }
};

static const sr_action actions_demo[] = {
    { "view",   SR_ACTION_VIEW,    "fixture.object.read"   },
    { "create", SR_ACTION_CREATE,  "fixture.object.write"  },
    { "edit",   SR_ACTION_EDIT,    "fixture.object.write"  },
    { "delete", SR_ACTION_DELETE,  "fixture.object.write"  },
    { NULL, 0, NULL }
};

static const sr_object_type objects[] = {
    { "fixture_object", "Fixture Object",
      fields_demo, actions_demo, "fixture" },
    { NULL, NULL, NULL, NULL, NULL }
};

static const sr_description description = {
    objects,
    (const char *const []){
        "fixture.object.read", "fixture.object.write", NULL
    }
};

static int fx_init(sr_ctx *ctx, char **err)
{
    (void)ctx; (void)err;
    return 0;
}

static int fx_describe(sr_ctx *ctx, const sr_description **out)
{
    (void)ctx;
    *out = &description;
    return 0;
}

/* Not implemented, and not advertised: the loader must refuse to call it
 * because the provides bit is absent, rather than assuming it exists. */
static int fx_render(sr_ctx *ctx, const char *object_type, const char *json,
                     char **out_text)
{
    (void)ctx; (void)json;
    *out_text = NULL;
    (void)object_type;
    return -1;
}

static const sr_module_ops ops = {
    .init     = fx_init,
    .describe = fx_describe,
    .render   = fx_render,
};

static const sr_module_descriptor descriptor = {
    .abi_version = SR_MODULE_ABI_VERSION,
    .name        = "fixture",
    .version     = "0.1.0",
    .summary     = "Fixture provider: proves describe() drives the interface",
    /* describe + init only: render is absent on purpose. */
    .provides     = SR_PROVIDES_INIT | SR_PROVIDES_DESCRIBE,
    .requires     = 0,
    .capability_requires = { NULL },
    .dependencies = NULL,
    .ops          = &ops,
};

const sr_module_descriptor *sr_module_descriptor_get(void)
{
    return &descriptor;
}
