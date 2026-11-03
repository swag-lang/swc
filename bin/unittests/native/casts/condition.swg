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
    Swag.require(not a)
    Swag.require(not b)
    Swag.require(not c)
    Swag.require(not d)
    Swag.require(not e)
    Swag.require(not f)
}

#test
{
    var a: *s32?
    var b: *s32?
    if not a or not b {}
    Swag.require(not a or not b)
}

#test
{
    var a: s32
    if a and a {}
    Swag.require((a and a) == false)
}

#test
{
    var a: *s32?
    var b: *s32?

    Swag.require(not a or not b)

    var ax: s32
    a = &ax
    Swag.require(not a or not b)

    var bx: s32
    b = &bx
    Swag.require((not a or not b) == false)
}

#test
{
    var a: s32

    Swag.require((a and a) == false)
    Swag.require(a or not a)
    Swag.require((a or a) == false)

    a = 1
    Swag.require(a and a)
    Swag.require(a or not a)
    Swag.require(a or a)
}

#test
{
    var a: *s32?

    Swag.require((a and a) == false)
    Swag.require(a or not a)
    Swag.require((a or a) == false)

    var ax: s32
    a = &ax
    Swag.require(a and a)
    Swag.require(a or not a)
    Swag.require(a or a)
}

#test
{
    var s: string?
    Swag.require(not s)

    s = "abc"
    Swag.require(not s == false)
}

// A slice answers a condition with its data pointer, so only a '?' slice asks a question.
#test
{
    var a: [2] s32
    var s: [..] s32? = a
    Swag.require(not s == false)

    s = null
    Swag.require(not s)
}
