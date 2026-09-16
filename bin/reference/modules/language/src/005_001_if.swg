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
        Swag.assert(false)

    if a == 1 do
        Swag.assert(false)

    if a == 0
    {
        Swag.assert(true)
    }

    // The 'else' keyword works as in most languages.
    // When omitting braces, 'do' is mandatory after the condition.
    if a == 0 do
        a += 1
    else do
        a += 2
    Swag.assert(a == 1)

    // 'elif' functions like 'else if' in other languages.
    if a == 1 do
        a += 1
    else do
        if a == 2 do
            Swag.assert(false)
        elif a == 3 do
            Swag.assert(false)
        elif a == 4 do
            Swag.assert(false)

    // Logical expressions work as expected with 'and' and 'or'.
    if a == 0 and a == 1 do
        Swag.assert(false)
    if a == 0 or a == 1 do
        Swag.assert(false)
    if a == 1 or a == 2 do
        Swag.assert(true)
}

/**
# Variable Declaration in 'if'

You can declare and test a variable directly in an `if` statement.
When doing so, the use of `var`, `let`, or `const` is mandatory.

The declared variable is converted to a boolean for the condition:
non-zero (or non-null) values are considered `true`.
*/

#test
{
    // Declare and test 'a' in the same line.
    // Since 'a' is 0, the condition is false and the block will not execute.
    if let a = 0
    {
        Swag.assert(false)
    }

    // Redeclare 'a' as a constant in another scope.
    // Since 'a' is 1, the block will execute.
    if const a = 1 do
        Swag.assert(a == 1)
    else do
        Swag.assert(false)
    if let a = 1 do
        Swag.assert(a == 1)
    else do
        Swag.assert(false)
}

/**
# Adding Conditions with 'where'

When an `if` statement includes a variable declaration, you can refine the test
with a `where` clause. The `where` condition is only evaluated if the variable test passes.
*/

#test
{
    func retSomething()->string => "string"
    func retNothing()->string?  => null

    // The 'where' clause runs only if 'str' is not null.
    if let str = retSomething() where str[0] == 's' do
        Swag.assert(true)
    else do
        Swag.assert(false)

    // Since 'retNothing()' returns null, the 'where' clause is skipped.
    if let str = retNothing() where str[0] == 's' do
        Swag.assert(false)
    else do
        Swag.assert(true)
}

/**
# Binding a Dynamic Type

`if value is T as name` tests dynamic compatibility and binds the successful view.
For a concrete `T`, `name` is a non-null pointer; for an interface, it is an
interface view. Source constness is preserved. The source is evaluated once, and
no binding copies the object or extends its lifetime.

An optional `where` guard runs only after a match. The binding is visible in that
guard and the successful body, but not in `elif`, `else`, or after the statement.
A false guard continues to the next branch. `elif` accepts the same binding form.
*/
#test
{
    let value: any = 42's32
    if value is s32 as number where number[] > 0 do
        Swag.assert(number[] == 42)
    elif value is string as text do
        Swag.assert(text[].count != 0)
    else do
        Swag.assert(false)
}
