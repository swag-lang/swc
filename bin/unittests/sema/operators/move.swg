#global private

struct Vec { x: s32 }

func assign(a: *Vec, b: #move Vec)
{
    dref a = #move b
}

func assign(a: *Vec, b: Vec)
{
    dref a = b
}

func semaTest001()
{
    var v = Vec{1}
    var out: Vec
    assign(&out, #move v)
    out = #move v
}
