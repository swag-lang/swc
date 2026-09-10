#global private

#test
{
    var a: *s32?
    if not a {}
    var b: string?
    if not b {}
    var c: [..] s32?
    if not c {}
    var d: [*] bool?
    if not d {}
    var e: (func())?
    if not e {}
    var f: typeinfo?
    if not f {}
    Swag.assert(not a)
    Swag.assert(not b)
    Swag.assert(not c)
    Swag.assert(not d)
    Swag.assert(not e)
    Swag.assert(not f)
}

#test
{
    var a: *s32?
    var b: *s32?
    if not a or not b {}
    Swag.assert(not a or not b)
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

    Swag.assert(not a or not b)

    var ax: s32
    a = &ax
    Swag.assert(not a or not b)

    var bx: s32
    b = &bx
    Swag.assert((not a or not b) == false)
}

#test
{
    var a: s32

    Swag.assert((a and a) == false)
    Swag.assert(a or not a)
    Swag.assert((a or a) == false)

    a = 1
    Swag.assert(a and a)
    Swag.assert(a or not a)
    Swag.assert(a or a)
}

#test
{
    var a: *s32?

    Swag.assert((a and a) == false)
    Swag.assert(a or not a)
    Swag.assert((a or a) == false)

    var ax: s32
    a = &ax
    Swag.assert(a and a)
    Swag.assert(a or not a)
    Swag.assert(a or a)
}

#test
{
    var s: string?
    Swag.assert(not s)

    s = "abc"
    Swag.assert(not s == false)
}

// A slice answers a condition with its data pointer, so only a '?' slice asks a question.
#test
{
    var a: [2] s32
    var s: [..] s32? = a
    Swag.assert(not s == false)

    s = null
    Swag.assert(not s)
}
