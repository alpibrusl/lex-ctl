# lex-ctl — the verifier's judgement of an effect contract
#
# The verifier is a scheduled job the HOST runs — deliberately not the
# agent that proposed the action. This module is only the pure
# judgement: given a contract, the observed signal value at/after the
# deadline, and whether any other action was in flight on the same
# subsystem, produce the outcome.
#
# Ambiguity (a concurrent action confounds attribution) counts as a
# falsification: it is a scheduling bug, and it must never inflate an
# action class's hit rate.
#
# Effects: none. All functions are pure.

import "./contract" as ct

type Outcome = Pending | Materialised | Falsified | Ambiguous

fn judge(c :: ct.EffectContract, observed_milli :: Option[Int], now_ms :: Int, concurrent_on_subsystem :: Int) -> Outcome
  examples {
    judge(ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback), Some(350000), 30000, 0) => Pending,
    judge(ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback), Some(350000), 60000, 0) => Materialised,
    judge(ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback), Some(450000), 60000, 0) => Falsified,
    judge(ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback), Some(350000), 60000, 1) => Ambiguous,
    judge(ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback), None, 60000, 0) => Falsified
  }
{
  if now_ms < c.deadline_ms {
    Pending
  } else {
    if concurrent_on_subsystem > 0 {
      Ambiguous
    } else {
      match observed_milli {
        None => Falsified,
        Some(v) => if ct.holds(c.predicate, v) {
          Materialised
        } else {
          Falsified
        },
      }
    }
  }
}

# Only a clean materialisation is a hit; Ambiguous is a miss.
fn counts_as_hit(o :: Outcome) -> Bool
  examples {
    counts_as_hit(Materialised) => true,
    counts_as_hit(Falsified) => false,
    counts_as_hit(Ambiguous) => false,
    counts_as_hit(Pending) => false
  }
{
  match o {
    Materialised => true,
    _ => false,
  }
}

# Has the verifier reached a disposition?
fn is_final(o :: Outcome) -> Bool
  examples {
    is_final(Pending) => false,
    is_final(Ambiguous) => true
  }
{
  match o {
    Pending => false,
    _ => true,
  }
}

