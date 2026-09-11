#global private

interface IMarkedValue
{
    mtd value()->s32
}

struct MarkedBase {}

impl IMarkedValue for MarkedBase
{
    mtd impl value()->s32 => 1
}

struct MarkedDerived { using base: MarkedBase }

impl MarkedDerived
{
    mtd impl value()->s32     => 2     // swc-expected-error {{sema_err_method_impl_outside_interface}}
    mtd impl unrelated()->s32 => 3     // swc-expected-error {{sema_err_method_impl_outside_interface}}
}

struct(T) MarkedGeneric { item: T }
var generic: MarkedGeneric's32

impl MarkedGeneric
{
    mtd impl unrelated()->s32 => 4     // swc-expected-error {{sema_err_method_impl_outside_interface}}
}

struct MarkedExplicit {}

impl MarkedExplicit
{
    func impl value(me)->s32   => 5     // swc-expected-error {{sema_err_method_impl_outside_interface}}
    mtd const impl read()->s32 => 6     // swc-expected-error {{sema_err_method_impl_outside_interface}}
}
