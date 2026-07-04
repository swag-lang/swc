#global private
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
