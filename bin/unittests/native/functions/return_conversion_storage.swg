#global private

// An owning text built from a slice through its implicit 'opSet', the way 'String' is.
struct Text
{
    bytes:  [32] u8
    length: u64
}

impl Text
{
    #[Swag.Implicit]
    mtd opSet(value: string)
    {
        .length = value.count
        Swag.memcpy(cast([*] u8) &.bytes[0], value.buffer, value.count)
    }

    mtd const view()->string => Swag.makeString(cast(const [*] u8) &.bytes[0], .length)
}

#[Swag.NoInline]
func passText(text: string)->string => text

// A call sema can evaluate at compile time: the conversion must keep its folded value.
#[Swag.NoInline]
func fixedText()->string => "fixed"

// The call returns a slice and the function a 'Text': the slice must go through the
// conversion, not straight into the caller's return slot as if it were a 'Text'.
#[Swag.NoInline]
func convertedReturn(name: string)->Text
{
    return passText(name)
}

#[Swag.NoInline]
func convertedEarlyReturn(kind: s32, name: string)->Text
{
    if kind == 0 do
        return passText(name)
    var built: Text = "fallback"
    return built
}

#[Swag.NoInline]
func convertedFoldedReturn()->Text
{
    return fixedText()
}

#[Swag.NoInline]
func passConverted(text: Text)->Text => text

#[Swag.NoInline]
func convertedFoldedArgument()->Text => passConverted(fixedText())

#test
{
    let a = convertedReturn("delta")
    Swag.assert(a.view() == "delta")
    let b = convertedEarlyReturn(0, "epsilon")
    Swag.assert(b.view() == "epsilon")
    let c = convertedEarlyReturn(1, "zeta")
    Swag.assert(c.view() == "fallback")
    let d = convertedFoldedReturn()
    Swag.assert(d.view() == "fixed")
    let e = convertedFoldedArgument()
    Swag.assert(e.view() == "fixed")
}
