#global private

// A pointer-like value answers a bool cast with its first pointer-sized word against null, so
// only a '#null' text or slice asks a question there. An empty one is still present.

func stringToBool()->bool
{
    let empty              = cast(#null string) null
    let text: #null string = "x"
    let none: #null string = ""
    return !cast(bool) empty and cast(bool) text and cast(bool) none
}

func sliceToBool()->bool
{
    let empty                  = cast(#null [..] s32) null
    var data: [2] s32          = [1, 2]
    let values: #null [..] s32 = data
    return !cast(bool) empty and cast(bool) values
}

#test
{
    @assert(stringToBool())
    @assert(sliceToBool())
}