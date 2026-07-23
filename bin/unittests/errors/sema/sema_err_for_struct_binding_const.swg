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
        v = Cell{5}     // swc-expected-error {{sema_err_assign_to_const}}
    }
}
