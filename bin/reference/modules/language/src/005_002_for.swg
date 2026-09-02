#global private

/**
# The 'for' Loop

The `for` construct in Swag enables iteration, allowing a block of code to execute repeatedly.
This guide explores its features: basic usage, indexing, naming, reverse loops, early exits,
range iteration, and advanced filtering using the `where` clause.
*/

/**
# Basic Usage

The `for` expression specifies the number of iterations and is evaluated **once** before the loop starts.
This expression must yield a **positive integer**.
*/
#test
{
    var cpt = 0
    for 10 do
        cpt += 1
    Swag.assert(cpt == 10)
}

/**
# Naming the Loop Index

Bind the loop index by naming it before `in`. In a counted loop that name is the current
iteration, starting from 0. A loop that never reads its index does not have to name one.
*/
#test
{
    var cpt = 0'u64

    for index in 5
    {
        cpt += index
    }

    Swag.assert(cpt == 0 + 1 + 2 + 3 + 4)
}

/**
Each loop names its own index, so a nested loop reads the one it named rather than the
nearest one.
*/
#test
{
    var pairs = 0'u64

    for row in 3
    {
        for column in 2 do
            pairs += row * 10 + column
    }

    Swag.assert(pairs == 63)
}

/**
# Looping Over Arrays and Slices

The `for` construct counts the elements of any type supporting `.count`, such as arrays,
slices, or strings. Naming a binding over the collection itself visits its **elements**
instead, so a loop that indexes back into the collection counts `.count`.
*/
#test
{
    var arr = [10, 20, 30, 40]
    #assert(arr.count == 4)

    var turns = 0
    for arr do
        turns += 1
    Swag.assert(turns == 4)

    var cpt = 0
    for index in arr.count do
        cpt += arr[index]
    Swag.assert(cpt == 10 + 20 + 30 + 40)
}

/**
> WARNING:
> When iterating over strings, `for` loops over **bytes**, not runes.
> Use `Std.Core` for rune-based iteration.
*/
#test
{
    var cpt = 0
    for "⻘" do
        cpt += 1
    Swag.assert(cpt == 3)
}

/**
# Reverse Looping

To iterate in reverse order, iterate the zero-allocation view returned by
`reversed`.
*/
#test
{
    var cpt = 0

    for index in reversed(3)
    {
        if cpt == 0 do
            Swag.assert(index == 2)
        elif cpt == 1 do
            Swag.assert(index == 1)
        elif cpt == 2 do
            Swag.assert(index == 0)
        cpt += 1
    }
}

/**
# Using 'break' and 'continue'

The `break` and `continue` keywords control loop flow.
`break` exits the loop, while `continue` skips to the next iteration.
*/

/**
# Exiting Early with 'break'

`break` stops the loop before completing all iterations.
*/
#test
{
    var cpt = 0
    for x in 10
    {
        if x == 5 do
            break
        cpt += 1
    }

    Swag.assert(cpt == 5)
}

/**
# Skipping Iterations with 'continue'

`continue` skips the current iteration and proceeds to the next.
*/
#test
{
    var cpt = 0
    for x in 10
    {
        if x == 5 do
            continue
        cpt += 1
    }

    Swag.assert(cpt == 9)
}

/**
# Ranges

The `for` loop supports signed integer ranges, offering flexible intervals.
*/

/**
# Looping Over a Range with 'to'

`to` defines an inclusive range loop.

> NOTE:
> An inverted range, whose start is above its end, selects nothing and the loop runs zero
> times. A loop asks whether the index is still within the range, and an inverted range
> answers no immediately, so this holds in every build configuration. Writing constant
> inverted bounds is still a compile-time error, because there the inversion is a certainty
> rather than an empty interval that happened to come out of a computation.

> WARNING:
> On an **unsigned** counter, do not write a collection-sized loop as
> `for i in 0 to count - 1`. This has nothing to do with inverted ranges: when `count` is
> zero, `count - 1` wraps to the largest value of the type, and the resulting range is valid
> and ascending, so no range rule can catch it. Only the overflow guard reports it, and it is
> off in `release`. Write `for i in 0 until count`, which needs no subtraction and is empty
> for a zero count.
*/
#test
{
    var count = 0
    var sum   = 0

    for i in -1 to 1
    {
        count += 1
        sum   += i
    }

    Swag.assert(sum == 0)
    Swag.assert(count == 3)
}

/**
# Excluding the Last Value with 'until'

`until` defines a range that excludes the end value.
*/
#test
{
    var cpt = 0
    for i in 1 until 3
    {
        cpt += i
    }

    Swag.assert(cpt == 1 + 2)
}

/**
# Empty Ranges

An `until` range whose bounds are equal is **empty**: the loop runs zero times. This makes
`for i in 0 until count` safe when `count` is zero, so a collection-sized loop needs no
guard of its own. Only an inverted range, where the lower bound is above the upper bound,
is an error.
*/
#test
{
    func sumUpTo(count: s32)->s32
    {
        var sum = 0
        for i in 0 until count do
            sum += i
        return sum
    }

    Swag.assert(sumUpTo(0) == 0)
    Swag.assert(sumUpTo(4) == 0 + 1 + 2 + 3)

    // The same holds for a constant empty range, and away from zero.
    var cpt = 0
    for i in 7 until 7 do
        cpt += 1
    Swag.assert(cpt == 0)
}

/**
# Reverse Range Looping

Construct a range view, then compose it with `.reversed()`.
*/
#test
{
    for ? in rangeTo(0, 5).reversed() {}

    for ? in rangeTo(-1, 1).reversed() {}

    for ? in range(-2, 2).reversed() {}
}

/**
# Infinite Loop

A `for` without an expression creates an infinite loop, similar to `while true {}`.
Use `break` to exit. There is no index to name here, so a loop that counts its own
turns keeps an ordinary variable.
*/
#test
{
    var turns = 0

    for
    {
        if turns == 4 do
            break
        turns += 1
    }

    Swag.assert(turns == 4)
}

/**
# Using 'where' Clause

The `where` clause filters iterations based on conditions.
*/

/**
# Basic 'where' Clause

Attach `where` to apply a filter to the loop index or element.
Only iterations meeting the condition are executed.
*/
#test
{
    var result = 0

    for i in 10 where i % 2 == 0
    {
        result += i
    }

    Swag.assert(result == 0 + 2 + 4 + 6 + 8)
}

/**
# Filtering Arrays with 'where'

Loop over the element count and use `where` to filter which indices run the body.
*/
#test
{
    var arr        = [10, 21, 30, 41, 50]
    var sumOfEvens = 0

    for i in arr.count where arr[i] % 2 == 0
    {
        sumOfEvens += arr[i]
    }

    Swag.assert(sumOfEvens == 10 + 30 + 50)
}

/**
# Complex Conditions with 'where'

The `where` clause supports multiple logical conditions for advanced filtering.
*/
#test
{
    var arr         = [10, 15, 20, 25, 30, 35]
    var filteredSum = 0

    for i in arr.count where arr[i] % 2 == 0 and arr[i] > 15
    {
        filteredSum += arr[i]
    }

    Swag.assert(filteredSum == 20 + 30)
}

#test
{
    var arr        = [10, 25, 30, 45, 50, 65]
    var complexSum = 0

    for i in arr.count where arr[i] % 2 == 0 or arr[i] > 40
    {
        complexSum += arr[i]
    }

    Swag.assert(complexSum == 10 + 30 + 45 + 50 + 65)
}

/**
# Filtering Ranges with 'where'

The `where` clause can also be applied to ranges.
*/
#test
{
    var sumOfPositiveEvens = 0

    for i in -5 to 5 where i > 0 and i % 2 == 0
    {
        sumOfPositiveEvens += i
    }

    Swag.assert(sumOfPositiveEvens == 2 + 4)
}

/**
# Combining '.reversed()' and 'where'

You can combine a reverse view with `where` for conditional iteration.
*/
#test
{
    var arr         = [10, 20, 30, 40, 50]
    var reversedSum = 0

    for i in reversed(arr.count) where arr[i] % 2 == 0
    {
        reversedSum += arr[i]
    }

    Swag.assert(reversedSum == 50 + 40 + 30 + 20 + 10)
}

/**
# C-like 'for'

Swag also supports a C-style `for` loop with initialization, condition, and increment sections.
*/
#test
{
    var cpt = 0

    // Standard syntax
    for var i = 0; i < 10; i += 1 do
        cpt += 1
    Swag.assert(cpt == 10)

    // Alternative syntax with newlines
    for var i = 0; i < 10; i += 1
    {
        cpt += 1
    }

    Swag.assert(cpt == 20)
}

/**
# The Counter Of A C-like 'for'

The variable declared in the initialization section is the only counter this form has,
and the loop is free to start it anywhere and step it by anything.
*/
#test
{
    var cpt = 0'u32

    for var i: u32 = 10; i < 15; i += 1 do
        cpt += i
    Swag.assert(cpt == 10 + 11 + 12 + 13 + 14)
}

/**
# Using 'break' and 'continue' in 'for' Loops

`break` exits the loop early, and `continue` skips to the next iteration.
*/
#test
{
    var sum = 0

    for var i = 0; i < 10; i += 1
    {
        if i == 5 do
            break
        sum += i
    }

    Swag.assert(sum == 0 + 1 + 2 + 3 + 4)

    sum = 0
    for var i = 0; i < 10; i += 1
    {
        if i % 2 == 0 do
            continue
        sum += i
    }

    Swag.assert(sum == 1 + 3 + 5 + 7 + 9)
}

/**
# Nested 'for' Loops

Swag supports nested loops. Each level names its own counter, so an inner body can read
both.
*/
#test
{
    var result = 0

    for var i = 0; i < 5; i += 1
    {
        for var j = 0; j < 5; j += 1
        {
            result += i * j
        }
    }

    Swag.assert(result == 100)
}

/**
# Iterating Over Arrays with 'for'

You can also use `for` to iterate over arrays and collections.
*/
#test
{
    var array = [1, 2, 3, 4, 5]
    var sum   = 0

    for var i = 0; i < array.count; i += 1
    {
        sum += array[i]
    }

    Swag.assert(sum == 1 + 2 + 3 + 4 + 5)
}
