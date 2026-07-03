#global private

// A `character`/`bool` literal argument is a coercible constant: a real call coerces it to the
// parameter type. When the callee is inlined, the binding must adopt the parameter type too,
// otherwise the materialized body sees the raw `character`/`bool` type — e.g. `arr[vkey]` would
// be rejected as a non-integer index, and `vkey + 1` would compute in the wrong type.

var arr: [256] u8

#[Swag.Inline]
func storeAt(vkey: u8)->u8
{
    arr[vkey] = vkey + 1
    return arr[vkey]
}

#[Swag.Inline]
func toByte(on: bool)->u8
{
    return cast(u8) on + 10
}

// Unmarked twins: auto-inline candidates under `-bc release`.
func storeAtAuto(vkey: u8)->u8
{
    arr[vkey] = vkey + 1
    return arr[vkey]
}

#test
{
    @assert(storeAt('A') == 66)
    @assert(arr[65] == 66)
    @assert(toByte(true) == 11)
    @assert(toByte(false) == 10)
    @assert(storeAtAuto('B') == 67)
    @assert(arr[66] == 67)
}
