# Borrow stable inline array arguments

A completed pure leaf inline body can read a plain array directly from a stable
caller variable. No snapshot is needed when all argument evaluations are bare
variables or constants of the exact parameter type, and no parameter, local or
return type can invoke user-defined copy/drop behavior. Calls, generated source,
parameter writes, address/buffer exposure and captures retain existing homes.
The purity result is consumed only after semantic completion, without waiting on
a possibly owning job. The proof is computed once per inline binding group.

The retained Release probe copies a source array into a caller local and invokes
a two-element selector. Its wrapper drops from 36 to 24 final Micro instructions,
22 to 18 memory operations and 12 to 10 explicit RSP accesses. Pushes remain zero.
The callee snapshot disappears; this does not claim elimination of the caller's
own source copy. The files retain both instruction bodies and the exact probe.
No elapsed-time improvement is claimed. Baseline is the preceding spill-cache
lot; the candidate also contains intervening master updates through a5a36abc3.

Validation uses the checkout-local Release compiler and Release programs:
3,631 native tests pass in both JIT and native execution, with the native failure
recovery probes passing their expected-failure checks. The three new cases cover
indexed reads, parameter mutation, later-argument mutation, aliases, indirect
calls and element copy hooks. Focused semantic-error coverage also passes.
An anonymous callback's ignored result now uses the existing generic diagnostic
instead of displaying an empty callee name; its source span and help are preserved.

Remaining work is to prove stability for larger/non-leaf bodies and nontrivial
argument evaluations. This narrow rule does not yet establish parity between the
value-returning SIMD transpose and its in-place API.
