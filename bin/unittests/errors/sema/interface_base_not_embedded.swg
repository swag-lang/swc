#global private

struct ItfBase { x: s32 }
struct ItfShifted { y: s32; using base: ItfBase }
struct ItfByPointer { using base: *ItfBase }

interface IItfShape is ItfBase { mtd area()->s32 }

impl IItfShape for ItfShifted     // swc-expected-error {{sema_err_interface_base_not_embedded}}
{
    mtd area()->s32 => .y
}

impl IItfShape for ItfByPointer     // swc-expected-error {{sema_err_interface_base_not_embedded}}
{
    mtd area()->s32 => 0
}
