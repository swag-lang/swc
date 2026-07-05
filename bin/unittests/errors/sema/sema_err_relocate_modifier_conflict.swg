#global private

// '#relocate' already implies an uninitialized target and an abandoned source: it
// cannot be combined with '#move' or '#nodrop'.
struct Vec { x: s32 }
impl Vec
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

#test
{
    var a, b: Vec
    a = #relocate #move b // swc-expected-error {{sema_err_relocate_modifier_conflict}}
}

#test
{
    var a, b: Vec
    a = #nodrop #relocate b // swc-expected-error {{sema_err_relocate_modifier_conflict}}
}
