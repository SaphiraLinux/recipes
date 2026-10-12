/* mod_badabi.c -- a module that declares an ABI the core does not implement.
 *
 * It exists to prove the refusal path (D2 6): the core must record it as
 * 'incompatible' WITH A CLEAR DIAGNOSTIC and must never load it
 * optimistically. It must not appear in the registry as loaded, and the TUI
 * must not gain a section for it.
 */
#include "sr_module.h"

/* No object types and no operations: this module exists only to be refused,
 * so it deliberately contributes nothing even if it ever did load. */
static const sr_module_ops ops = { 0 };

static const sr_module_descriptor descriptor = {
    .abi_version = SR_MODULE_ABI_VERSION + 99,   /* from the future */
    .name        = "badabi",
    .version     = "9.9.9",
    .summary     = "Declares an unsupported ABI; must be refused",
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
