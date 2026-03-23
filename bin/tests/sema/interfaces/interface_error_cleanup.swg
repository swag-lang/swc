#global fileprivate

struct A {}

interface I
{
    mtd print(me); // swc-expected-error {{sema_err_tok_outside_impl}}
}

impl I for A
{
    mtd impl print() {}
}
