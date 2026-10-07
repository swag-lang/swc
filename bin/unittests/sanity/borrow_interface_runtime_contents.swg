#global private

interface IRuntimeContentsBorrow
{
    mtd getValue()->s32
}

struct RuntimeContentsBorrowValue
{
    value: s32
}

impl IRuntimeContentsBorrow for RuntimeContentsBorrowValue
{
    mtd impl getValue()->s32 => .value
}

#[Swag.NoInline]
func runtimeContentsBorrowObject(value: IRuntimeContentsBorrow)->*void?
{
    let runtimeValue = cast(*Swag.Interface, &value)
    return runtimeValue.obj
}

// The representation copies the interface's object pointer, preserving its lifetime
// even though the interface parameter's own slot is no longer part of that lifetime.
func runtimeContentsBorrowRejectLocal()->*void?
{
    var object: RuntimeContentsBorrowValue
    var value:  IRuntimeContentsBorrow = object
    return runtimeContentsBorrowObject(value)     // swc-expected-error {{sanity_err_borrow_escape}}
}
