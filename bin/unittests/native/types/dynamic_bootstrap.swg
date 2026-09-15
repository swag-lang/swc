#global private

interface IDynamicBootstrapReader
{
    mtd read() fail
}

struct DynamicBootstrapReader {}
struct DynamicBootstrapError { code: s32 }

// This unrelated fallible method needs runtime error storage. Preparing it while
// evaluating the runtime configuration would create a bootstrap dependency cycle.
impl IDynamicBootstrapReader for DynamicBootstrapReader
{
    mtd read() fail
    {
        fail DynamicBootstrapError{17}
    }
}

func dynamicBootstrapValue()->s32
{
    var boxed: any = 42's32
    return (cast #try (*s32) boxed)![]
}

const dynamicBootstrapResult = #run dynamicBootstrapValue()

#test
{
    Swag.assert(dynamicBootstrapResult == 42)
}
