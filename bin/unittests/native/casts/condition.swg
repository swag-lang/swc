#global private

#test
{
    var a: #null *s32
    if !a {}
    var b: #null string
    if !b {}
    var c: #null [..] s32
    if !c {}
    var d: #null [*] bool
    if !d {}
    var e: #null func()
    if !e {}
    var f: #null typeinfo
    if !f {}
    @assert(!a)
    @assert(!b)
    @assert(!c)
    @assert(!d)
    @assert(!e)
    @assert(!f)
}

#test
{
    var a: #null *s32
    var b: #null *s32
    if !a or !b {}
    @assert(!a or !b)
}

#test
{
    var a: s32
    if a and a {}
    @assert((a and a) == false)
}

#test
{
    var a: #null *s32
    var b: #null *s32

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
    var a: #null *s32

    @assert((a and a) == false)
    @assert(a or !a)
    @assert((a or a) == false)

    var ax: s32
    a = &ax
    @assert(a and a)
    @assert(a or !a)
    @assert(a or a)
}

#test
{
    var s: #null string
    @assert(!s)

    s = "abc"
    @assert(!s == false)
}

// A slice answers a condition with its data pointer, so only a '#null' slice asks a question.
#test
{
    var a: [2] s32
    var s: #null [..] s32 = a
    @assert(!s == false)

    s = null
    @assert(!s)
}
