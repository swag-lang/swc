#global private

struct NonNullCannotCastItem
{
    value: s32
}

struct NonNullCannotCastDefaultField
{
    value: *NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

struct NonNullCannotCastOpCastBox
{
}

impl NonNullCannotCastOpCastBox
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd const opCast()->#null *NonNullCannotCastItem => null
}

struct NonNullCannotCastNullableOpCastBox
{
}

impl NonNullCannotCastNullableOpCastBox
{
    #[Swag.Implicit]
    mtd const opCast()->#null string => "present-but-optional"
}

func acceptNonNullCannotCast(value: *NonNullCannotCastItem)
{
}

func defaultNonNullCannotCast(value: *NonNullCannotCastItem = null) // swc-expected-error {{sema_err_cannot_cast}}
{
}

func returnNonNullCannotCast()->*NonNullCannotCastItem
{
    return null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: *NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: [*] NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: [..] NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: string = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: cstring = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: typeinfo = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: any = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var item = NonNullCannotCastItem{value: 1}
    var value: *NonNullCannotCastItem = &item
    value = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var item = NonNullCannotCastItem{value: 1}
    var value: *NonNullCannotCastItem = &item
    @init(&value)(null) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    acceptNonNullCannotCast(null) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var nullable: #null *NonNullCannotCastItem = null
    let value: *NonNullCannotCastItem = nullable // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // A migration-compatible legacy type must not launder a constant known to be null.
    let value: *NonNullCannotCastItem = cast(*NonNullCannotCastItem) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    let value = cast(*NonNullCannotCastItem) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // The cast result, not just the source literal, must satisfy the contract.
    let value = cast(*NonNullCannotCastItem) 0'u64 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // Boxing null in 'any' must not hide it from the explicit non-null contract.
    let value: any = cast(any) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    let value = cast(any) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // A boxed zero is a present 'any' value, not a null 'any'.
    let direct: any = 0
    let preboxed: any = cast(any) 0

    // Boxing a typed null pointer also creates a present 'any' value.
    let nullPointer: #null *NonNullCannotCastItem = null
    let boxedPointer: any = cast(any) nullPointer
    #assert(boxedPointer != null)
}

#test
{
    // A constexpr opCast result must satisfy the destination contract after folding.
    let value: *NonNullCannotCastItem = NonNullCannotCastOpCastBox{} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // An explicitly nullable opCast result cannot promise a non-null contract.
    let value: string = NonNullCannotCastNullableOpCastBox{} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // Identical string bytes under distinct nullability contracts must keep distinct types.
    let legacy: string = "same-bytes"
    let optional: #null string = "same-bytes"
    let required: string = "same-bytes"
    #assert(#typeof(legacy) == string)
    #assert(#typeof(optional) == #null string)
    #assert(#typeof(required) == string)
}
