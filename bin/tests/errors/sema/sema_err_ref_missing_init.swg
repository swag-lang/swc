#global fileprivate

struct S {}

// References must be bound at declaration time; every reference-typed binding without an initializer is an error.
#test
{
    var a: S
    var b: const &S              // swc-expected-error {{sema_err_ref_missing_init}}
}

#test
{
    var x: const &s32            // swc-expected-error {{sema_err_ref_missing_init}}
}
