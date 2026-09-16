#global private

/**
# The 'switch' Statement

The `switch` statement in Swag behaves similarly to C/C++, with one key difference:
Swag **does not require `break`** at the end of each case.
Unintentional fallthroughs are prevented by default, ensuring each `case` is isolated unless explicitly linked with `fallthrough`.
*/

#test
{
    let value = 6

    switch value
    {
    case 0:  Swag.assert(false)
    case 5:  Swag.assert(false)
    case 6:  Swag.assert(true)
    default: Swag.assert(false)
    }

    let ch = 'A'rune

    switch ch
    {
    case 'B': Swag.assert(false)
    case 'A': break
    }
}

/**
# Multiple Values in a 'case'

A `case` can match multiple values, simplifying logic when several values share the same behavior.
*/

#test
{
    let value = 6

    switch value
    {
    case 2, 4, 6: Swag.assert(true)
    default:      Swag.assert(false)
    }

    // Alternatively, list each value on its own line for clarity.
    switch value
    {
    case 2,
         4,
         6: Swag.assert(true)

    default: Swag.assert(false)
    }
}

/**
# Using 'switch' with Various Types

`switch` supports any type that implements `==`, including strings and user-defined comparable types.
*/

#test
{
    let value = "myString"

    switch value
    {
    case "myString":    Swag.assert(true)
    case "otherString": Swag.assert(false)
    default:            Swag.assert(false)
    }
}

/**
# Intentional Fallthrough with 'fallthrough'

Use `fallthrough` to intentionally continue execution into the next case.
*/

#test
{
    let value = 6

    switch value
    {
    case 6:  fallthrough
    case 7:  Swag.assert(value == 6)
    default: Swag.assert(true)
    }
}

/**
# Exiting a 'case' Early with 'break'

Use `break` to exit a `case` early when a certain condition is met.
*/

#test
{
    let value = 6

    switch value
    {
    case 6:
        if value == 6 do
            break
        Swag.assert(false)

    default:
        Swag.assert(false)
    }
}

/**
# Handling Empty Cases with 'break'

A `case` cannot be left empty. Use `break` explicitly when no action is required.
*/

#test
{
    let value = 6

    switch value
    {
    case 5:  Swag.assert(false)
    case 6:  break
    default: Swag.assert(false)
    }
}

/**
# Variable and Expression Cases

`switch` cases can use variables and expressions, evaluated dynamically at runtime.
*/

#test
{
    let test = 2
    let a    = 0
    let b    = 1

    switch test
    {
    case a:     Swag.assert(false)
    case b:     Swag.assert(false)
    case b + 1: Swag.assert(true)
    }
}

/**
# Enum Case Values

When the switch expression is an enum, write inferred enum values with a leading
dot, such as `case .Ready`. The bare form `case Ready` is not auto-scoped.
Ordinary constants and other case expressions remain valid.
*/

#test
{
    enum State { Idle, Ready }
    let state = State.Ready

    switch state
    {
    case .Idle:  Swag.assert(false)
    case .Ready: break
    }
}

/**
# The '#complete' Modifier

Write `switch #complete` when matching enums to enforce exhaustive case handling. Every
declared enum value must have a `case`, and the switch cannot have a `default`.

`#complete` is a modifier and not an attribute because it selects a variant of **this one
statement**: a statement carries no symbol, so there is nothing for an attribute to
annotate or for reflection to report.

`#static switch` accepts it too, with the same meaning and the same two rules: every
declared enum value needs a `case`, and a `default` is rejected.
*/

#test
{
    enum Color { Red, Green, Blue }
    let color = Color.Red

    switch #complete color
    {
    case .Red:   break
    case .Green: Swag.assert(false)
    case .Blue:  Swag.assert(false)
    }
}

/**
# Matching Ranges in a 'switch' Statement

Swag supports matching a **range of values** in `case` conditions for concise range-based logic.
*/

#test
{
    var success = false
    let x       = 6

    switch x
    {
    case 0 to 5:  Swag.assert(false)
    case 6 to 15: success = true
    }

    Swag.assert(success)
}

/**
# Overlapping Ranges

When ranges overlap, the **first matching range** is executed; later overlaps are ignored.
*/

#test
{
    var success = false
    let x       = 6

    switch x
    {
    case 0 to 10:    success = true
    case 5 until 15: Swag.assert(false)
    }

    Swag.assert(success)
}

/**
# Using the 'where' Clause in 'switch'

Add a `where` clause to a `case` to refine matching conditions based on additional logic.
*/

#test
{
    let x = 6
    let y = 10

    switch x
    {
    case 6 where y == 9:  Swag.assert(false)
    case 6 where y == 10: Swag.assert(true)
    default: Swag.assert(false)
    }
}

/**
# Using 'where' with 'default'

A `where` clause can also modify the `default` case for conditional fallbacks.
*/

#test
{
    let x = 7
    let y = 10
    switch x
    {
    case 6 where y == 10:  Swag.assert(false)
    case 7 where y == 9:   Swag.assert(false)
    default where y == 10: break
    default: Swag.assert(false)
    }
}

/**
# Switching on Type with 'any' or 'interface'

A switch over an `any`, an interface, or a pointer to a dynamic struct can match
concrete types. Write `case T` to test compatibility, or `case T as name` to borrow
the matching object. An interface type can also be the target of a case.

The subject is evaluated once. Matching uses the same compatibility and pointer
adjustments as `cast #try`. A null source does not match a type. The first matching
case whose `where` guard succeeds is selected. Pointer subjects also retain ordinary
pointer cases, including `case null`; these can appear alongside type cases.

A concrete binding has type `*T`; an interface binding is an interface view. Both
are non-null, preserve source constness, and borrow without extending the source's
lifetime. The name is visible in its case's guard and body only.
*/
#test
{
    let value: any = "value"
    switch value
    {
    case s32: Swag.assert(false)
    case string as text where text[] == "other": Swag.assert(false)
    case string as text: Swag.assert(text[] == "value")
    default:  Swag.assert(false)
    }
}

/**
A `fallthrough` into a typed case checks its type and `where` guard before entering
its body; an unsuccessful match continues to the next case. `switch #complete`
asserts that some case matches, with a panic on a miss when `.Switch` safety is enabled.

An expressionless switch also accepts `case let name = expression`. It evaluates
the expression once and enters the case if its result is present. This general
binding remains useful for nullable results from ordinary expressions. A direct
`cast #try` initializer is rejected; use a typed switch for dynamic dispatch.
*/
#test
{
    func findText(value: *string?)->*string? => value
    var value = "value"
    switch
    {
    case let text = findText(&value) where text[] == "value": Swag.assert(text[] == "value")
    default: Swag.assert(false)
    }
}

/**
# Switch Without an Expression

A `switch` without an expression behaves like an `if`/`elif` chain.
Each `case` is evaluated in order, executing the first one that evaluates to `true`.
*/

#test
{
    let value  = 6
    let value1 = "true"

    switch
    {
    case value == 6 or value > 10:
        Swag.assert(true)
        fallthrough

    case value1 == "true":
        Swag.assert(true)

    default:
        Swag.assert(false)
    }
}
