#global private

struct NonNullCannotCastItem
{
    value: s32
}

func acceptNonNullCannotCast(value: #nonull *NonNullCannotCastItem)
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
