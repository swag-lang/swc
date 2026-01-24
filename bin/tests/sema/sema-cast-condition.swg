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
    var f: typeinfo
    if !f {}
}

#test
{
    var a: *s32
    var b: *s32
    if !a or !b {}
}

const A = ""
#assert(!A == false)
