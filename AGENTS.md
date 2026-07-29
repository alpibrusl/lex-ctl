# lex-ctl — Agent Guidelines

Controller kernel for agentic systems. Pure Lex + stdlib only
(`std.str`, `std.int`, `std.list`, `std.crypto`). No Rust, no I/O.

Read `lex agent-guidelines` in full before writing code. The four
highest-leverage discipline rules:

1. **Narrow effects, always.** This package is entirely pure — every
   `fn` here has an empty effect set. If a change seems to need an
   effect, it belongs in a host (lex-loom, lex-soft), not here.
2. **Repair, don't regenerate.** `lex --output json check` →
   `lex repair --apply`. Only regenerate after two failed repairs.
3. **`examples {}` blocks on every pure fn.** They fold into the SigId
   and run at `lex check` time.
4. **Use the stdlib.** `std.crypto` for hashing, `std.list` folds over
   hand-rolled recursion where possible.

## The loop

```sh
lex check --strict src/
lex fmt --check src/ tests/
lex test tests/
```

## Project-specific overrides — lex-ctl

- **Mechanism only, never policy.** No action vocabulary, no default
  thresholds, no baselines, no scheduler. Hosts supply all of those.
  Nothing loom- or soft-specific may appear here (no "company",
  "sprint", "settlement", "pack").
- **Integer units are load-bearing.** Signal values and thresholds are
  integer milli-units; posteriors/confidence are integer percent.
  Contract ids are SHA-256 over canonical content — introducing floats
  would break content addressing. Don't.
- **Ambiguous = falsified.** `verify.judge` returning `Ambiguous` must
  never count as a hit anywhere. This is the anti-confounding
  invariant; treat it like a type-system rule.
- **Ceilings are structural.** `tier.ceiling` consults only the action
  classification. No measured record, argument, or narrative may lift
  a class above its ceiling — only demote below it.
- **The kernel never self-resets a tripped breaker.** Recovery is the
  host's decision (manual or shadow re-qualification).
- **The status FSM is exhaustive.** Extend `incident.legal_move` and
  its examples together; never bypass `advance` by rebuilding a record
  with a different `status`.
- **Predicates are typed, never strings.** Extending `Predicate` means
  a coordinated change with `contract.compute_id` (id coverage) and
  `verify.judge` — all three or none.
