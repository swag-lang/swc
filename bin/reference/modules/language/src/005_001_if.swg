#global private

/**
# Basic Usage of 'if'

A basic test with an 'if' statement.

In Swag, curly braces `{}` are optional for control structures like `if`.
However, if you omit them, you must use `do`. This rule also applies to `while` and `for` loops.

Unlike in C/C++, the condition in an `if` statement does not need parentheses.
They can be used for clarity or grouping, but they are not required.
*/

#test
{
    var a = 0

    if a == 1 do
        Swag.require(false)

    if a == 1 do
        Swag.require(false)

    if a == 0
    {
        Swag.require(true)
    }

    // The 'else' keyword works as in most languages.
    // When omitting braces, 'do' is mandatory after the condition.
    if a == 0 do
        a += 1
    else do
        a += 2
    Swag.require(a == 1)

    // 'elif' functions like 'else if' in other languages.
    if a == 1 do
        a += 1
    else do
        if a == 2 do
            Swag.require(false)
        elif a == 3 do
            Swag.require(false)
        elif a == 4 do
            Swag.require(false)

    // Logical expressions work as expected with 'and' and 'or'.
    if a == 0 and a == 1 do
        Swag.require(false)
    if a == 0 or a == 1 do
        Swag.require(false)
    if a == 1 or a == 2 do
        Swag.require(true)
}

/**
# Variable Declaration in 'if'

An `if` or `elif` can declare a value with `let`, `var`, or `const`.
A runtime initializer is evaluated once when that clause is reached.
A nullable declaration tests whether the value is present.
A non-nullable declaration needs `where`, which supplies the condition
and follows the rules for an ordinary `if`.
The name is in scope in the `where` condition and both branches of its clause.
The binding's lifetime ends as control leaves the conditional.
*/

#test
{
    if let count = 0 where count == 0 do
        Swag.require(count == 0)
    else do
        Swag.require(false)

    if var available = 3 where available >= 10 do
        Swag.require(false)
    else
    {
        available += 1
        Swag.require(available == 4)
    }

    if const preferred = 0 where preferred > 0 do
        Swag.require(false)
    elif let fallback = 1 where fallback > 0 do
        Swag.require(fallback == 1)
    else do
        Swag.require(false)
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
    if let text = readText() where text[0] == 's' do
        matched = true
    Swag.require(matched)

    let empty: string? = ""
    if let text = empty do
        Swag.require(text.count == 0)
    else do
        Swag.require(false)

    if var text = readAbsent() where text == null do
        Swag.require(false)
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
guard and the successful body, but not in `elif`, `else`, or after the statement.
A false guard continues to the next branch. `elif` accepts the same binding form.
*/
#test
{
    let value: const any = 42's32
    if value is s32 as number where number[] > 0 do
        Swag.require(number[] == 42)
    elif value is string as text do
        Swag.require(text[].count != 0)
    else do
        Swag.require(false)
}
