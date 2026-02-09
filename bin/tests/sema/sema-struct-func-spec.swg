#global internal

struct SpecA
{
    value: s32
}

impl SpecA
{
    mtd opDrop() {}

    mtd opEquals(value: s32) -> bool { return true; }
    mtd opEquals(value: f32) -> bool { return false; }

    mtd opMagic() {} // swc-expected-error {{sema_err_spec_op_unknown}}

    mtd opCount() -> s32 { return 0; } // swc-expected-error {{sema_err_spec_op_signature}}
}

func opDrop(self: &SpecA) {} // swc-expected-error {{sema_err_spec_op_outside_impl}}

struct SpecB
{
    value: s32
}

impl SpecB
{
    mtd opDrop() {}
    mtd opPostCopy() {}
    mtd opPostMove() {}
    mtd opCount() -> u64 { return 0; }
    mtd opData() -> *s32 { return null; }
    mtd opCast() -> s32 { return 0; }
    mtd opEquals(value: s32) -> bool { return true; }
    mtd opCmp(value: s32) -> s32 { return 0; }
    mtd opBinary(other: SpecB) -> SpecB { return {}; }
    mtd opUnary() -> SpecB { return {}; }
    mtd opAssign(value: s32) {}
    mtd opAffect(value: s32) {}
    mtd opAffectLiteral(value: s32) {}
    mtd opSlice(low: u64, up: u64) -> string { return ""; }
    mtd opIndex(index: s32) -> s32 { return 0; }
    mtd opIndexAssign(index: s32, value: s32) {}
    mtd opIndexAffect(index: s32, value: s32) {}
    //mtd opVisit(stmt: #code) {}
}
