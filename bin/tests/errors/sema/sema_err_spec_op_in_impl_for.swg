#global fileprivate

struct SpecB
{
    value: s32
}

interface I {}
impl I for SpecB
{
    mtd opDrop() {} // swc-expected-error {{sema_err_spec_op_in_impl_for}}
}
