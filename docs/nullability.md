# Nullability

`#null` qualifies a type whose runtime representation has a null state. It does not model a generic absence of value.

The nullable-capable families are value pointers, block pointers, slices, strings, C strings, `any`, `typeinfo`, functions, and interfaces. Their unqualified forms are non-null by default.

For a nullable-capable `T`, the compiler permits the implicit widening `T` to `#null T`. The inverse conversion is never implicit. It requires either a control-flow proof that the expression is non-null or an explicit `notnull` assertion. Under runtime safety, `notnull` panics when its operand is null.

Using a `#null T` value where a valid runtime address is required — dereferencing a pointer, indexing pointer-backed storage, accessing a member, calling a nullable function — is permitted and behaves like C: the compiler does not demand a narrowing proof at the use site. Proven null dereferences are reported at compile time by the static sanitizer, and the remaining cases are caught by the runtime null-safety guards in checked builds. Enforcement lives at the type boundary instead: a `#null T` never converts implicitly to `T`. Crossing requires a control-flow proof that the expression is non-null, which narrows a stable expression to `T` for the guarded region, or an explicit `notnull` assertion. Assignments, address-taking, and other possible mutations invalidate a narrowing proof.

Provable contradictions are rejected as dead contracts. Three rules share that shape:

- A parameter declared `#null` whose FIRST use, on every path to an exit of the function, is an operation that requires its address. Such a function cannot survive any call with null, so the `#null` in its signature promises what the body forbids. Any other first use — a null test, a copy, passing the parameter along, a `notnull` assertion, or an exit that can leave before the use — keeps the contract alive.
- A `#null` return type that no return path can produce: when every returned expression is provably non-null (an address-of, a value of a non-null declared type, a call whose declared return type is non-null), the qualifier advertises a null that never happens. Functions that can throw are exempt, since their error path synthesizes a null result, and so are interface method implementations, whose signature is fixed by the interface.
- A local declared `#null` that can never hold null: initialized with a provably non-null value, never reassigned null or a possibly-null value, and whose address never escapes. Locals without an initializer default to null, which keeps the qualifier meaningful, and locals declared inside inline or macro expansions are exempt because their annotation belongs to the callee's generic code.

Nullability participates in static type identity, overload signatures, aliases, generic arguments, reflection metadata, and public API fingerprints. It does not change layout or calling convention. Runtime type hashing deliberately ignores the qualifier because `T` and `#null T` share their representation.

`null` may initialize only a nullable-capable type carrying `#null`. Nullable storage defaults to null; non-null storage must receive a non-null initializer unless another explicit initialization rule applies. `undefined` remains an explicit low-level escape hatch and carries no non-null guarantee.
