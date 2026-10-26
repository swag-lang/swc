#global private

/**
# The `#returntype` Type
`#returntype` names the current function's return type. It lets you declare the value a
function builds without repeating that type, which matters most for long, generic, or unnamed
return types such as tuples.
*/
#test
{
    func toto()->s32
    {
        var result: #returntype     // '#returntype' resolves to 's32' in this context.
        result = 10
        return result
    }

    Swag.assert(toto() == 10)
}

/**
# Building the Result in Place
A local that every return in its scope returns is built directly in the caller's memory: filling
it field by field costs no copy at the end of the function, and returning it runs no hook. The
compiler decides this on its own, for any local of the return type; nothing in the program has
to ask for it.

Returning an aggregate literal is built in the caller's memory as well, so
`return RGB{0.5, 0.1, 1.0}` needs no local at all. Reach for a local when the value is filled in
step by step.
*/
#test
{
    struct RGB
    {
        x, y, z: f64
    }

    func getWhite()->RGB
    {
        var result: #returntype
        result.x = 0.5
        result.y = 0.1
        result.z = 1.0
        return result
    }

    let {x: r, y: g, z: b} = getWhite()
    Swag.assert(r == 0.5)
    Swag.assert(g == 0.1)
    Swag.assert(b == 1.0)
}

/**
# Returning Arrays Efficiently
Large values such as arrays benefit the most: the array below is filled where the caller keeps
it, without an intermediate copy.
*/
#test
{
    func toto()->[255] s32
    {
        var result: #returntype
        for i in 255 do
            result[i] = i
        return result
    }

    var arr = toto()
    Swag.assert(arr[0] == 0)
    Swag.assert(arr[100] == 100)
    Swag.assert(arr[254] == 254)
}

/**
# An Ordinary Local
A `#returntype` local is an ordinary local: it can be read by the value a `return` gives back,
and a function can still return something else. Building in place never changes what a program
observes. A return captures its value first, so a `defer` that runs afterwards neither sees the
local change under it nor changes what was returned.
*/
#test
{
    func clampedDouble(value: s32)->s32
    {
        var result: #returntype = value * 2
        if result < 0 do
            return 0
        return Swag.min(result, 100)
    }

    Swag.assert(clampedDouble(-4) == 0)
    Swag.assert(clampedDouble(4) == 8)
    Swag.assert(clampedDouble(80) == 100)

    func counted()->s32
    {
        var result: #returntype = 1
        defer result += 1
        return result
    }

    Swag.assert(counted() == 1)
}
