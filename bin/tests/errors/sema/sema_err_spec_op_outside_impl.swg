#global fileprivate

struct SpecA
{
    value: s32
}

func opDrop(self: &SpecA) {} // swc-expected-error {{sema_err_spec_op_outside_impl}}
