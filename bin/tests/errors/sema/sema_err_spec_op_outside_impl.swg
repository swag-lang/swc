#global fileprivate

// Special operator functions (opDrop, opAssign, etc.) must live inside an 'impl' block.
struct A
{
    value: s32
}

func opDrop(self: &A) {}                     // swc-expected-error {{sema_err_spec_op_outside_impl}}
func opPostCopy(self: &A, src: const &A) {}  // swc-expected-error {{sema_err_spec_op_outside_impl}}
