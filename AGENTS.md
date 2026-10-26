# Agent Guidelines

## Documentation Governance

Before writing, modifying, or archiving documentation, read and follow
`docs/dev/documentation/index.md`. Do not create, edit, move, or delete
files inside `docs/dev/documentation/`; propose changes there as written
recommendations for a human maintainer to apply.

## Repository Contracts

The governance rules treat these files as optional contracts. This
repository currently uses none of them:

- No `CHANGELOG.md`: changelog update rules do not apply.
- No `CONTRIBUTING.md`: contributor workflow lives in `docs/dev/` only.
- No `docs/adr/`: record architectural rationale in `docs/explanation/`.
- No `docs/reference/glossary.md`: keep terminology local to each doc.

If one of these files is added later, update this list and the matching
rules become active.

## Operational Conventions

- Treat this repository as the source of truth, and describe rather than
  automate: hosts differ, so the docs show commands a reader adapts.
  Package artifacts are the exception, shipped through two local `wright`
  plans whose copies must stay identical to the repository copies:
  `xray` (upstream binary only) and `xray-tproxy` (the solution: the four
  files under `host/client/` — unit, `/etc/nftables/xray-tproxy.nft`, sysusers
  entry, networkd template; `runtime_deps = ['xray', 'v2ray-rules-dat']`).
  A package may only carry values that do not differ per host.
- No installer scripts, timers or `/usr/libexec` helpers. Unit behaviour
  belongs in the unit (`ExecStartPre`/`ExecStartPost`/`ExecStopPost`);
  everything else is a documented command.
- One owner per kernel object: the `fwmark 1 -> table 110` policy rule
  belongs to the networkd drop-in, the `local` route in table `110` and
  both nftables tables to the unit. The unit repairs the rule, never
  removes it.
- Do not commit diagnostic reports (`xray-tproxy-diagnose-*.txt`); they
  are covered by `.gitignore`.
- Never commit `**/*.local.json` — those files carry the server address, the
  UUID and the REALITY key, and are covered by `.gitignore`. Rotate
  credentials immediately if one is ever committed.
- **Example values in a template must be obviously fake**: `REDACTED`,
  `example`, `a1b2c3d4-…`, `203.0.113.x`. A template once shipped a real
  REALITY private key inside a `<PRIVATE_KEY:…>` placeholder, and because git
  history is permanent it is still there; the key was superseded, which is the
  only reason it is not a live exposure. Treat every committed example value as
  public, because it is.
- `.gitignore` cannot protect a file git already tracks, so filling real values
  into `schemes/<scheme>/client.json` itself would be committed on the next
  `git add`. `.githooks/pre-commit` closes that path: it inspects what is
  staged, so it also catches `git add -f` and a template filled in place.
  Activate it once per clone with `git config core.hooksPath .githooks`, and
  run its test after editing it: `sh .githooks/test-pre-commit.sh`. Do not
  reach for `--no-verify` without a written reason. This is repository
  hygiene, not host automation — the rule against installer scripts and
  timers is about what runs on a deployed host.
- `host/client/xray-tproxy.nft` changes should keep the bypass semantics
  documented in `docs/reference/traffic-selection.md` in sync.
- A scheme config is complete and self-contained, so a scheme directory may
  only differ from its siblings in the outbound (`client.json`) and inbound
  (`server.json`) blocks. A change to the shared datapath — TProxy inbound,
  DNS, routing rules, policy — must be applied to **every** scheme, and each
  file must pass `xray run -test` before deploying. Keep the rule table in
  `docs/reference/client-configuration.md` in sync, including the rule order.
- The Local API inbound (`127.0.0.1:10085`) is an admin surface: never bind
  it off-loopback, and keep its routing rule first.
