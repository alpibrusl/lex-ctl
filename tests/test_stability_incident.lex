# lex-ctl tests — damping + incident working set (pure, no effects)

import "std.list" as list

import "../src/stability" as st

import "../src/incident" as inc

fn test_dwell_lock_lifecycle() -> Result[Unit, Str] {
  let locks := st.acquire([], "svc", 100)
  if not st.can_act(locks, "svc", 50, 0, 2) {
    if st.can_act(locks, "svc", 150, 0, 2) {
      if list.len(st.sweep(locks, 150)) == 0 {
        Ok(())
      } else {
        Err("expired lock survived sweep")
      }
    } else {
      Err("expired lock still blocks")
    }
  } else {
    Err("live dwell lock did not block")
  }
}

fn test_global_cap_is_independent_of_subsystem() -> Result[Unit, Str] {
  if st.can_act([], "other", 0, 1, 1) {
    Err("global cap must bind regardless of subsystem")
  } else {
    Ok(())
  }
}

fn test_hysteresis_band_walk() -> Result[Unit, Str] {
  let h := { enter_milli: 3000, exit_milli: 1000 }
  let opened := st.next_open(h, 3500, false)
  let held := st.next_open(h, 2000, true)
  let closed := st.next_open(h, 500, true)
  if opened and held and not closed {
    Ok(())
  } else {
    Err("hysteresis band walk failed")
  }
}

fn fresh_incident() -> inc.Incident {
  { id: "i1", opened_at_ms: 0, symptoms: ["svc.p99"], hypotheses: [], evidence: [], budget: { spent_milli: 0, cap_milli: 1000 }, actions: [], pending_effects: [], status: Triage }
}

fn test_incident_happy_path() -> Result[Unit, Str] {
  match inc.advance(fresh_incident(), Acting) {
    Err(m) => Err(m),
    Ok(a) => match inc.advance(a, Verifying) {
      Err(m) => Err(m),
      Ok(v) => match inc.advance(v, Resolved) {
        Err(m) => Err(m),
        Ok(_) => Ok(()),
      },
    },
  }
}

fn test_resolved_is_terminal() -> Result[Unit, Str] {
  match inc.advance(fresh_incident(), Acting) {
    Err(m) => Err(m),
    Ok(a) => match inc.advance(a, Verifying) {
      Err(m) => Err(m),
      Ok(v) => match inc.advance(v, Resolved) {
        Err(m) => Err(m),
        Ok(r) => match inc.advance(r, Acting) {
          Err(_) => Ok(()),
          Ok(_) => Err("resolved incident accepted a new transition"),
        },
      },
    },
  }
}

fn test_budget_refuses_overrun() -> Result[Unit, Str] {
  let i := fresh_incident()
  match inc.add_evidence(i, { query: "logs", cost_milli: 800, result_ref: "r1", ts_ms: 1 }) {
    Err(m) => Err(m),
    Ok(i2) => match inc.add_evidence(i2, { query: "logs", cost_milli: 300, result_ref: "r2", ts_ms: 2 }) {
      Err(_) => Ok(()),
      Ok(_) => Err("budget overrun was allowed"),
    },
  }
}

fn run_all() -> Unit {
  let results := [test_dwell_lock_lifecycle(), test_global_cap_is_independent_of_subsystem(), test_hysteresis_band_walk(), test_incident_happy_path(), test_resolved_is_terminal(), test_budget_refuses_overrun()]
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

