#global internal

#test
{
    var a: *s32
    if !a {}
    var b: string
    if !b {}
}

const A = ""
#assert(!A == false)
