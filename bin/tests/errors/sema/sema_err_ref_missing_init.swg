#global fileprivate

struct A {}

#test
{
    var a: A
    var b: const &A // swc-expected-error {{sema_err_ref_missing_init}}
}
