#global private

// A method marked 'impl' in an interface implementation is one of the interface's methods with the
// same parameters and return type: the interface table calls it through that signature.

interface IImplShape
{
    mtd area()->f32
    mtd scale(factor: f32)
}

struct ImplWrongReturn
{
    side: f32
}

impl IImplShape for ImplWrongReturn
{
    mtd impl area()->s32 => 1     // swc-expected-error {{sema_err_impl_method_signature_mismatch}}
    mtd impl scale(factor: f32) { .side *= factor }
}

struct ImplWrongParameter
{
    side: f32
}

impl IImplShape for ImplWrongParameter
{
    mtd impl area()->f32 => .side * .side
    mtd impl scale(factor: s32) { .side *= cast(f32, factor) }     // swc-expected-error {{sema_err_impl_method_signature_mismatch}}
}

struct ImplUnknownMethod
{
    side: f32
}

impl IImplShape for ImplUnknownMethod
{
    mtd impl area()->f32 => .side * .side
    mtd impl scale(factor: f32) { .side *= factor }
    mtd impl volume()->f32 => 0     // swc-expected-error {{sema_err_impl_method_not_in_interface}}
}
