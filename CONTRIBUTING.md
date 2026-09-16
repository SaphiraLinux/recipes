# Contributing to Saphira recipes

Bug fixes, package updates and recipe improvements are welcome.

## The contract

`RECIPE_RULES.md` is the authoritative recipe contract. Read it before
changing any recipe; this file is only a summary for contributors.

## Pure-text public mirror

Public Git is pure-text. Do not commit source archives, firmware blobs,
built packages or secrets. Recipes must fetch publicly obtainable
upstream source (pinned URL plus checksum, per `RECIPE_RULES.md`);
reviewers will reject vendored blobs.

## What makes a good change

- Focused commits: one recipe or coherent package set per commit.
- Run the relevant local test suites before submitting, plus
  `git diff --check`.
- Adding a dependency merely because it happens to exist on the Egg
  build controller is invalid. Declare only dependencies the clean
  build root actually needs.
- Egg historical and unowned files are evidence about how v0.1 was
  built, never build inputs. Nothing is copied from the host into
  build roots.
- Never use `--force-overwrite` and never work around package file
  ownership collisions. A collision means the recipe split is wrong;
  fix the split.
- Describe the verification you performed in the pull request:
  what you built, what you tested, and what the result was.
