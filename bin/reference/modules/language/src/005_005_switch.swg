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
    case 0:  Swag.require(false)
    case 5:  Swag.require(false)
    case 6:  Swag.require(true)
    default: Swag.require(false)
    }

    let ch = 'A'rune

    switch ch
    {
    case 'B': Swag.require(false)
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
    case 2, 4, 6: Swag.require(true)
    default:      Swag.require(false)
    }

    // Alternatively, list each value on its own line for clarity.
    switch value
    {
    case 2,
         4,
         6:
        Swag.require(true)

    default: Swag.require(false)
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
    case "myString":    Swag.require(true)
    case "otherString": Swag.require(false)
    default:            Swag.require(false)
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
    case 7:  Swag.require(value == 6)
    default: Swag.require(true)
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
        Swag.require(false)

    default:
        Swag.require(false)
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
    case 5:  Swag.require(false)
    case 6:  break
    default: Swag.require(false)
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
    case a:     Swag.require(false)
    case b:     Swag.require(false)
    case b + 1: Swag.require(true)
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
    case .Idle:  Swag.require(false)
    case .Ready: break
    }
}

/**
# Exhaustive Enum Switches

A runtime `switch` over a closed enum or a tagged union with a closed enum tag must cover
every declared value. Several enum names can name the same value. A case for one name covers
those aliases. Numeric and rune ranges cover the declared values they contain. A guarded case
with values or ranges counts when the compiler proves its guard is always true.

When its storage type has a default value, a plain enum can also be initialized to zero,
false, or absence, depending on that type. If no case covers that value, control can continue
past the switch even when all named values are covered. A type that needs explicit
initialization introduces no extra value. A tagged union is created with a named tag, so
covering all declared tags is sufficient.

Use `default` for all remaining values, or `default: break` when ignoring them is intentional.
Flags enums, `#[Swag.Incomplete]` enums and dynamic type switches can have unmatched values.
Write an explicit fallback when their callers need every path to produce a result.

`switch #complete` forbids `default` and asserts that some case matches. On an enum it needs
cases for every declared value. On other operands it asserts coverage in the presence of the
`.Switch` runtime guard. `#static switch #complete` likewise checks declared enum coverage and
forbids `default` when selecting code at compile time.
*/

#test
{
    enum Color { Red, Green, Blue }
    let color = Color.Red

    switch color
    {
    case .Red:   break
    case .Green: Swag.require(false)
    case .Blue:  Swag.require(false)
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
    case 0 to 5:  Swag.require(false)
    case 6 to 15: success = true
    }

    Swag.require(success)
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
    case 5 until 15: Swag.require(false)
    }

    Swag.require(success)
}

/**
# Using the 'where' Clause in 'switch'

Add a `where` clause to a `case` to refine matching conditions based on additional logic.
The case values are tested first, and the guard is evaluated only when one of them matched,
so a guard with a cost or a side effect runs only for the values its case selects. A
`fallthrough` into a value case enters its body without testing its values or its guard.
*/

#test
{
    let x = 6
    let y = 10

    switch x
    {
    case 6 where y == 9:  Swag.require(false)
    case 6 where y == 10: Swag.require(true)
    default: Swag.require(false)
    }
}

/**
# Cases With Only a Guard

Write `case where` to test a guard without comparing case values. The switch tries it
in source order and enters the arm if the guard is true. This form also works in a
switch without a subject. A `fallthrough` into this arm enters its body directly.
A switch can have one unconditional `default` arm.
*/

#test
{
    let x = 7
    let y = 10
    switch x
    {
    case 6 where y == 10:  Swag.require(false)
    case 7 where y == 9:   Swag.require(false)
    case where y == 10:   break
    default: Swag.require(false)
    }
}

/**
# Switching on Type with 'any' or 'interface'

A switch over an `any`, an interface, or a pointer to a dynamic struct can match
concrete types. Write `case T` to test compatibility, or `case T as name` to borrow
the matching object. An interface type can also be the target of a case.

The subject is evaluated once. Matching uses the same compatibility and pointer
adjustments as a checked cast. A null source does not match a type. The first matching
case whose `where` guard succeeds is selected. Pointer subjects also retain ordinary
pointer cases, including `case null`; these can appear alongside type cases.

A concrete binding has type `*T`; an interface binding is an interface view. Both
are non-null, preserve source constness, and borrow without extending the source's
lifetime. The name is visible in its case's guard and body only.

A `fallthrough` into a typed case checks its type and `where` guard before entering
its body. An unsuccessful match continues to the next case. `switch #complete`
asserts that some case matches, with a panic on a miss when `.Switch` safety is enabled.
*/
#test
{
    let value: const any = "value"
    switch value
    {
    case s32: Swag.require(false)
    case string as text where text[] == "other": Swag.require(false)
    case string as text: Swag.require(text[] == "value")
    default:  Swag.require(false)
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
        Swag.require(true)
        fallthrough

    case value1 == "true":
        Swag.require(true)

    default:
        Swag.require(false)
    }
}

/**
# Declaring a Value in a Case

A switch without an expression accepts declarations with `case let`,
`case var`, and `case const`. A runtime initializer is evaluated once
when the case is tested, including after a `fallthrough`. The name is in
scope in that case's `where` condition and body.
An owned value is released when its case ends, including before a
`fallthrough` target or the next initializer after a failed guard.

A nullable declaration tests presence before evaluating an optional
`where` condition. An absent value skips the condition and the case.
An empty string or slice is present.
*/
#test
{
    func readText(available: bool)->string? => available ? "" : null

    switch
    {
    case let text = readText(false) where text == null:
        Swag.require(false)

    case var text = readText(true) where text.count == 0:
        text = "empty"
        Swag.require(text == "empty")

    default:
        Swag.require(false)
    }
}

/**
A non-nullable declaration needs a `where` condition. That condition
decides whether the case matches and follows the rules for an ordinary
`if` condition.
*/
#test
{
    switch
    {
    case const count = 0 where count == 0:
        Swag.require(count == 0)

    default:
        Swag.require(false)
    }
}
