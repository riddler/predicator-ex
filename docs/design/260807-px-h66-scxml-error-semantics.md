# SCXML has no rollback: execute/2 returns the partial context

Bead: px-h66. Status: proposed (2026-08-07), awaiting review.

px-tbv.2's acceptance criteria record the `Predicator.execute/2` error contract
as:

> Errors abort the sequence and the context from completed statements is not
> committed - matching SCXML's all-or-nothing error story, cheap because
> contexts are immutable. Statifier maps the error to `error.execution` and
> discards.

st-bfq carries the same sentence. This note verifies the citation against the
W3C spec, finds it wrong, and decides the contract on its own merits.

## The W3C reading

**W3C SCXML 1.0 specifies stop-on-error without rollback. It is textually
silent on rollback, and its conformance suite pins non-rollback
observationally.**

The one normative sentence is
[§4.9, Evaluation of Executable Content](https://www.w3.org/TR/scxml/#EvaluationofExecutableContent):

> The SCXML processor MUST execute the elements of a block in document order.
> If the processing of an element causes an error to be raised, the processor
> MUST NOT process the remaining elements of the block. (The execution of
> other blocks of executable content is not affected.)

The obligation is forward-looking only. Nothing is said about elements that
already completed, and the words "rollback", "undo", "transaction", and
"atomicity" do not appear in the error-handling text of §1-§6.

[§4.6, `<foreach>`](https://www.w3.org/TR/scxml/#foreach) repeats the shape and
propagates the stop outward, again saying nothing about completed iterations:

> If the evaluation of any child element causes an error, the processor MUST
> cease execution of the `<foreach>` element and the block that contains it.

[§5.4, `<assign>`](https://www.w3.org/TR/scxml/#assign) obliges only that a bad
location or an illegal value place `error.execution` on the internal queue. It
does not state that the target location is left unchanged; that is inference
from "there was nothing valid to write", and it scopes to the single element
either way.

[§3.13, Selecting and Executing Transitions](https://www.w3.org/TR/scxml/#SelectingTransitions)
is the section that would have to establish a transactional boundary if one
existed. It contains no error-handling language at all. Errors are queued
events, not thrown exceptions (§4.9, second paragraph), so an error does not
unwind the transition: the exit set is exited, the transition's content runs up
to the failure point, and the entry set is entered.

### The conformance suite closes the gap the text leaves open

Silence in the Recommendation would leave rollback merely permitted. The
[SCXML IRP](https://www.w3.org/Voice/2013/scxml-irp/) does not.
[Test 156](https://www.w3.org/Voice/2013/scxml-irp/156/test156.txml) is the one
test in the suite that observes a *prior successful* assign after a *later*
element in the same block errored:

> test that an error causes the foreach to stop execution. The second piece of
> executable content should cause an error, so var1 should be incremented only
> once

```xml
<foreach conf:item="2" conf:arrayVar="3">
  <conf:incrementID id="1"/>
  <!-- assign an illegal value to a non-existent var -->
  <assign conf:location="5" conf:illegalExpr=""/>
</foreach>
...
<transition conf:idVal="1=1" conf:targetpass=""/>
<transition conf:targetfail=""/>
```

The increment succeeds; the next element in the same block errors. The test
passes only if `var1 == 1`. A rolling-back implementation observes `var1 == 0`
and takes the fail branch. **An all-or-nothing SCXML processor fails W3C
conformance test 156.**

Supporting tests pin the forward half only and do not bear on retention:
[159](https://www.w3.org/Voice/2013/scxml-irp/159/test159.txml) (failing element
first, later element skipped),
[286](https://www.w3.org/Voice/2013/scxml-irp/286/test286.txml) and
[487](https://www.w3.org/Voice/2013/scxml-irp/487/test487.txml) (assign errors
raise `error.execution`),
[277](https://www.w3.org/Voice/2013/scxml-irp/277/test277.txml) (a failed
`<data>` init leaves the variable created but unbound). No test in the suite
asserts rollback.

Retrieval gap, stated plainly: Appendix B.2 (the ECMAScript data model) was not
retrievable during this reading, so the negative findings on rollback
vocabulary cover §1-§6 only. B.2 binds a single `<assign>` and could not carry
a block-level atomicity rule without contradicting §4.9 and test 156.

## What this means for px-tbv.2

Two separate faults, only one of which is a wording problem.

**The justification is false.** "Matching SCXML's all-or-nothing error story"
cites a story SCXML does not tell. That clause has to go regardless of which
contract is chosen.

**The contract as written makes the downstream use case unimplementable.** The
recorded contract is `{:ok, %Context{}} | {:error, e}`: on error the caller
receives an error and *nothing else*. st-t3f's converter lowers SCXML script
bodies down two paths - `<assign>` sequences and predicator statement programs
- and pins them against one corpus. The `<assign>` path retains prior writes
because a conformant processor must. The predicator path cannot retain them,
because predicator never hands them back. The two paths are then observably
different on the same input, which is the divergence px-h66 was filed to catch,
and it is a hole in the return type rather than a policy disagreement.

## Decision

**Option (b), narrowly: `execute/2` returns the context as of the last
successfully completed statement alongside the error. Commit-or-discard becomes
the caller's policy, not the engine's guarantee.**

    @spec execute(binary() | [Types.instruction()], Context.t()) ::
            {:ok, Context.t()} | {:error, error(), Context.t()}

- The engine's guarantee is stop-on-error, which px-tbv.2 already has right and
  which is what §4.9 actually requires.
- The partial context is a value, not a commit. Contexts are immutable, so
  returning the one at the failure point costs nothing - the same immutability
  the old text invoked to justify discarding is what makes *not* discarding
  free.
- A caller wanting all-or-nothing drops the third element and keeps the context
  it already had. That is one match clause, and it stays the natural thing to
  write, so the ordinary predicator user still gets the safe behavior by
  default.
- Statifier keeps the third element, maps the error to `error.execution`, and
  is conformant with §4.9 and test 156 on both converter paths. It needs no
  documented divergence, which retires option (c).

The three-element error tuple is the deliberate part. Widening every struct in
`lib/predicator/errors/` with a context field would put an evaluation-time
value on types that parse errors also use, and a `{:error, e}` two-tuple with
the context hidden inside `e` makes the partial state easy to miss. A distinct
arity makes the extra value impossible to ignore at the match site and leaves
`evaluate/3`'s existing `{:error, e}` shape untouched. It satisfies CLAUDE.md's
"errors are values, returned as `{:ok, result} | {:error, ...}` tuples".

### Rejected: option (a), keep discard and just fix the prose

Choosing discard on its own merits is defensible for a general-purpose
condition engine - half-applied state is a bad default. But discard as the
*engine's* behavior is not separable from discard as the *only* behavior when
the partial context is never returned, and that forecloses SCXML conformance
for the one downstream consumer already named in the bead. The decision above
keeps discard available as the default caller policy and costs the engine
nothing to offer the alternative, so there is no merit left that (a) uniquely
buys.

### Rejected: option (c), keep discard and document the divergence

A documented divergence is the right move when matching a spec is expensive.
Here it is free. Spending a permanent cross-repo caveat to avoid returning a
value predicator already has in hand is a bad trade.

## Scope: this decision does not move the ISA

The `store` opcode's behavior is unchanged, and no opcode is added, removed, or
altered. This is a contract on `Predicator.execute/2`, the API surface, not on
the instruction set. ADR-0003's versioning obligation is not triggered and no
ISA version bump is owed.

`docs/isa.md` does gain one clarifying sentence from this, in the
statement-program halt contract px-z5m is writing: a program that halts on an
error has no result, and the partially applied context is a property of the
host API rather than of the VM. That wording is handed to px-z5m rather than
written here, because a parallel worktree owns that file.

## Follow-on edits this decision owes

1. px-tbv.2 (this repo): strike the SCXML justification clause, change the
   return type of `execute/2` to the three-element error tuple, and state that
   discard is a caller policy.
2. st-bfq (statifier): the same correction, plus the converter requirement that
   the statement path keep the partial context so both lowering paths agree.
3. px-z5m: the isa.md halt-contract sentence above.
