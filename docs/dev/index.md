# Contributor Documentation

Contributor-only documentation. User documentation lives under
`docs/how-to/`, `docs/reference/`, and `docs/explanation/`; do not mix the
two.

## Pages

| Page | Purpose |
|------|---------|
| [Project Layout](project-layout.md) | Repository tree map and where new files go |
| [Documentation Governance](documentation/index.md) | Rules for organizing, writing, and reviewing docs |

## Notes

- Verifying a running deployment is manual; see
  [How to Verify the Setup](../how-to/verify-the-setup.md). The one automated
  check in the repository is the commit guard's own test,
  `sh .githooks/test-pre-commit.sh`.
- Activate the commit guard once per clone:
  `git config core.hooksPath .githooks`. It refuses a commit that would leak
  host-specific values; see [Project Layout](project-layout.md#tree-map).
- The repository has no release process yet; deployments are done by hand
  with `sudo install ...` followed by a service restart.
