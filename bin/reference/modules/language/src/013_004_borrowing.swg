#global private

/**
# Borrowing

A **view** is a value that reads storage it does not own: a pointer, a reference, a
slice, a 'string', an 'any', an interface, a closure capturing by address. Swag has one
rule about views, and the compiler enforces it on every program:

> A view must not outlive the storage it views.

Nothing has to be written down for this. There are no lifetime parameters, no borrow
sigils, no ownership annotations: the compiler infers what it needs from the code as
written. What it cannot prove, it says nothing about.

The rule is part of the language, not of the sanity tooling. '#[Swag.Sanity]' and
'buildCfg.sanityGuards' select which *proofs of a runtime fault* the compiler attempts —
use after free, use after move, a read of uninitialized storage — and none of them
reaches the rule below. A guarantee a caller can switch off is not a guarantee, so
whether a program is accepted never depends on an attribute.
*/

/**
# Escaping the Frame

Function-local storage dies with the frame, so a view of it must not leave: not through
a return value, not into a global, not through a caller-visible pointer, not inside a
closure that itself escapes.

This includes views of what a value OWNS. A local 'Core.String' frees its buffer when it
drops, and a local drops at the end of its scope, so a 'string' view of it dies with the
owner even though the buffer lives on the heap.
*/
var borrowGlobalBuffer: [4] u8
var borrowGlobalValue:  s32

#test
{
    func makeView()->const [..] u8
    {
        // var buf: [4] u8
        // return cast(const [..] u8) buf  // Uncomment: error, the view outlives 'buf'
        return cast(const [..] u8) borrowGlobalBuffer     // A global's storage is fine
    }

    @assert(@countof(makeView()) == 4)
}

/**
A temporary is the same story with a shorter life: it dies at the end of the statement
that built it, so binding a view of one is already too late. Name the owner first.
*/

/**
# Across Calls

The rule is not confined to one function body. Each function carries a summary of what
it does with the storage its parameters view: whether the result borrows a parameter,
whether the callee keeps one, whether it frees one, whether it can move what a parameter
owns. Summaries are inferred, never written, they chain through wrappers, and they cross
module boundaries in the generated module API (the 'Swag.BorrowSummary' attribute).

The call site is then judged against what was really passed in. Wrapping a borrowing
function does not hide the borrow.
*/
#test
{
    func passthrough(p: *s32)->*s32
    {
        return p
    }

    func wrapper(p: *s32)->*s32
    {
        return passthrough(p)     // Inherits the summary of 'passthrough'
    }

    func caller()->*s32
    {
        // var v: s32
        // return wrapper(&v)  // Uncomment: error, borrows a local through the chain
        return wrapper(&borrowGlobalValue)     // Caller-owned data flows through
    }

    @assert(caller() == &borrowGlobalValue)
}

/**
An aggregate can carry several independent borrows. Every parameter origin is kept in
the summaries, and local borrows are tracked by field path, so assigning a sibling field
neither hides nor inherits another field's borrow. Constant array indices are tracked
independently; a dynamic index conservatively overlaps every element.
*/
#test
{
    struct Views
    {
        local:  *s32
        global: *s32
    }

    var local: s32
    var views: Views = undefined
    views.local  = &local
    views.global = &borrowGlobalValue
    @assert(views.global == &borrowGlobalValue)
}

/**
# Arguments a Callee Keeps

A callee that stores its parameter into storage outliving the call makes any borrowed
argument escape, whatever happens to the call result. Storing one parameter into storage
reachable from ANOTHER — 'container.add(&item)' — is summarized as a pair, and the call
site errors whenever the container provably outlives what was stored in it: a global
container, or a local container declared in a shallower scope than the borrowed source.

Reaching into a container counts even when it goes through the container's own heap
buffer. A '[*] T' held by a value with an owning lifecycle addresses memory that value
frees when it dies, so a store through it — directly, through a local, or through an
accessor method — is a store into the container. That is what makes filling a collection
of views from a per-iteration owner an error:

```swag
var set: HashSet'(string)
for line in lines
{
    var key: String = build(line)
    set.add(key)     // Error: 'set' outlives 'key', and it keeps a view of it
}
```

A plain '*T' field is deliberately not treated this way: a single-object pointer inside
an owner is just as often a back-reference to something it does not own.
*/
var borrowGlobalStash: #null *s32

func borrowStash(p: *s32)
{
    borrowGlobalStash = p     // Legal here: 'p' is caller-owned. Judged at call sites.
}

#test
{
    func caller()
    {
        // var v: s32
        // borrowStash(&v)  // Uncomment: error, the callee keeps the borrow
        borrowStash(&borrowGlobalValue)     // A global outlives everything
    }

    caller()
    @assert(borrowGlobalStash == &borrowGlobalValue)
}

/**
# Storage That Moves Under a View

Outliving the storage is not only about scopes. A container that grows, shrinks or is
released moves the very bytes a view was reading, and the view is stale from that moment
even though its owner is still perfectly alive.

The compiler knows which methods can do this: a method that hands what its receiver owns
to the allocator — directly, or through any chain of calls — is summarized as one that
can move the payload. A method that only reads or assigns fields is not, and a 'const'
method cannot be. Taking the view again after the change is the fix.

```swag
var text: String
text.append("hello")

let view = text.toString()     // A view into 'text's buffer
text.append(" world")          // Error: 'append' can move that buffer...
Console.print(view)            // ...and this reads the old one
```

Two things are deliberately not affected. A view of the value ITSELF — a pointer to it, or
an interface built from it — keeps addressing the same slot however much the payload is
reallocated: it is the handle the change is made through, not something the change
invalidates. And a value that merely *reaches* the container is not a view into it: a
factory method handing back a fresh object that holds a back-reference to its receiver
survives any reallocation of what that receiver owns. Only a result read OUT of the
payload goes stale, and the summaries record that as a separate fact.
*/

/**
# Iterating and Mutating

The same rule inside a loop is what other languages call iterator invalidation. A loop
reads a snapshot of the collection, so adding to it, removing from it or clearing it
while it is being iterated is an error.

Iteration is tracked at the storage level, so mutating a sibling field of a shared owner
is fine. Mutating and then leaving the loop right away — the find-then-remove-then-return
shape — is fine too: the snapshot is never read again.
*/
#test
{
    var values: [4] s32
    var total:  s32
    for v in values do
        total += v
    @assert(total == 0)
}

/**
# What the Rule Does Not Do

It never guesses. Where the compiler cannot see the whole story — a pointer whose
provenance is opaque, a conditional release the flow state cannot follow — it stays
silent rather than reject a correct program. A missed case is a bug in the analysis; a
rejected correct program would be a bug in the language.

There is no opt-out, so there is also nothing to reach for when a program is rejected:
the answer is always to make the storage really outlive the view. Own the data instead
of viewing it, move the storage to where it lives long enough, or take the view again
after the change.
*/
