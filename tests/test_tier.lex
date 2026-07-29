# lex-ctl tests — autonomy earned from measured record (pure, no effects)

import "std.list" as list

import "../src/tier" as tr

fn restart_class() -> tr.ActionClass {
  { key: "restart", reversibility: Idempotent, blast: Instance, dwell_ms: 60000 }
}

fn policy() -> tr.Policy {
  { min_samples: 30, min_hit_rate_pct: 70, breaker_misses: 3 }
}

fn after(outcomes :: List[Bool]) -> tr.ClassStats {
  list.fold(outcomes, tr.empty_stats(), fn (s :: tr.ClassStats, hit :: Bool) -> tr.ClassStats {
    tr.record(s, hit)
  })
}

fn n_hits(n :: Int) -> List[Bool] {
  if n == 0 {
    []
  } else {
    list.cons(true, n_hits(n - 1))
  }
}

fn test_no_promotion_without_samples() -> Result[Unit, Str] {
  match tr.effective(restart_class(), tr.empty_stats(), policy()) {
    Propose => Ok(()),
    _ => Err("an unproven class must sit at Propose"),
  }
}

fn test_promotion_at_measured_hit_rate() -> Result[Unit, Str] {
  match tr.effective(restart_class(), after(n_hits(30)), policy()) {
    Auto => Ok(()),
    _ => Err("30/30 hits should earn Auto"),
  }
}

fn test_breaker_demotes_despite_history() -> Result[Unit, Str] {
  let s := after(list.concat(n_hits(30), [false, false, false]))
  match tr.effective(restart_class(), s, policy()) {
    Propose => Ok(()),
    _ => Err("3 consecutive misses must trip the breaker"),
  }
}

fn test_hit_resets_breaker() -> Result[Unit, Str] {
  let s := after(list.concat(n_hits(30), [false, false, true]))
  match tr.effective(restart_class(), s, policy()) {
    Auto => Ok(()),
    _ => Err("a hit resets the consecutive-miss counter"),
  }
}

fn test_structural_ceiling_ignores_record() -> Result[Unit, Str] {
  let irreversible := { key: "migrate", reversibility: Irreversible, blast: Instance, dwell_ms: 60000 }
  match tr.effective(irreversible, after(n_hits(1000)), policy()) {
    Escalate => Ok(()),
    _ => Err("no record may lift an irreversible class above Escalate"),
  }
}

fn run_all() -> Unit {
  let results := [test_no_promotion_without_samples(), test_promotion_at_measured_hit_rate(), test_breaker_demotes_despite_history(), test_hit_resets_breaker(), test_structural_ceiling_ignores_record()]
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __discard := 1 / 0
    ()
  }
}

