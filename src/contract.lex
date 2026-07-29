# lex-ctl — effect contracts: the falsifiable prediction attached to every action
#
# The kernel's core rule: no action without a checkable expected effect.
# A contract names the signal that should move, what "moved" means (a
# typed predicate — never free text), a deadline, the agent's stated
# confidence, and what happens on falsification. The contract `id` is
# the SHA-256 of its canonical content, so the same logical prediction
# has the same id wherever it is materialized (trail-ready).
#
# Numeric convention: signal values and thresholds are integer
# milli-units (a standardized residual of 1.234 is 1234); confidence
# is an integer percentage. Integers keep content addressing exact.
#
# Effects: none. All functions are pure.

import "std.str" as str

import "std.int" as int

import "std.crypto" as crypto

type Comparator = Below | Above

type OnFalsify = Rollback | Hold | Handoff

type Predicate = { signal :: Str, cmp :: Comparator, threshold_milli :: Int }

type EffectContract = { id :: Str, action_id :: Str, class_key :: Str, subsystem :: Str, predicate :: Predicate, deadline_ms :: Int, confidence_pct :: Int, on_falsify :: OnFalsify }

fn cmp_str(c :: Comparator) -> Str
  examples {
    cmp_str(Below) => "below",
    cmp_str(Above) => "above"
  }
{
  match c {
    Below => "below",
    Above => "above",
  }
}

fn on_falsify_str(o :: OnFalsify) -> Str
  examples {
    on_falsify_str(Rollback) => "rollback",
    on_falsify_str(Handoff) => "handoff"
  }
{
  match o {
    Rollback => "rollback",
    Hold => "hold",
    Handoff => "handoff",
  }
}

# Deterministic id over the contract's content fields.
fn compute_id(action_id :: Str, class_key :: Str, subsystem :: Str, p :: Predicate, deadline_ms :: Int, confidence_pct :: Int, on_falsify :: OnFalsify) -> Str
  examples {
    compute_id("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback) => compute_id("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback)
  }
{
  crypto.sha256_str(str.join([action_id, class_key, subsystem, p.signal, cmp_str(p.cmp), int.to_str(p.threshold_milli), int.to_str(deadline_ms), int.to_str(confidence_pct), on_falsify_str(on_falsify)], "|"))
}

# Build a contract with a computed id.
fn make(action_id :: Str, class_key :: Str, subsystem :: Str, p :: Predicate, deadline_ms :: Int, confidence_pct :: Int, on_falsify :: OnFalsify) -> EffectContract
  examples {
    make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback) => { id: compute_id("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback), action_id: "a1", class_key: "restart", subsystem: "svc", predicate: { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, deadline_ms: 60000, confidence_pct: 80, on_falsify: Rollback }
  }
{
  { id: compute_id(action_id, class_key, subsystem, p, deadline_ms, confidence_pct, on_falsify), action_id: action_id, class_key: class_key, subsystem: subsystem, predicate: p, deadline_ms: deadline_ms, confidence_pct: confidence_pct, on_falsify: on_falsify }
}

# Verify a contract's id matches its content (integrity check).
fn is_valid(c :: EffectContract) -> Bool
  examples {
    is_valid(make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback)) => true
  }
{
  c.id == compute_id(c.action_id, c.class_key, c.subsystem, c.predicate, c.deadline_ms, c.confidence_pct, c.on_falsify)
}

# Does an observed value satisfy the predicate?
fn holds(p :: Predicate, observed_milli :: Int) -> Bool
  examples {
    holds({ signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 350000) => true,
    holds({ signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 450000) => false,
    holds({ signal: "err_rate", cmp: Above, threshold_milli: 1000 }, 2000) => true
  }
{
  match p.cmp {
    Below => observed_milli < p.threshold_milli,
    Above => observed_milli > p.threshold_milli,
  }
}

