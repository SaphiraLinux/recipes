# docbook-xsl-nons patches

Top-level `patches/`, so the builder worker applies them
automatically. Note: the recipe build is currently a no-op, so these
apply to sources that produce no payload change today; they are kept
because dropping applied patches silently is worse than carrying them.

| File | Why |
|---|---|
| `0001-stack-fix.patch` | LFS-origin EXSLT `replace`-function fix (Upstream Status: Unsure): avoids stack overflow in recursive `string.subst`. |
| `0002-old-uri-catalog.patch` | Retain historical DocBook XSL URI catalog for compatibility with v1.79.1 or earlier. |
