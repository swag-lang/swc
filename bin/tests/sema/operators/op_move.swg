#global internal

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

#test
{
    var v = Vec{1}
    var out: Vec
    out = moveref &v // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var v = Vec{1}
    var out: Vec
    var rr: &&Vec = moveref &v
    out = rr // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var v = Vec{1}
    var bad = moveref v // swc-expected-error {{sema_err_unary_operand_type}}
}
