#global fileprivate // swc-option suite-test

struct Vec { x: s32 }

#[Swag.Overload]
func assign(a: &Vec, b: &&Vec)
{
    a = #move b
}

#[Swag.Overload]
func assign(a: &Vec, b: Vec)
{
    a = b
}

#test
{
    var v = Vec{1}
    var out: Vec
    assign(&out, moveref &v)
    out = #move moveref &v
    var rr: &&Vec = moveref &v
    out = #move rr
}



