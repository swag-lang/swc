#global private

// The by-value struct binding of 'for' is a const reference: mutation requires '&name'.

struct Cell
{
    x: s32
}

#test
{
    var arr: [2] Cell
    for v in arr
    {
        v.x += 1     // swc-expected-error {{sema_err_assign_to_const}}
    }
}

#test
{
    var arr: [2] Cell
    for v in arr
    {
        v = Cell{5}     // swc-expected-error {{sema_err_assign_to_let}}
    }
}

// An array is stored in its binding, so an immutable binding reaches its elements:
// '&name' over a 'let' or 'const' array binds a const reference too. Without this the
// assignment used to compile and then be silently dropped.

func makeCells()->[2] Cell => [Cell{1}, Cell{2}]

#test
{
    let arr = makeCells()
    for &v in arr
    {
        v.x = 5     // swc-expected-error {{sema_err_assign_to_const}}
    }
}

#test
{
    let values = [1, 2]
    for &v in values
    {
        dref v = 5     // swc-expected-error {{sema_err_assign_to_const}}
    }
}

#test
{
    const values = [1, 2]
    for &v in values
    {
        dref v = 5     // swc-expected-error {{sema_err_assign_to_const}}
    }
}
