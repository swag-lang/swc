# Nullability

`#null` qualifies a type whose runtime representation has a null state. It does not model a generic absence of value.

The nullable-capable families are value pointers, block pointers, slices, strings, C strings, `any`, `typeinfo`, functions, and interfaces. Their unqualified forms are non-null by default.

For a nullable-capable `T`, the compiler permits the implicit widening `T` to `#null T`. The inverse conversion is never implicit. It requires either a control-flow proof that the expression is non-null or an explicit `notnull` assertion. Under runtime safety, `notnull` panics when its operand is null.

A `#null T` expression cannot be used by an operation that requires a valid runtime address. This includes dereferencing a pointer, indexing pointer-backed storage, accessing a member through a nullable pointer or interface, and calling a nullable function. A preceding null check may narrow a stable expression to `T` for the guarded control-flow region. Assignments, address-taking, and other possible mutations invalidate that proof.

Nullability participates in static type identity, overload signatures, aliases, generic arguments, reflection metadata, and public API fingerprints. It does not change layout or calling convention. Runtime type hashing deliberately ignores the qualifier because `T` and `#null T` share their representation.

`null` may initialize only a nullable-capable type carrying `#null`. Nullable storage defaults to null; non-null storage must receive a non-null initializer unless another explicit initialization rule applies. `undefined` remains an explicit low-level escape hatch and carries no non-null guarantee.
