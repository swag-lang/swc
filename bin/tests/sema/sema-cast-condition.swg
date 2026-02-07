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

#test
{
    var a: s32
    if a and a {}
}

#test
{
    var a: *s32
    var b: *s32

    @assert(!a or !b)

    var ax: s32
    a = &ax
    @assert(!a or !b)

    var bx: s32
    b = &bx
    @assert((!a or !b) == false)
}

#test
{
    var a: s32

    @assert((a and a) == false)
    @assert(a or !a)
    @assert((a or a) == false)

    a = 1
    @assert(a and a)
    @assert(a or !a)
    @assert(a or a)
}

#test
{
    var a: *s32

    @assert((a and a) == false)
    @assert(a or !a)
    @assert((a or a) == false)

    var ax: s32
    a = &ax
    @assert(a and a)
    @assert(a or !a)
    @assert(a or a)
}
