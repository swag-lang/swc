#global internal

struct SpecA
{
    value: s32
}

impl SpecA
{
    mtd opDrop() {}

    // swc-expected-error@(+1,+2) {{sema_err_already_defined}}
    mtd opEquals(value: s32) -> bool { return true; }
    mtd opEquals(value: f32) -> bool { return false; }

    mtd opMagic() {} // swc-expected-error {{sema_err_special_function_unknown}}

    mtd opCount() -> s32 { return 0; } // swc-expected-error {{sema_err_special_function_signature}}
}

func opDrop(self: &SpecA) {} // swc-expected-error {{sema_err_special_function_outside_impl}}
