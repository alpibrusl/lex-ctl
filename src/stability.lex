# lex-ctl — stability primitives: the controller is inside the loop it observes
#
# Oscillation is the default failure mode, not the exotic one. This
# module carries the damping mechanisms:
#
# - Dwell locks: no new action on a subsystem while a prior effect on
#   that subsystem is pending — also what keeps attribution
#   identifiable for the verifier.
# - A global concurrency cap, independent of how many incidents are
#   open (correlated incidents produce correlated actions).
# - Hysteresis: entry and exit conditions differ, never symmetric.
#
# Effects: none. All functions are pure.

import "std.list" as list

type DwellLock = { subsystem :: Str, held_until_ms :: Int }

# Is the subsystem under an unexpired dwell lock?
fn locked(locks :: List[DwellLock], subsystem :: Str, now_ms :: Int) -> Bool
  examples {
    locked([], "svc", 0) => false,
    locked([{ subsystem: "svc", held_until_ms: 100 }], "svc", 50) => true,
    locked([{ subsystem: "svc", held_until_ms: 100 }], "svc", 100) => false,
    locked([{ subsystem: "svc", held_until_ms: 100 }], "other", 50) => false
  }
{
  list.fold(locks, false, fn (acc :: Bool, l :: DwellLock) -> Bool {
    acc or l.subsystem == subsystem and now_ms < l.held_until_ms
  })
}

# Take a dwell lock on a subsystem until `until_ms`.
fn acquire(locks :: List[DwellLock], subsystem :: Str, until_ms :: Int) -> List[DwellLock]
  examples {
    acquire([], "svc", 100) => [{ subsystem: "svc", held_until_ms: 100 }]
  }
{
  list.cons({ subsystem: subsystem, held_until_ms: until_ms }, locks)
}

# Drop expired locks (host calls this on its verification schedule).
fn sweep(locks :: List[DwellLock], now_ms :: Int) -> List[DwellLock]
  examples {
    sweep([{ subsystem: "svc", held_until_ms: 100 }], 200) => [],
    sweep([{ subsystem: "svc", held_until_ms: 100 }], 50) => [{ subsystem: "svc", held_until_ms: 100 }]
  }
{
  list.reverse(list.fold(locks, [], fn (acc :: List[DwellLock], l :: DwellLock) -> List[DwellLock] {
    if now_ms < l.held_until_ms {
      list.cons(l, acc)
    } else {
      acc
    }
  }))
}

# The gate the executor consults before any action: the subsystem must
# be unlocked AND the system-wide in-flight count must be under the
# global cap. This check is structural — it never consults narrative.
fn can_act(locks :: List[DwellLock], subsystem :: Str, now_ms :: Int, in_flight :: Int, global_cap :: Int) -> Bool
  examples {
    can_act([], "svc", 0, 0, 1) => true,
    can_act([], "svc", 0, 1, 1) => false,
    can_act([{ subsystem: "svc", held_until_ms: 100 }], "svc", 50, 0, 1) => false
  }
{
  in_flight < global_cap and not locked(locks, subsystem, now_ms)
}

# Asymmetric entry/exit thresholds over a residual score. A condition
# opens at `enter_milli` and only closes again below `exit_milli`.
type Hysteresis = { enter_milli :: Int, exit_milli :: Int }

# Entry must be strictly above exit, or the band is degenerate.
fn well_formed(h :: Hysteresis) -> Bool
  examples {
    well_formed({ enter_milli: 3000, exit_milli: 1000 }) => true,
    well_formed({ enter_milli: 1000, exit_milli: 1000 }) => false
  }
{
  h.enter_milli > h.exit_milli
}

# Next open/closed state given the current score and current state.
fn next_open(h :: Hysteresis, score_milli :: Int, open :: Bool) -> Bool
  examples {
    next_open({ enter_milli: 3000, exit_milli: 1000 }, 3500, false) => true,
    next_open({ enter_milli: 3000, exit_milli: 1000 }, 2000, false) => false,
    next_open({ enter_milli: 3000, exit_milli: 1000 }, 2000, true) => true,
    next_open({ enter_milli: 3000, exit_milli: 1000 }, 500, true) => false
  }
{
  if open {
    score_milli >= h.exit_milli
  } else {
    score_milli >= h.enter_milli
  }
}

