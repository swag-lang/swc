#global fileprivate

struct MissingBinaryGeneric
{
    value: s32
}

impl MissingBinaryGeneric
{
    #[Swag.Overload]
    mtd const opBinary(other: MissingBinaryGeneric)->MissingBinaryGeneric { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct WrongUnaryGenericType
{
    value: s32
}

impl WrongUnaryGenericType
{
    #[Swag.Overload]
    mtd(flag: bool) const opUnary()->WrongUnaryGenericType { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct ExtraAssignGeneric
{
    value: s32
}

impl ExtraAssignGeneric
{
    #[Swag.Overload]
    mtd(op: string, suffix: string) opAssign(value: s32) {} // swc-expected-error {{sema_err_spec_op_signature}}
}

struct MissingAffectLiteralGeneric
{
    value: s32
}

impl MissingAffectLiteralGeneric
{
    #[Swag.Overload]
    mtd opAffectLiteral(value: s32) {} // swc-expected-error {{sema_err_spec_op_signature}}
}

struct MissingIndexAssignGeneric
{
    value: s32
}

impl MissingIndexAssignGeneric
{
    #[Swag.Overload]
    mtd opIndexAssign(index: s32, value: s32) {} // swc-expected-error {{sema_err_spec_op_signature}}
}

struct UnexpectedIndexAffectGeneric
{
    value: s32
}

impl UnexpectedIndexAffectGeneric
{
    #[Swag.Overload]
    mtd(op: string) opIndexAffect(index: s32, value: s32) {} // swc-expected-error {{sema_err_spec_op_signature}}
}

struct WrongVisitGenericCount
{
    value: s32
}

impl WrongVisitGenericCount
{
    #[Swag.Overload]
    mtd(ptr: bool) opVisit(stmt: #code void) {} // swc-expected-error {{sema_err_spec_op_signature}}
}
