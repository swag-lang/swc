#global fileprivate

struct MissingConstUnaryMe
{
    value: s32
}

impl MissingConstUnaryMe
{
    #[Swag.Overload]
    mtd(op: string) opUnary()->MissingConstUnaryMe { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct(T) GenericMissingConstUnaryMe
{
    value: T
}

impl GenericMissingConstUnaryMe
{
    #[Swag.Overload]
    mtd(op: string) opUnary()->GenericMissingConstUnaryMe'T { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}

struct BadMultiIndexGet {}
struct BadMultiIndexSet {}
struct BadMultiIndexAssign {}

impl BadMultiIndexGet
{
    mtd opIndex(row: s32, col: u32) -> s32 { return 0 } // swc-expected-error {{sema_err_spec_op_signature}}
}

impl BadMultiIndexSet
{
    mtd opIndexSet(row: s32, col: u32, value: s32) {} // swc-expected-error {{sema_err_spec_op_signature}}
}

impl BadMultiIndexAssign
{
    mtd(op: string) opIndexAssign(row: s32, col: u32, value: s32) {} // swc-expected-error {{sema_err_spec_op_signature}}
}

#test
{
    var value = MissingConstUnaryMe{value: 1}
    let result = -value
    #assert(#typeof(result) == MissingConstUnaryMe)
}

#test
{
    var value: GenericMissingConstUnaryMe's32 = {value: 1}
    let result = -value
    #assert(#typeof(result) == GenericMissingConstUnaryMe's32)
}

#test
{
    var get = BadMultiIndexGet{}
    let value = get[0, 0]

    var set = BadMultiIndexSet{}
    set[0, 0] = value

    var assign = BadMultiIndexAssign{}
    assign[0, 0] += value
}
