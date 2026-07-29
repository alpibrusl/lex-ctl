# lex-ctl tests — contract integrity + verifier judgement (pure, no effects)

import "std.list" as list

import "../src/contract" as ct

import "../src/verify" as vf

fn test_contract_id_deterministic() -> Result[Unit, Str] {
  let p := { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }
  let a := ct.make("a1", "restart", "svc", p, 60000, 80, Rollback)
  let b := ct.make("a1", "restart", "svc", p, 60000, 80, Rollback)
  if a.id == b.id {
    Ok(())
  } else {
    Err("same content produced different ids")
  }
}

fn test_contract_id_covers_predicate() -> Result[Unit, Str] {
  let a := ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback)
  let b := ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 500000 }, 60000, 80, Rollback)
  if a.id != b.id {
    Ok(())
  } else {
    Err("different thresholds produced same id")
  }
}

fn test_tampered_contract_invalid() -> Result[Unit, Str] {
  let a := ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback)
  let tampered := { id: a.id, action_id: a.action_id, class_key: a.class_key, subsystem: a.subsystem, predicate: a.predicate, deadline_ms: a.deadline_ms, confidence_pct: 99, on_falsify: a.on_falsify }
  if ct.is_valid(a) and not ct.is_valid(tampered) {
    Ok(())
  } else {
    Err("tampering was not detected")
  }
}

fn test_ambiguity_is_a_miss() -> Result[Unit, Str] {
  let c := ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback)
  let o := vf.judge(c, Some(350000), 60000, 1)
  if vf.is_final(o) and not vf.counts_as_hit(o) {
    Ok(())
  } else {
    Err("a confounded verification must count as a miss")
  }
}

fn test_missing_signal_is_falsified() -> Result[Unit, Str] {
  let c := ct.make("a1", "restart", "svc", { signal: "p99_ms", cmp: Below, threshold_milli: 400000 }, 60000, 80, Rollback)
  match vf.judge(c, None, 60000, 0) {
    Falsified => Ok(()),
    _ => Err("an unobservable prediction must be falsified"),
  }
}

fn run_all() -> Unit {
  let results := [test_contract_id_deterministic(), test_contract_id_covers_predicate(), test_tampered_contract_invalid(), test_ambiguity_is_a_miss(), test_missing_signal_is_falsified()]
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

