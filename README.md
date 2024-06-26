# LeanSAT

## Description
The LeanSAT package is meant to provide an interface and foundation for verified SAT reasoning.

The things of interested for most external users are:
- SAT tactics for automatically discharging goals about boolean expressions, using a SAT solver.
- (WIP) bitblasting tactic for automatically discharging goals about bitvector expressions, using a
  verified bitblaster + a SAT solver.

These tactics are driven by two components that might be of interested for further work:
1. A verified LRAT certificate checker, used to import UNSAT proofs generated by high performance
   SAT solvers, like CaDiCal.
2. A verified AIG implementation, used to exploit subterm sharing while turning the goals into
   SAT problems.

## Installation
This is a Lean 4 project.
- If you already have Lean 4 installed, with an up-to-date version of `elan`, this project can be
  built by running `lake build`.
- If you already have Lean 4 installed, but `elan` is not up to date
  (and in particular, is old enough to not be able to access `lean4:nightly-2023-07-31`), then
  first run `elan self update`.
  After this command is run once, the project can be built by running `lake build`.
- If you do not have Lean 4 installed, first run
  `curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh`,
  then the project can be built by running `lake build`.
- If you do not have Lean 4 installed and the above `curl` command fails,
  follow the instructions under
  `Regular install` [here](https://leanprover-community.github.io/get_started.html).

Additionally the project requires a SAT solver, capable of emitting LRAT UNSAT proofs. The one that
is used by default is CaDiCal. CaDiCal can usually be installed from Linux package repositories or
built from source if necessary.

## Usage
The package offers three different SAT tactics for proving goals involving `BitVec` and `Bool`:
1. `bv_decide`, this takes the goal, hands it over to a SAT solver and verifies the generated LRAT
   UNSAT proof to prove the goal.
2. `bv_check file.lrat`, it can prove the same things as `bv_decide`. However instead of
   dynamically handing the goal to a SAT solver to obtain an LRAT proof, the LRAT proof is read from
   `file.lrat`. This allows users that do not have a SAT solver installed to verify proofs.
3. `bv_decide?` this offers a code action to turn a `bv_decide` invocation automatically into a
   `bv_decide` one.

## Roadmap
There are a couple of ways in which this project can be improved.

`bv_decide`:
- Improve on the file name format used in `bv_decide?`
- clearly define the precise shape of goals that we operate on
- add support for additional `BitVec` constructs, we probably want to be approximately on a level
  with `QF_BV`.

AIG:
- Improve the CNF implementation, it is currently a purely naive one.
- Improve optimizations made on the AIG at construction time.
- Automization for writing functions involving `LawfulOperator`s, this is currently a bit tedious.
- Don't clear the cache when relabeling between variable types.

LRAT Checker:
- Currently, there are no specific optimizations for RAT additions. In particular, the function
  `ratHintsExhaustive` in `LRAT.Formula.Implementation.lean` is used to check that the negative RAT
  hints provided by a RAT addition are exhaustive. However, the current implementation of
  `ratHintsExhaustive` simply filters the totality of the default formula's `clauses` field and
  verifies that the ordered list of indices containing clauses is identical to the list of negative
  RAT hints provided by the RAT addition. This is inefficient because it involves a linear check
  over all indices in `clauses` including those that have been set to `none` due to a clause
  deletion. One way to improve on this would be to adopt an optimization used by cake_lpr and
  maintain a list of indices containing non-deleted clauses. Then, it would only be necessary to
  iterate over this list, rather than over all the indices in the `clauses` field. If such a change
  would be made, the resulting changes to the soundness proof should largely be localized to
  `existsRatHint_of_ratHintsExhaustive` in `LRAT.Formula.RatAddSound.lean`, though it would
  probably also be necessary to add additional requirements to `readyForRupAdd` and
  `readyForRatAdd`.

- Currently, the LRAT parser only supports the human readable format. Given the extent to which the
  parser poses a bottleneck, it is extremely desirable to find a way to either improve or bypass
  the parser. There are two avenues that might be explored to this end:
  1. In addition to having a human readable format, LRAT has a compressed binary format that is
     designed to be significantly shorter than the human readable format. Supporting this
    compressed binary format would likely make efficiently reading significantly long LRAT proofs
    more feasible. This improvement could benefit the LRAT checker both when it is used within Lean
    and when it is used as a standalone executable.
  2. To bypass LRAT parsing entirely, it may be possible to modify Cadical (or whichever SAT solver
     one desires to use) to use Lean's
     [Foreign Function Interface](https://leanprover.github.io/lean4/doc/dev/ffi.html) to have the
     SAT solver transform its LRAT proof into a datastructure that Lean can interact with directly.
     Then, rather than have the SAT solver write to a file and have the LRAT checker subsequently
     parse that file (slowly), the FFI could be used to send the LRAT proof to Lean directly.
     This would only be of benefit when the checker is being used within Lean, but I would expect
     it to yield greater performance benefits than the compressed binary format.
