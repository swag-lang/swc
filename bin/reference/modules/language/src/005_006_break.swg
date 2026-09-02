#global private

/**
# The 'break' Statement
The 'break' statement exits the nearest enclosing loop or switch case.
It works with 'for', 'while', and 'switch'. Use it to stop a loop
early or to leave a switch case.
*/
#test
{
    // Immediately exits the loop body
    for 10 do
        break

    // Exits after the first iteration
    for var i = 0; i < 10; i += 1 do
        break

    // Not reached because the condition is false
    while false do
        break
}

/**
# Default Behavior
By default, 'break' exits only the innermost loop or switch case.
Outer structures continue to run.
*/
#test
{
    var cpt = 0

    for 10
    {
        for 10
        {
            // Exits only the inner loop
            break
        }

        // Outer loop continues
        cpt += 1
    }

    Swag.assert(cpt == 10)
}

/**
# Named Scopes with '#scope'
Define a named scope with '#scope(Name)'. 'break to Name' exits that scope
from anywhere inside it, however deeply nested.
*/
#test
{
    var cpt = 0

    #scope(BigScope)
    {
        for 10
        {
            cpt += 1
            break to BigScope     // Leave the whole 'BigScope'
        }

        Swag.assert(false)     // Unreachable
    }

    Swag.assert(cpt == 1)
}

/**
# A Scope Is Never the Target of a Bare 'break'
'break to Name' is the only statement that leaves a '#scope'. A bare 'break'
written inside one keeps targeting the enclosing loop or switch, so wrapping a
piece of a loop body in a scope does not change where its 'break' statements go.
*/
#test
{
    var runs = 0

    for 10
    {
        #scope(Grouped)
        {
            runs += 1
            break     // Exits the 'for', not 'Grouped'
        }
    }

    Swag.assert(runs == 1)
}

/**
'continue' behaves the same way: a scope is not a loop, so 'continue' restarts
the enclosing loop and never the scope. Repeating a block therefore needs a real
loop, and a '#scope' that encloses no loop rejects both bare statements.
*/
#test
{
    var visited = 0

    for 3
    {
        #scope(Grouped)
        {
            visited += 1
            continue     // Restarts the 'for'
        }
    }

    Swag.assert(visited == 3)
}

/**
# Unnamed Scopes
A scope can be left unnamed when nothing needs to jump out of it. It then only
groups statements and bounds the lifetime of what it declares. Give it a name as
soon as a 'break to' has to reach it.
*/
#test
{
    var total = 0

    #scope
    {
        let step = 4
        total += step
    }

    Swag.assert(total == 4)
}

/**
# Scopes with Simple Statements
A scope label can precede a simple statement. 'break to Label' exits to just
after that labeled statement.
*/
#test
{
    #scope(Up)
    for 10
    {
        for index in 10
        {
            if index == 5 do
                break to Up     // Exit to after the labeled 'for'
        }

        Swag.assert(false)     // Unreachable
    }
}
