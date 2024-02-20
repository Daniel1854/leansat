import LeanSAT.Reflect.Tactics.Reflect
import LeanSAT.Reflect.BoolExpr.Decidable -- This import is not used directly, but without it the tactic fails.

open Lean Meta ReflectSat

def _root_.Lean.MVarId.satDecide (g : MVarId) : MetaM Unit := M.run do
  let g' ← falseOrByContra g
  g'.withContext do
  let (e, f) ← reflectSAT g'
    trace[sat] "Reflected boolean expression: {e}"
    let p ← mkDecideProof (mkApp2 (.const ``BoolExpr.unsat []) (.const ``Nat []) (toExpr e))
    g'.assign (← f p)

syntax (name := satDecideSyntax) "sat_decide" : tactic

open Elab.Tactic
elab_rules : tactic
  | `(tactic| sat_decide) => do liftMetaFinishingTactic fun g => g.satDecide
