#global private

#test
{
    var a: *s32?
    if !a {}
    var b: string?
    if !b {}
    var c: [..] s32?
    if !c {}
    var d: [*] bool?
    if !d {}
    var e: (func())?
    if !e {}
    var f: typeinfo?
    if !f {}
    Swag.assert(!a)
    Swag.assert(!b)
    Swag.assert(!c)
    Swag.assert(!d)
    Swag.assert(!e)
    Swag.assert(!f)
}

#test
{
    var a: *s32?
    var b: *s32?
    if !a or !b {}
    Swag.assert(!a or !b)
}

#test
{
    var a: s32
    if a and a {}
    Swag.assert((a and a) == false)
}

#test
{
    var a: *s32?
    var b: *s32?

    Swag.assert(!a or !b)

    var ax: s32
    a = &ax
    Swag.assert(!a or !b)

    var bx: s32
    b = &bx
    Swag.assert((!a or !b) == false)
}

#test
{
    var a: s32

    Swag.assert((a and a) == false)
    Swag.assert(a or !a)
    Swag.assert((a or a) == false)

    a = 1
    Swag.assert(a and a)
    Swag.assert(a or !a)
    Swag.assert(a or a)
}

#test
{
    var a: *s32?

    Swag.assert((a and a) == false)
    Swag.assert(a or !a)
    Swag.assert((a or a) == false)

    var ax: s32
    a = &ax
    Swag.assert(a and a)
    Swag.assert(a or !a)
    Swag.assert(a or a)
}

#test
{
    var s: string?
    Swag.assert(!s)

    s = "abc"
    Swag.assert(!s == false)
}

// A slice answers a condition with its data pointer, so only a '?' slice asks a question.
#test
{
    var a: [2] s32
    var s: [..] s32? = a
    Swag.assert(!s == false)

    s = null
    Swag.assert(!s)
}
