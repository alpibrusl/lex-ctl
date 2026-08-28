# lex-ctl

**Part of the [Lex](https://lexlang.org) project** — Library · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

Controller kernel for agentic systems: **no action without a checkable
predicted effect.** Effect contracts with deadlines, autonomy tiers earned
from measured hit rate, and the damping primitives (dwell locks, hysteresis,
circuit breaker) that keep an agent from oscillating the system it acts on.

Pure Lex, mechanism only. The kernel ships no action vocabulary, no
thresholds, no baselines and no scheduler — hosts supply policy and wiring.
Design source: *The Agentic Control Surface*
([lex-loom#118](https://github.com/alpibrusl/lex-loom/issues/118)); the
Lex-native port lands as `lex-loom/docs/design/operate-loop.md`.

## The loop it encodes

```
sensing (residuals) → incident object → capability gate → typed actuation
        ▲                                                      │
        └────────── verifier (scheduled, not the agent) ◀──────┘
                    materialised | falsified | ambiguous → ledger
```

Every action carries an `EffectContract` — the signal that should move, a
typed predicate for what "moved" means, a deadline, stated confidence, and
what happens on falsification. The verifier's dispositions accumulate into
per-action-class hit rates, and those measured records are the only thing
that promotes a class to autonomous execution. Ambiguity (a concurrent
action confounds attribution) counts as falsification.

## Modules

| module | purpose |
|---|---|
| `lex-ctl/contract` | `EffectContract` + typed `Predicate`, content-addressed ids, integrity check |
| `lex-ctl/verify` | the verifier's pure judgement: `Pending / Materialised / Falsified / Ambiguous`; ambiguous = miss |
| `lex-ctl/tier` | action classes (reversibility × blast × dwell), structural ceilings, hit-rate promotion, circuit breaker |
| `lex-ctl/stability` | dwell locks per subsystem, global concurrency cap, asymmetric hysteresis |
| `lex-ctl/incident` | the incident working set: calibrated hypotheses, budgeted evidence, exhaustive status FSM |

Numeric convention: signal values/thresholds are integer **milli-units**
(a standardized residual of 1.234 is `1234`), posteriors and confidence are
integer **percent**. Integers keep content addressing exact.

## Consumers

- **lex-loom** — the Operate loop v1 controller
  ([epic lex-loom#118](https://github.com/alpibrusl/lex-loom/issues/118),
  kernel extraction [lex-loom#126](https://github.com/alpibrusl/lex-loom/issues/126)).
- **lex-soft** — forward-looking verdicts for domain-pack actions
  ([lex-soft#106](https://github.com/alpibrusl/lex-soft/issues/106)).

Planned integrations (with the first real consumer): contracts and
dispositions recorded as [lex-trail](https://github.com/alpibrusl/lex-trail)
events; tier decisions feeding
[lex-agent](https://github.com/alpibrusl/lex-agent) capability gates.

## Development

```sh
lex check --strict src/
lex fmt --check src/ tests/
lex test tests/
```

## License

Copyright (c) 2026 lex-ctl contributors.

Licensed under the [EUPL-1.2](LICENSE) — the European Union Public Licence, as used across the `lex-*` ecosystem.
