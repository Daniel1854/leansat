import LeanSAT.Reflect.Tactics.BVDecide

theorem bitvec_AndOrXor_1704 :
 ∀ (A B : BitVec 64), (B == 0) || (A < B) = (A ≤ B + -1)
:= by bv_decide