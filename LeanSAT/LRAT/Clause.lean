/-
Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Josh Clune
-/
import LeanSAT.Sat.Basic
import LeanSAT.Sat.Literal
import LeanSAT.Util.PosFin
import LeanSAT.Util.Misc
import Std.Data.Array.Lemmas
import LeanSAT.LRAT.Assignment

namespace LRAT

/-- ReduceResult is an inductive datatype used specifically for the output of the `reduce` function. The intended
    meaning of each constructor is explained in the docstring of the `reduce` function. -/
inductive ReduceResult (α : Type u)
  | encounteredBoth
  | reducedToEmpty
  | reducedToUnit (l : Literal α)
  | reducedToNonunit

open Misc Literal Assignment ReduceResult

/-- Typeclass for clauses. An instance [Clause α β] indicates that β is
    the type of a clause with variables of type α. -/
class Clause (α : outParam (Type u)) (β : Type v) where
  toList : β → List (Literal α)
  not_tautology : ∀ c : β, ∀ l : Literal α, l ∉ toList c ∨ negateLiteral l ∉ toList c
  ofArray : Array (Literal α) → Option β -- Returns none if the given array contains complementary literals
  ofArray_eq :
    ∀ arr : Array (Literal α), (∀ i : Fin arr.size, ∀ j : Fin arr.size, i.1 ≠ j.1 → arr[i] ≠ arr[j]) →
      ∀ c : β, ofArray arr = some c → toList c = arr.toList
  empty : β
  empty_eq : toList empty = []
  unit : Literal α → β
  unit_eq : ∀ l : Literal α, toList (unit l) = [l]
  isUnit : β → Option (Literal α)
  isUnit_iff : ∀ c : β, ∀ l : Literal α, isUnit c = some l ↔ toList c = [l]
  negate : β → List (Literal α)
  negate_iff : ∀ c : β, negate c = (toList c).map negateLiteral
  insert : β → Literal α → Option β -- Returns none if the result is a tautology
  delete : β → Literal α → β
  delete_iff : ∀ c : β, ∀ l : Literal α, ∀ l' : Literal α,
    l' ∈ toList (delete c l) ↔ l' ≠ l ∧ l' ∈ toList c
  contains : β → Literal α → Bool
  contains_iff : ∀ c : β, ∀ l : Literal α, contains c l ↔ l ∈ toList c
  reduce : β → Array Assignment → ReduceResult α -- Reduces the clause with respect to the given assignment
  dimacs : β → String

namespace Clause

instance [Clause α β] : HSat α β :=
  { eval := fun p c => (toList c).any fun (l : Literal α) => p ⊨ l }

instance [Clause α β] (p : α → Bool) (c : β) : Decidable (p ⊨ c) := by
  rw [HSat.eval, instHSat]
  simp only [decide_eq_true_eq, Prod.exists, Bool.exists_bool]
  rw [List.any]
  exact Bool.decEq _ _

instance [Clause α β] : Inhabited β where
  default := empty

end Clause

/-- The `DefaultClause` structure is primarily a list of literals. The additional field `nodupkey` is included to ensure that `not_tautology`
    is provable (which is needed to prove `insertRup_entails_hsat` and `insertRat_entails_hsat` in `LRAT.Formula.RupAddSound.lean` and
    `LRAT.Formula.RatAddSound.lean`). The additional field `nodup` is included to ensure that `delete` can be implemented by simply calling `erase`
    on the `clause` field. Without `nodup`, it would be necessary to iterate through the entire `clause` field and erase all instances of the literal
    to be deleted, since there would potentially be more than one.

    In principle, one could combine `nodupkey` and `nodup` to instead have one additional field that stipulates that
    `∀ l1 : PosFin numVarsSucc, ∀ l2 : PosFin numVarsSucc, l1.1 ≠ l2.1`. This would work just as well, and the only reason that `DefaultClause`
    is structured in this manner is that the `nodup` field was only included in a later stage of the verification process when it became clear that
    it was needed. -/
@[ext] structure DefaultClause (numVarsSucc : Nat) where
  clause : List (Literal (PosFin numVarsSucc))
  nodupkey : ∀ l : PosFin numVarsSucc, (l, true) ∉ clause ∨ (l, false) ∉ clause
  nodup : List.Nodup clause

instance {n : Nat} : BEq (DefaultClause n) where
  beq := fun a1 a2 => a1.clause == a2.clause

instance {n : Nat} : ToString (DefaultClause n) where
  toString := fun c => s!"{c.clause.reverse}"

namespace DefaultClause

def toList {n : Nat} (c : DefaultClause n) : List (Literal (PosFin n)) := c.clause

theorem not_tautology {n : Nat} (c : DefaultClause n) (l : Literal (PosFin n)) : ¬ l ∈ toList c ∨ ¬negateLiteral l ∈ toList c := by
  simp only [toList, negateLiteral]
  have h := c.nodupkey l.1
  by_cases hl : l.2
  . simp only [hl, Bool.not_true]
    rcases h with h | h
    . rw [← hl] at h
      exact Or.inl h
    . exact Or.inr h
  . simp only [hl, Bool.not_false]
    simp only [Bool.not_eq_true] at hl
    rcases h with h | h
    . exact Or.inr h
    . rw [← hl] at h
      exact Or.inl h

def empty {n : Nat} : DefaultClause n :=
  let clause := []
  have nodupkey := by simp only [List.find?, List.not_mem_nil, not_false_eq_true, or_self, implies_true]
  have nodup := by simp only [List.nodup_nil]
  ⟨clause, nodupkey, nodup⟩

theorem empty_eq {n : Nat} : toList (empty : DefaultClause n) = [] := by rfl

def unit {n : Nat} (l : Literal (PosFin n)) : DefaultClause n :=
  let clause := [l]
  have nodupkey := by
    intro l'
    by_cases l.2
    . next hl =>
      apply Or.inr
      simp only [List.mem_singleton]
      rw [← @Prod.mk.eta (PosFin n) Bool l, hl]
      simp only [Prod.mk.injEq, and_false, not_false_eq_true]
    . next hl =>
      apply Or.inl
      simp only [List.mem_singleton]
      simp only [Bool.not_eq_true] at hl
      rw [← @Prod.mk.eta (PosFin n) Bool l, hl]
      simp only [Prod.mk.injEq, and_false, not_false_eq_true]
  have nodup := by simp only [List.nodup_cons, List.find?, List.not_mem_nil, not_false_eq_true, List.nodup_nil, and_self]
  ⟨clause, nodupkey, nodup⟩

theorem unit_eq {n : Nat} (l : Literal (PosFin n)) : toList (unit l) = [l] := by rfl

def isUnit {n : Nat} (c : DefaultClause n) : Option (Literal (PosFin n)) :=
  match c.clause with
  | [l] => some l
  | _ => none

theorem isUnit_iff {n : Nat} (c : DefaultClause n) (l : Literal (PosFin n)) :
  isUnit c = some l ↔ toList c = [l] := by
  simp only [isUnit, Prod.forall, toList]
  split
  . next l' heq =>
    simp only [Option.some.injEq]
    constructor
    . intro h
      rw [← h]
      exact heq
    . intro h
      rw [h] at heq
      simp only [List.cons.injEq, and_true] at heq
      exact heq.symm
  . next hne =>
    simp only [false_iff]
    intro heq
    exact hne l heq

def negate {n : Nat} (c : DefaultClause n) : List (Literal (PosFin n)) := c.clause.map negateLiteral

theorem negate_iff {n : Nat} (c : DefaultClause n) : negate c = (toList c).map negateLiteral := by rfl

theorem instBEq_rw {n : Nat} : (instBEq : BEq (Literal (PosFin n))) = instBEqProd := by
  simp only [instBEq, instBEqProd]
  have beq_rw :
    (fun (l1 : Literal (PosFin n)) (l2 : Literal (PosFin n)) => decide (l1 = l2)) =
    (fun (l1 : Literal (PosFin n)) (l2 : Literal (PosFin n)) => l1.1 == l2.1 && decide (l1.2 = l2.2)) := by
    funext
    next a b =>
    by_cases a.1 == b.1
    . next h1 =>
      simp only [h1, beq_self_eq_true, Bool.true_and, decide_eq_decide]
      constructor
      . intro h; rw [h]
      . intro h2
        simp only [beq_iff_eq] at h1
        rw [← @Prod.mk.eta (PosFin n) Bool a, h1, h2]
    . next h1 =>
      simp only [h1, Bool.false_and, decide_eq_false_iff_not]
      intro h
      simp only [h, beq_self_eq_true, not_true] at h1
  rw [beq_rw]

/-- Attempts to add the literal (idx, b) to clause c. Returns none if doing so would make c a tautology -/
def insert {n : Nat} (c : DefaultClause n) (l : Literal (PosFin n)) : Option (DefaultClause n) :=
  if heq1 : c.clause.contains (l.1, not l.2) then none -- Adding l would make c a tautology
  else if heq2 : c.clause.contains l then some c
  else
    let clause := l :: c.clause
    have nodupkey : ∀ (l : PosFin n), ¬(l, true) ∈ clause ∨ ¬(l, false) ∈ clause := by
      intro l'
      simp only [List.contains, Bool.not_eq_true] at heq1
      rw [← instBEq_rw] at heq1
      have heq1 := @List.not_mem_of_elem_eq_false (Literal (PosFin n)) _ (l.1, !l.2) c.clause heq1
      simp only [List.find?, List.mem_cons, not_or]
      by_cases l' = l.1
      . next l'_eq_l =>
        by_cases hl : l.2
        . apply Or.inr
          constructor
          . intro heq
            simp only [← heq] at hl
          . simp only [hl, ← l'_eq_l, Bool.not_true] at heq1
            exact heq1
        . simp only [Bool.not_eq_true] at hl
          apply Or.inl
          constructor
          . intro heq
            simp only [← heq] at hl
          . simp only [← l'_eq_l, hl, Bool.not_false] at heq1
            exact heq1
      . next l'_ne_l =>
        rcases c.nodupkey l' with h | h
        . apply Or.inl
          apply And.intro _ h
          intro heq
          simp only [← heq, not_true] at l'_ne_l
        . apply Or.inr
          apply And.intro _ h
          intro heq
          simp only [← heq, not_true] at l'_ne_l
    have nodup : List.Nodup clause := by
      simp only [List.nodup_cons, c.nodup, and_true]
      simp only [List.contains, Bool.not_eq_true] at heq2
      rw [← instBEq_rw] at heq2
      exact @List.not_mem_of_elem_eq_false (Literal (PosFin n)) _ l c.clause heq2
    some ⟨clause, nodupkey, nodup⟩

def ofArray {n : Nat} (ls : Array (Literal (PosFin n))) : Option (DefaultClause n) :=
  let fold_fn (l : Literal (PosFin n)) (acc : Option (DefaultClause n)) : Option (DefaultClause n) :=
    match acc with
    | none => none
    | some acc => acc.insert l
  ls.foldr fold_fn (some empty)

theorem ofArray_eq (arr : Array (Literal (PosFin n))) (arrNodup : ∀ i : Fin arr.size, ∀ j : Fin arr.size, i.1 ≠ j.1 → arr[i] ≠ arr[j])
  (c : DefaultClause n) : ofArray arr = some c → toList c = Array.toList arr := by
  intro h
  simp only [ofArray] at h
  rw [toList, Array.toList_eq]
  let motive (idx : Nat) (acc : Option (DefaultClause n)) : Prop :=
    ∃ idx_le_arr_size : idx ≤ arr.size, ∀ c' : DefaultClause n, acc = some c' →
      ∃ hsize : c'.clause.length = arr.size - idx, ∀ i : Fin c'.clause.length,
      have idx_in_bounds : idx + i.1 < arr.size := by
        rw [Nat.eq_add_of_sub_eq idx_le_arr_size (Eq.symm hsize), Nat.add_comm]
        apply Nat.add_lt_add_right
        exact i.2
      List.get c'.clause i = arr[idx + i]'idx_in_bounds
  have h_base : motive arr.size (some empty) := by
    apply Exists.intro $ Nat.le_refl arr.size
    intro c' heq
    simp only [Option.some.injEq] at heq
    have hsize : List.length c'.clause = arr.size- arr.size := by
      simp only [← heq, empty, List.length_nil, Nat.sub_self]
    apply Exists.intro hsize
    intro i
    simp only [← heq, empty, List.length_nil] at i
    exact Fin.elim0 i
  let fold_fn (l : Literal (PosFin n)) (acc : Option (DefaultClause n)) : Option (DefaultClause n) :=
    match acc with
    | none => none
    | some acc => acc.insert l
  have h_inductive (idx : Fin arr.size) (acc : Option (DefaultClause n)) (ih : motive (idx.1 + 1) acc) :
    motive idx.1 (fold_fn arr[idx] acc) := by
    rcases ih with ⟨idx_add_one_le_arr_size, ih⟩
    apply Exists.intro $ Nat.le_of_succ_le idx_add_one_le_arr_size
    intro c' heq
    simp only [getElem_fin] at heq
    split at heq
    . simp only at heq
    . next acc =>
      specialize ih acc (by rfl)
      rcases ih with ⟨hsize, ih⟩
      simp only at ih
      simp only [insert] at heq
      split at heq
      . exact False.elim heq
      . split at heq
        . next h_dup =>
          exfalso -- h_dup contradicts arrNodup
          simp only [List.contains] at h_dup
          rw [← instBEq_rw] at h_dup
          rcases List.get_of_mem $ List.mem_of_elem_eq_true h_dup with ⟨j, hj⟩
          specialize ih j
          rw [hj] at ih
          have idx_add_one_add_j_in_bounds : idx.1 + 1 + j.1 < arr.size := by
            simp only [getElem] at ih
            -- The following proof term was obtained by examining the proof state of ih
            exact @Eq.mpr (idx.val + 1 + j.val < Array.size arr) (idx.val + 1 + j.val < List.length acc.clause + (idx.val + 1))
              (id (Nat.eq_add_of_sub_eq idx_add_one_le_arr_size (Eq.symm hsize) ▸ Eq.refl (idx.val + 1 + j.val < Array.size arr)))
              (Eq.mpr
                (id (Nat.add_comm (idx.val + 1) j.val ▸ Eq.refl (idx.val + 1 + j.val < List.length acc.clause + (idx.val + 1))))
                (Nat.add_lt_add_right j.isLt (idx.val + 1)))
          have idx_ne_idx_add_one_add_j_in_bounds : idx.1 ≠ idx.1 + 1 + j.1 :=
            Nat.ne_of_lt ∘ Nat.lt_add_right idx.val (idx.val + 1) j.val $ Nat.lt_succ_self idx.1
          exact arrNodup idx ⟨idx.1 + 1 + j.1, idx_add_one_add_j_in_bounds⟩ idx_ne_idx_add_one_add_j_in_bounds ih
        . simp only [Option.some.injEq] at heq
          have hsize' : c'.clause.length = arr.size - idx.1 := by
            simp only [← heq, List.length_cons, hsize]
            rw [Nat.succ_eq_add_one, Nat.sub_add_eq, Nat.sub_add_cancel]
            apply Nat.le_sub_of_add_le
            rw [Nat.add_comm]
            exact idx_add_one_le_arr_size
          apply Exists.intro hsize'
          intro i
          simp only
          have lhs_rw : c'.clause = arr[idx.1] :: acc.clause := by rw [← heq]
          simp only [List.get_of_eq lhs_rw]
          by_cases i.1 = 0
          . next i_eq_zero =>
            simp only [List.length_cons, i_eq_zero, List.get, Nat.add_zero]
          . next i_ne_zero =>
            rcases Nat.exists_eq_succ_of_ne_zero i_ne_zero with ⟨j, hj⟩
            simp only [List.length_cons, hj, List.get, Nat.succ_eq_add_one]
            simp only [Nat.add_comm j 1, ← Nat.add_assoc]
            have j_in_bounds : j < acc.clause.length := by
              have i_property := i.2
              rw [hj, hsize'] at i_property
              rw [hsize, Nat.sub_add_eq]
              exact Nat.lt_sub_of_add_lt i_property
            exact ih ⟨j, j_in_bounds⟩
  rcases (Array.foldr_induction motive h_base h_inductive).2 c h with ⟨hsize, h⟩
  ext
  next i l =>
  by_cases i_in_bounds : i < c.clause.length
  . specialize h ⟨i, i_in_bounds⟩
    simp only at h
    have i_in_bounds' : i < arr.data.length := by
      simp only [Nat.sub_zero] at hsize
      rw [← Array.size_mk, ← hsize]
      exact i_in_bounds
    rw [List.get?_eq_get i_in_bounds, List.get?_eq_get i_in_bounds']
    simp only [h, Nat.zero_add, Array.getElem_eq_data_get, Option.mem_def, Option.some.injEq]
  . simp only [Nat.not_lt] at i_in_bounds
    have arr_data_length_le_i : arr.data.length ≤ i := by
      simp only [Nat.sub_zero] at hsize
      rw [hsize] at i_in_bounds
      rw [← Array.size_mk]
      exact i_in_bounds
    rw [← List.get?_eq_none] at i_in_bounds
    rw [← List.get?_eq_none] at arr_data_length_le_i
    rw [i_in_bounds, arr_data_length_le_i]

def delete {n : Nat} (c : DefaultClause n) (l : Literal (PosFin n)) : DefaultClause n :=
  let clause := c.clause.erase l
  let nodupkey : ∀ (l : PosFin n), ¬(l, true) ∈ clause ∨ ¬(l, false) ∈ clause := by
    intro l'
    simp only
    rw [← instBEq_rw]
    rcases c.nodupkey l' with ih | ih
    . apply Or.inl
      intro h
      exact ih $ List.mem_of_mem_erase h
    . apply Or.inr
      intro h
      exact ih $ List.mem_of_mem_erase h
  have nodup := by
    simp only
    rw [← instBEq_rw]
    exact List.Nodup.erase l c.nodup
  ⟨clause, nodupkey, nodup⟩

theorem delete_iff (c : DefaultClause n) (l l' : Literal (PosFin n)) : l' ∈ toList (delete c l) ↔ l' ≠ l ∧ l' ∈ toList c := by
  simp only [toList, delete, ne_eq]
  by_cases hl : l' = l
  . simp only [hl, not_true, false_and, iff_false]
    rw [← instBEq_rw]
    exact List.Nodup.not_mem_erase c.nodup
  . simp only [hl, not_false_eq_true, true_and]
    rw [← instBEq_rw]
    exact List.mem_erase_of_ne hl

def contains {n : Nat} (c : DefaultClause n) (l : Literal (PosFin n)) : Bool := c.clause.contains l

theorem contains_iff : ∀ (c : DefaultClause n) (l : Literal (PosFin n)), contains c l = true ↔ l ∈ toList c := by
  intro c l
  simp only [contains, List.contains]
  rw [← instBEq_rw]
  constructor
  . exact List.mem_of_elem_eq_true
  . exact List.elem_eq_true_of_mem

def reduce_fold_fn (assignments : Array Assignment) (acc : ReduceResult (PosFin n)) (l : Literal (PosFin n)) : ReduceResult (PosFin n) :=
  match acc with
    | encounteredBoth => encounteredBoth
    | reducedToEmpty =>
      match assignments[l.1.1]! with
      | pos =>
        if l.2 then reducedToUnit l
        else reducedToEmpty
      | neg =>
        if not l.2 then reducedToUnit l
        else reducedToEmpty
      | both => encounteredBoth
      | unassigned => reducedToUnit l
    | reducedToUnit l' =>
      match assignments[l.1.1]! with
      | pos =>
        if l.2 then reducedToNonunit -- Assignment fails to refute both l and l'
        else reducedToUnit l'
      | neg =>
        if not l.2 then reducedToNonunit -- Assignment fails to refute both l and l'
        else reducedToUnit l'
      | both => encounteredBoth
      | unassigned => reducedToNonunit -- Assignments fails to refute both l and l'
    | reducedToNonunit => reducedToNonunit

/-- The `reduce` function takes in a clause `c` and takes in an array of assignments and attempts to eliminate every literal
    in the clause that is not compatible with the `assignments` argument.
    - If `reduce` returns `encounteredBoth`, then this means that the `assignments` array has a `both` Assignment and is therefore fundamentally unsatisfiable.
    - If `reduce` returns `reducedToEmpty`, then this means that every literal in `c` is incompatible with `assignments`. In other words, this means that
      the conjunction of `assignments` and `c` is unsatisfiable.
    - If `reduce` returns `reducedToUnit l`, then this means that every literal in `c` is incompatible with `assignments` except for `l`. In other words,
      this means that the conjunction of `assignments` and `c` entail `l`.
    - If `reduce` returns `reducedToNonunit`, then this means that there are multiple literals in `c` that are compatible with `assignments`. This is a failure
      condition for `confirmRupHint` (in `LRAT.Formula.Implementation.lean`) which calls `reduce`. -/
def reduce {n : Nat} (c : DefaultClause n) (assignments : Array Assignment) : ReduceResult (PosFin n) :=
  c.clause.foldl (reduce_fold_fn assignments) reducedToEmpty

def dimacs {n : Nat} (c : DefaultClause n) : String :=
  String.join ((toList c).map (fun l => Literal.dimacs l ++ " ")) ++ "0"

instance {n : Nat} : Clause (PosFin n) (DefaultClause n) where
  toList := toList
  not_tautology := not_tautology
  ofArray := ofArray
  ofArray_eq := ofArray_eq
  empty := empty
  empty_eq := empty_eq
  unit := unit
  unit_eq := unit_eq
  isUnit := isUnit
  isUnit_iff := isUnit_iff
  negate := negate
  negate_iff := negate_iff
  insert := insert
  delete := delete
  delete_iff := delete_iff
  contains := contains
  contains_iff := contains_iff
  reduce := reduce
  dimacs := dimacs
