# lex-ctl — autonomy tiers earned from measured hit rate
#
# Every action class is classified along three axes (reversibility ×
# blast radius × dwell). The classification sets a structural CEILING
# on autonomy; the measured effect-contract hit rate decides whether
# the class actually reaches it. Promotion and demotion are both
# driven by the rolling record — never by confidence in the agent.
#
# The circuit breaker applies to the class: N consecutive falsified
# contracts drop an Auto-capable class back to Propose. Recovery is
# the host's call (manual, or shadow re-qualification) — the kernel
# only reports; it never self-resets.
#
# Effects: none. All functions are pure.

type Reversibility = Idempotent | Compensatable | Irreversible

type Blast = Instance | Service | SharedDep | Global

type Tier = Auto | Propose | Escalate

type ActionClass = { key :: Str, reversibility :: Reversibility, blast :: Blast, dwell_ms :: Int }

type ClassStats = { hits :: Int, misses :: Int, consecutive_misses :: Int }

type Policy = { min_samples :: Int, min_hit_rate_pct :: Int, breaker_misses :: Int }

fn empty_stats() -> ClassStats
  examples {
    empty_stats() => { hits: 0, misses: 0, consecutive_misses: 0 }
  }
{
  { hits: 0, misses: 0, consecutive_misses: 0 }
}

# Record one verifier disposition (hit = clean materialisation only).
fn record(s :: ClassStats, hit :: Bool) -> ClassStats
  examples {
    record(empty_stats(), true) => { hits: 1, misses: 0, consecutive_misses: 0 },
    record(empty_stats(), false) => { hits: 0, misses: 1, consecutive_misses: 1 },
    record(record(empty_stats(), false), false) => { hits: 0, misses: 2, consecutive_misses: 2 },
    record(record(empty_stats(), false), true) => { hits: 1, misses: 1, consecutive_misses: 0 }
  }
{
  if hit {
    { hits: s.hits + 1, misses: s.misses, consecutive_misses: 0 }
  } else {
    { hits: s.hits, misses: s.misses + 1, consecutive_misses: s.consecutive_misses + 1 }
  }
}

fn samples(s :: ClassStats) -> Int
  examples {
    samples(empty_stats()) => 0,
    samples(record(empty_stats(), true)) => 1
  }
{
  s.hits + s.misses
}

# Hit rate as an integer percentage; 0 when there are no samples.
fn hit_rate_pct(s :: ClassStats) -> Int
  examples {
    hit_rate_pct(empty_stats()) => 0,
    hit_rate_pct(record(empty_stats(), true)) => 100,
    hit_rate_pct(record(record(empty_stats(), true), false)) => 50
  }
{
  let n := samples(s)
  if n == 0 {
    0
  } else {
    s.hits * 100 / n
  }
}

# Structural ceiling from the classification alone. Irreversible or
# global actions can never exceed Escalate; compensatable or
# shared-dependency actions can never exceed Propose. Only an
# idempotent-reversible action with blast ≤ service can earn Auto.
fn ceiling(c :: ActionClass) -> Tier
  examples {
    ceiling({ key: "restart", reversibility: Idempotent, blast: Instance, dwell_ms: 60000 }) => Auto,
    ceiling({ key: "scale", reversibility: Compensatable, blast: Service, dwell_ms: 60000 }) => Propose,
    ceiling({ key: "migrate", reversibility: Irreversible, blast: Instance, dwell_ms: 60000 }) => Escalate,
    ceiling({ key: "flush", reversibility: Idempotent, blast: Global, dwell_ms: 60000 }) => Escalate,
    ceiling({ key: "evict", reversibility: Idempotent, blast: SharedDep, dwell_ms: 60000 }) => Propose
  }
{
  match c.reversibility {
    Irreversible => Escalate,
    Compensatable => match c.blast {
      Global => Escalate,
      _ => Propose,
    },
    Idempotent => match c.blast {
      Global => Escalate,
      SharedDep => Propose,
      _ => Auto,
    },
  }
}

fn breaker_tripped(s :: ClassStats, p :: Policy) -> Bool
  examples {
    breaker_tripped(empty_stats(), { min_samples: 30, min_hit_rate_pct: 70, breaker_misses: 3 }) => false,
    breaker_tripped(record(record(record(empty_stats(), false), false), false), { min_samples: 30, min_hit_rate_pct: 70, breaker_misses: 3 }) => true
  }
{
  s.consecutive_misses >= p.breaker_misses
}

# The tier the class actually operates at: its structural ceiling,
# demoted by insufficient evidence or a tripped breaker. A class is
# never promoted on another class's record.
fn effective(c :: ActionClass, s :: ClassStats, p :: Policy) -> Tier
  examples {
    effective({ key: "migrate", reversibility: Irreversible, blast: Instance, dwell_ms: 60000 }, empty_stats(), { min_samples: 1, min_hit_rate_pct: 70, breaker_misses: 3 }) => Escalate,
    effective({ key: "restart", reversibility: Idempotent, blast: Instance, dwell_ms: 60000 }, empty_stats(), { min_samples: 1, min_hit_rate_pct: 70, breaker_misses: 3 }) => Propose,
    effective({ key: "restart", reversibility: Idempotent, blast: Instance, dwell_ms: 60000 }, record(empty_stats(), true), { min_samples: 1, min_hit_rate_pct: 70, breaker_misses: 3 }) => Auto,
    effective({ key: "restart", reversibility: Idempotent, blast: Instance, dwell_ms: 60000 }, record(record(record(empty_stats(), false), false), false), { min_samples: 1, min_hit_rate_pct: 70, breaker_misses: 3 }) => Propose
  }
{
  match ceiling(c) {
    Escalate => Escalate,
    Propose => Propose,
    Auto => if breaker_tripped(s, p) {
      Propose
    } else {
      if samples(s) < p.min_samples {
        Propose
      } else {
        if hit_rate_pct(s) < p.min_hit_rate_pct {
          Propose
        } else {
          Auto
        }
      }
    },
  }
}

