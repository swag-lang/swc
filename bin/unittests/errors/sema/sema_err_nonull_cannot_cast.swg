#global private

struct NonNullCannotCastItem
{
    value: s32
}

struct NonNullCannotCastDefaultField
{
    value: #nonull *NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

struct NonNullCannotCastOpCastBox
{
}

impl NonNullCannotCastOpCastBox
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd const opCast()->*NonNullCannotCastItem => null
}

struct NonNullCannotCastNullableOpCastBox
{
}

impl NonNullCannotCastNullableOpCastBox
{
    #[Swag.Implicit]
    mtd const opCast()->#null string => "present-but-optional"
}

func acceptNonNullCannotCast(value: #nonull *NonNullCannotCastItem)
{
}

func defaultNonNullCannotCast(value: #nonull *NonNullCannotCastItem = null) // swc-expected-error {{sema_err_cannot_cast}}
{
}

func returnNonNullCannotCast()->#nonull *NonNullCannotCastItem
{
    return null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull *NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull [*] NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull [..] NonNullCannotCastItem = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull string = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull cstring = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull typeinfo = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var value: #nonull any = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var item = NonNullCannotCastItem{value: 1}
    var value: #nonull *NonNullCannotCastItem = &item
    value = null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var item = NonNullCannotCastItem{value: 1}
    var value: #nonull *NonNullCannotCastItem = &item
    @init(&value)(null) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    acceptNonNullCannotCast(null) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var nullable: #null *NonNullCannotCastItem = null
    let value: #nonull *NonNullCannotCastItem = nullable // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // A migration-compatible legacy type must not launder a constant known to be null.
    let value: #nonull *NonNullCannotCastItem = cast(*NonNullCannotCastItem) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    let value = cast(#nonull *NonNullCannotCastItem) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // The cast result, not just the source literal, must satisfy the contract.
    let value = cast(#nonull *NonNullCannotCastItem) 0'u64 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // Boxing null in 'any' must not hide it from the explicit non-null contract.
    let value: #nonull any = cast(any) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    let value = cast(#nonull any) null // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // A boxed zero is a present 'any' value, not a null 'any'.
    let direct: #nonull any = 0
    let preboxed: #nonull any = cast(any) 0

    // Boxing a typed null pointer also creates a present 'any' value.
    let nullPointer: *NonNullCannotCastItem = null
    let boxedPointer: #nonull any = cast(any) nullPointer
    #assert(boxedPointer != null)
}

#test
{
    // A constexpr opCast result must satisfy the destination contract after folding.
    let value: #nonull *NonNullCannotCastItem = NonNullCannotCastOpCastBox{} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // An explicitly nullable opCast result cannot promise a non-null contract.
    let value: #nonull string = NonNullCannotCastNullableOpCastBox{} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // Identical string bytes under distinct nullability contracts must keep distinct types.
    let legacy: string = "same-bytes"
    let optional: #null string = "same-bytes"
    let required: #nonull string = "same-bytes"
    #assert(#typeof(legacy) == string)
    #assert(#typeof(optional) == #null string)
    #assert(#typeof(required) == #nonull string)
}
