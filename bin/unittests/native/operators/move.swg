#global private
// This file asserts the RAW move mechanics: the test deliberately re-moves an
// already-consumed source (no 'opDrop', so the abandoned bits are untouched).
// Lifecycle safety would poison the source in 'assign', so it is off file-wide.
#global #[Swag.Safety(.Lifecycle, false), Swag.Sanity(.Lifecycle, false)]

struct Vec { x: s32 }

func assign(a: &Vec, b: #move Vec)
{
    a = #move b
}

func assign(a: &Vec, b: Vec)
{
    a = b
}

// Move semantics with overloaded assign
#test
{
    var v = Vec{1}
    var out: Vec
    assign(&out, #move v)
    out = #move v
    @assert(out.x == 1)
}
