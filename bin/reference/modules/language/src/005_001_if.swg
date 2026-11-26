#global private

/**
# Basic Usage of 'if'

A basic test with an 'if' statement.

Control-flow bodies use curly braces `{}`. The braces also define the scope of
the body.

Unlike in C/C++, the condition in an `if` statement does not need parentheses.
They can be used for clarity or grouping, but they are not required.
*/

#test
{
    var a = 0

    if a == 1
    {
        Swag.require(false)
    }

    if a == 1
    {
        Swag.require(false)
    }

    if a == 0
    {
        Swag.require(true)
    }

    // The 'else' keyword works as in most languages.
    if a == 0
    {
        a += 1
    }
    else
    {
        a += 2
    }

    Swag.require(a == 1)

    if a == 1
    {
        a += 1
    }
    else if a == 2
    {
        Swag.require(false)
    }
    else if a == 3
    {
        Swag.require(false)
    }
    else if a == 4
    {
        Swag.require(false)
    }

    // Logical expressions work as expected with 'and' and 'or'.
    if a == 0 and a == 1
    {
        Swag.require(false)
    }

    if a == 0 or a == 1
    {
        Swag.require(false)
    }

    if a == 1 or a == 2
    {
        Swag.require(true)
    }
}

/**
# Variable Declaration in 'if'

An `if` or `else if` can declare a value with `let`, `var`, or `const`.
A runtime initializer is evaluated once when that clause is reached.
A nullable declaration tests whether the value is present.
A non-nullable declaration needs `where`, which supplies the condition
and follows the rules for an ordinary `if`.
The name is in scope in the `where` condition and both branches of its clause.
The binding's lifetime ends as control leaves the conditional.
*/

#test
{
    if let count = 0 where count == 0
    {
        Swag.require(count == 0)
    }
    else
    {
        Swag.require(false)
    }

    if var available = 3 where available >= 10
    {
        Swag.require(false)
    }
    else
    {
        available += 1
        Swag.require(available == 4)
    }

    if const preferred = 0 where preferred > 0
    {
        Swag.require(false)
    }
    else if let fallback = 1 where fallback > 0
    {
        Swag.require(fallback == 1)
    }
    else
    {
        Swag.require(false)
    }
}

/**
# Adding Conditions with 'where'

For a nullable declaration, a present value proceeds to the optional `where`
condition. An absent value skips it and takes the false branch.
An empty string or slice is present. A pointer to a zero-valued object is present.
*/

#test
{
    func readText()->string?   => "string"
    func readAbsent()->string? => null

    var matched = false
    if let text = readText() where text[0] == 's'
    {
        matched = true
    }

    Swag.require(matched)

    let empty: string? = ""
    if let text = empty
    {
        Swag.require(text.count == 0)
    }
    else
    {
        Swag.require(false)
    }

    if var text = readAbsent() where text == null
    {
        Swag.require(false)
    }
    else
    {
        Swag.require(text == null)
        text = "fallback"
        Swag.require(text == "fallback")
    }
}

/**
# Binding a Dynamic Type

`if value is T as name` tests dynamic compatibility and binds the successful view.
For a concrete `T`, `name` is a non-null pointer; for an interface, it is an
interface view. Source constness is preserved. The source is evaluated once, and
no binding copies the object or extends its lifetime.
An 'any' boxed from a literal or constant binds a read-only view.
Declare the source `const any` to request that view in a binding pattern.

An optional `where` guard runs only after a match. The binding is visible in that
guard and the successful body, but not in `else if`, `else`, or after the statement.
A false guard continues to the next branch. `else if` accepts the same binding form.
*/
#test
{
    let value: const any = 42_s32
    if value is s32 as number where number[] > 0
    {
        Swag.require(number[] == 42)
    }
    else if value is string as text
    {
        Swag.require(text[].count != 0)
    }
    else
    {
        Swag.require(false)
    }
}
