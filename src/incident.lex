# lex-ctl — the incident object: the controller's working set
#
# The agent never re-reads the firehose; it reads and writes one
# structured object. Hypotheses carry explicit numeric posteriors so
# a wrong diagnosis is measurable rather than deniable, and evidence
# acquisition is budgeted — exhausting the budget without confidence
# is a SENSING gap (escalate and log it), not an agent defect.
#
# Numeric convention: posteriors are integer percent, costs are
# integer milli-units of the host's budget currency.
#
# Effects: none. All functions are pure.

import "std.list" as list

import "std.str" as str

type Status = Triage | Acting | Verifying | Resolved | Escalated

type Hypothesis = { cause :: Str, p_pct :: Int, evidence_for :: List[Str], evidence_against :: List[Str] }

type Evidence = { query :: Str, cost_milli :: Int, result_ref :: Str, ts_ms :: Int }

type Budget = { spent_milli :: Int, cap_milli :: Int }

type Incident = { id :: Str, opened_at_ms :: Int, symptoms :: List[Str], hypotheses :: List[Hypothesis], evidence :: List[Evidence], budget :: Budget, actions :: List[Str], pending_effects :: List[Str], status :: Status }

fn status_str(s :: Status) -> Str
  examples {
    status_str(Triage) => "triage",
    status_str(Escalated) => "escalated"
  }
{
  match s {
    Triage => "triage",
    Acting => "acting",
    Verifying => "verifying",
    Resolved => "resolved",
    Escalated => "escalated",
  }
}

# The status FSM is exhaustive: illegal moves are rejected, never
# silently absorbed. Escalated and Resolved are terminal for the
# kernel; reopening is a new incident.
fn legal_move(from :: Status, to :: Status) -> Bool
  examples {
    legal_move(Triage, Acting) => true,
    legal_move(Triage, Escalated) => true,
    legal_move(Acting, Verifying) => true,
    legal_move(Verifying, Acting) => true,
    legal_move(Verifying, Resolved) => true,
    legal_move(Resolved, Acting) => false,
    legal_move(Escalated, Triage) => false,
    legal_move(Triage, Resolved) => false
  }
{
  match from {
    Triage => match to {
      Acting => true,
      Escalated => true,
      _ => false,
    },
    Acting => match to {
      Verifying => true,
      Escalated => true,
      _ => false,
    },
    Verifying => match to {
      Acting => true,
      Resolved => true,
      Escalated => true,
      _ => false,
    },
    Resolved => false,
    Escalated => false,
  }
}

fn advance(i :: Incident, to :: Status) -> Result[Incident, Str]
  examples {
    advance({ id: "i1", opened_at_ms: 0, symptoms: [], hypotheses: [], evidence: [], budget: { spent_milli: 0, cap_milli: 1000 }, actions: [], pending_effects: [], status: Triage }, Acting) => Ok({ id: "i1", opened_at_ms: 0, symptoms: [], hypotheses: [], evidence: [], budget: { spent_milli: 0, cap_milli: 1000 }, actions: [], pending_effects: [], status: Acting }),
    advance({ id: "i1", opened_at_ms: 0, symptoms: [], hypotheses: [], evidence: [], budget: { spent_milli: 0, cap_milli: 1000 }, actions: [], pending_effects: [], status: Resolved }, Acting) => Err("illegal transition: resolved -> acting")
  }
{
  if legal_move(i.status, to) {
    Ok({ id: i.id, opened_at_ms: i.opened_at_ms, symptoms: i.symptoms, hypotheses: i.hypotheses, evidence: i.evidence, budget: i.budget, actions: i.actions, pending_effects: i.pending_effects, status: to })
  } else {
    Err(str.join(["illegal transition: ", status_str(i.status), " -> ", status_str(to)], ""))
  }
}

fn exhausted(b :: Budget) -> Bool
  examples {
    exhausted({ spent_milli: 1000, cap_milli: 1000 }) => true,
    exhausted({ spent_milli: 999, cap_milli: 1000 }) => false
  }
{
  b.spent_milli >= b.cap_milli
}

# Spend from the evidence budget; refuses to overrun. Budget
# exhaustion is the caller's cue to escalate and record a sensing gap.
fn spend(b :: Budget, cost_milli :: Int) -> Result[Budget, Str]
  examples {
    spend({ spent_milli: 0, cap_milli: 1000 }, 400) => Ok({ spent_milli: 400, cap_milli: 1000 }),
    spend({ spent_milli: 900, cap_milli: 1000 }, 200) => Err("evidence budget exhausted")
  }
{
  if b.spent_milli + cost_milli > b.cap_milli {
    Err("evidence budget exhausted")
  } else {
    Ok({ spent_milli: b.spent_milli + cost_milli, cap_milli: b.cap_milli })
  }
}

# Append an evidence record, paying its cost from the budget.
fn add_evidence(i :: Incident, e :: Evidence) -> Result[Incident, Str]
  examples {
    add_evidence({ id: "i1", opened_at_ms: 0, symptoms: [], hypotheses: [], evidence: [], budget: { spent_milli: 900, cap_milli: 1000 }, actions: [], pending_effects: [], status: Triage }, { query: "q", cost_milli: 200, result_ref: "r", ts_ms: 1 }) => Err("evidence budget exhausted")
  }
{
  match spend(i.budget, e.cost_milli) {
    Err(m) => Err(m),
    Ok(b) => Ok({ id: i.id, opened_at_ms: i.opened_at_ms, symptoms: i.symptoms, hypotheses: i.hypotheses, evidence: list.cons(e, i.evidence), budget: b, actions: i.actions, pending_effects: i.pending_effects, status: i.status }),
  }
}

# The current best hypothesis, by posterior.
fn top_hypothesis(hs :: List[Hypothesis]) -> Option[Hypothesis]
  examples {
    top_hypothesis([]) => None,
    top_hypothesis([{ cause: "a", p_pct: 30, evidence_for: [], evidence_against: [] }, { cause: "b", p_pct: 70, evidence_for: [], evidence_against: [] }]) => Some({ cause: "b", p_pct: 70, evidence_for: [], evidence_against: [] })
  }
{
  list.fold(hs, None, fn (acc :: Option[Hypothesis], h :: Hypothesis) -> Option[Hypothesis] {
    match acc {
      None => Some(h),
      Some(best) => if h.p_pct > best.p_pct {
        Some(h)
      } else {
        Some(best)
      },
    }
  })
}

# Stopping rule: the max posterior has cleared the confidence bar.
fn confident(hs :: List[Hypothesis], p_star_pct :: Int) -> Bool
  examples {
    confident([], 80) => false,
    confident([{ cause: "a", p_pct: 85, evidence_for: [], evidence_against: [] }], 80) => true,
    confident([{ cause: "a", p_pct: 40, evidence_for: [], evidence_against: [] }], 80) => false
  }
{
  match top_hypothesis(hs) {
    None => false,
    Some(h) => h.p_pct >= p_star_pct,
  }
}

