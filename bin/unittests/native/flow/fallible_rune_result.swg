#global private

// A fallible function whose result type is 'rune'. A rune is integer-like but carries its
// own constant kind, so the zero result synthesized for the failure path had no
// materialization arm and lowering stopped on an internal error. Both the success value
// and the failure default must reach the caller.
struct RuneError
{
    using base: Swag.BaseError
}

func readRune(ok: bool)->rune fail
{
    if !ok do
        fail RuneError{base: Swag.BaseError{"nope"}}
    return 'é'rune
}

#test
{
    let value = catch readRune(true) as err
    Swag.assert(err == null)
    Swag.assert(value == 'é'rune)
}

#test
{
    let value = catch readRune(false) as err
    Swag.assert(err != null)
    Swag.assert(cast(u32) value == 0)
}
