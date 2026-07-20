#global private
/**
# Introduction to Closures in Swag

Swag supports limited closures, allowing functions to capture variables from
their surrounding scope. Up to 64 bytes can be captured without heap allocation.

A by-value capture is a plain byte copy into the closure: the closure never runs
'opPostCopy' on the way in and never drops the captured value. Only simple types
(without 'opDrop', 'opPostCopy', or 'opPostMove', and not marked '#[Swag.NoCopy]')
can therefore be captured by value; other types must be captured by reference
with '&'.
*/

/**
# Declaring a Closure

A closure is declared like a lambda, with captured variables listed between '|...|'
before the parameter list. The type uses 'func||(...)'.
*/
#test
{
    let a = 125
    let b = 521

    let fct: func||() = func|a, b|()
    {
        @assert(a == 125)
        @assert(b == 521)
    }

    fct()
}

/**
# Init-Capture and Aliases

Use 'name = expr' to capture the value of an expression under a chosen name.
This is useful when capturing a member path, a computed value, or 'me' under a
clear callback-local name.
*/
#test
{
    struct Box
    {
        value: s32
    }

    let leftBox  = Box{2}
    let rightBox = Box{7}

    let fct: func||()->s32 = func|left = leftBox.value, right = rightBox.value|()->s32
    {
        return left * 10 + right
    }

    @assert(fct() == 27)
}

/**
# Capturing Variables by Reference

Use '&' to capture by reference; otherwise, capture is by value.
*/
#test
{
    var a = 125

    let fct: func||() = func|&a|()
    {
        a += 1
    }

    fct()
    @assert(a == 126)

    fct()
    @assert(a == 127)
}

/**
# Aliased Reference Capture

The '&' form can also be used with an alias when the captured expression is
addressable.
*/
#test
{
    var a = 125

    let fct: func||()->s32 = func|&current = a|()->s32
    {
        current += 1
        return current
    }

    @assert(fct() == 126)
    @assert(a == 126)
}

/**
# Assigning Lambdas to Closure Variables

A closure variable can also hold a regular lambda (no captures).
*/
#test
{
    var fct: #null func||(s32, s32)->s32

    fct = func(x, y) => x + y
    @assert(fct(1, 2) == 3)
}

/**
# Capturing Complex Types

Arrays, structs, and slices can be captured by value if they fit in the capture size
and are plain data (POD).
*/
#test
{
    var x = [1, 2, 3]
    var fct: #null func||(s32)->s32
    fct = func|x|(toAdd)
    {
        var res = 0
        for v in x do
            res += v
        res += toAdd
        return res
    }
    let result = fct(4)
    @assert(result == 1 + 2 + 3 + 4)
}

/**
# Modifying Captured Variables

Captured values belong to the closure and can be mutated, enabling stateful behavior.
*/
#test
{
    func getInc()->func||()->s32
    {
        let x = 10

        return func|x|()->s32
        {
            x += 1
            return x
        }
    }

    let fct = getInc()

    @assert(fct() == 11)
    @assert(fct() == 12)
    @assert(fct() == 13)
}
