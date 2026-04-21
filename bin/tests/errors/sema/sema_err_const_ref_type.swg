#global fileprivate

struct A {}

#test
{
    var a: A
    const b: const &A // swc-expected-error {{sema_err_const_ref_type}}
}
