#global private

// A local captured by address in a closure passed straight to a call is observed by that call: it
// keeps its default value even when nothing else in the function reads it.

func callCapture(body: func||()->u32)->u32 => body()

struct CapturedBox
{
    value: u32
}

func incrementThroughReturn()->u32
{
    var box: CapturedBox
    return callCapture(func|&box|()->u32 { box.value += 1; return box.value })
}

func incrementThroughLocal()->u32
{
    var box: CapturedBox
    let result = callCapture(func|&box|()->u32 { box.value += 1; return box.value })
    return result
}

#test
{
    for 4
    {
        Swag.assert(incrementThroughReturn() == 1)
        Swag.assert(incrementThroughLocal() == 1)
    }
}
