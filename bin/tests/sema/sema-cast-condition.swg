#global internal

#test
{
    var a: *s32
    if !a {}
    var b: string
    if !b {}
    var c: [..] s32
    if !c {}
    var d: [*] bool
    if !d {}
    var e: func()
    if !e {}
}

const A = ""
#assert(!A == false)
