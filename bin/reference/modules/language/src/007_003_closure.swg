#global private

/**
# Closures

Swag supports limited closures, allowing functions to capture variables from
their surrounding scope. Up to 64 bytes can be captured without heap allocation.

A by-value capture is a plain byte copy into the closure: the closure never runs
'opPostCopy' on the way in and never drops the captured value. Only simple types
(without 'opDrop', 'opPostCopy', or 'opPostMove', and not marked '#[Swag.NoCopy]')
can therefore be captured by value; other types must be captured by address
with '&'.

The copy is read-only unless the capture is written 'var'. Because the copy is
storage of the closure's own, the capture list states its mutability rather than
inheriting it from the source declaration.
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
        Swag.assert(a == 125)
        Swag.assert(b == 521)
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

    let fct: func||()->s32 = func|left = leftBox.value, right = rightBox.value|()->s32 { return left * 10 + right }

    Swag.assert(fct() == 27)
}

/**
# Capturing Variables by Address

Use '&' to capture the variable's address; otherwise, capture is by value. An
'&' capture aliases the outer variable: reads and writes in the closure body
reach the original storage.
*/
#test
{
    var a = 125

    let fct: func||() = func|&a|() { a += 1 }

    fct()
    Swag.assert(a == 126)

    fct()
    Swag.assert(a == 127)
}

/**
# Aliased Address Capture

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

    Swag.assert(fct() == 126)
    Swag.assert(a == 126)
}

/**
# Assigning Lambdas to Closure Variables

A closure variable can also hold a regular lambda (no captures).
*/
#test
{
    var fct: #null func||(s32, s32)->s32

    fct = func(x, y) => x + y
    Swag.assert(fct(1, 2) == 3)
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
    Swag.assert(result == 1 + 2 + 3 + 4)
}

/**
# Modifying Captured Values with 'var'

A 'var' capture is a writable copy owned by the closure. It outlives the variable
it was copied from and keeps its value across calls, which is what makes a stateful
closure. The source is untouched, whether it was declared 'let' or 'var'.
*/
#test
{
    func getInc()->func||()->s32
    {
        let x = 10

        return func|var x|()->s32
        {
            x += 1
            return x
        }
    }

    let fct = getInc()

    Swag.assert(fct() == 11)
    Swag.assert(fct() == 12)
    Swag.assert(fct() == 13)
}

/**
Without 'var' the copy is read-only, so a capture that is only read says so, and
a closure that keeps state announces it at the capture list instead of at its
first assignment. Use '&' instead of 'var' to write the outer variable itself.
*/
#test
{
    var counter = 0

    let readOnly: func||()->s32 = func|counter|()->s32 { return counter }
    let writable: func||()      = func|&counter|() { counter += 1 }

    writable()
    Swag.assert(counter == 1)
    Swag.assert(readOnly() == 0)     // The read-only capture copied the original value
}
