# Local Secret-Scanning Hooks

These repository-local Bash hooks scan staged changes before commits and outgoing
commits before pushes. They complement, but do not replace, GitHub Actions secret
scanning.

## Install

From the repository root, run this once per clone:

```bash
bash .secret-scanning/install.sh
```

The installer configures this clone's `core.hooksPath` to
`.secret-scanning/hooks`. Developers need Bash, Git 2.31+ and Python 3.9+; no scanner package
installation is required.

## Behavior

- `pre-commit` scans added lines in the staged diff, including `*.example` files.
- `pre-push` scans added lines in commits from the configured upstream, or from
  the merge base with local `main` or `master` when no upstream exists.
  Commits already reachable from remote-tracking branches for the branch's
  configured remote (default: `origin`) are excluded, so merging remote `main`
  does not rescan its existing history. Fetch before scanning to refresh these
  remote-tracking refs.
  Merge commits are checked for changes unique to the merge.
- Both scanners use the same Python detector for case-insensitive credential
  field names in shell/YAML, JSON and XML, bearer headers and common token formats.
  Environment references and clearly marked placeholders are allowed.
- Both scanners report file names, new-file line numbers and field names, never
  matched credential values.
- Both scanners read Python regular expressions from `.secretscan-allowlist` at
  the repository root. Blank lines and comments are ignored. Keep false-positive
  exceptions narrow and repository-specific.
- Both hooks fail closed when a match is found.
- Detection is heuristic and complements CI scanning; it is not proof that a
  checkout, binary file or Git history contains no secrets.

## Manual Checks

```bash
bash .secret-scanning/scripts/scan-secrets-staged.sh
bash .secret-scanning/scripts/scan-secrets-range.sh
python3 -m unittest discover -s .secret-scanning/tests -v
```
