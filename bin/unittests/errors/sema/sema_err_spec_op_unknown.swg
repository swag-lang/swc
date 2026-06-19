#global fileprivate

struct SpecA
{
    value: s32
}

impl SpecA
{
    mtd opMagic() {} // swc-expected-error {{sema_err_spec_op_unknown}}
}
