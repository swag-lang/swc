#global private

/**
# Generic Functions

Generic parameters appear between 'func' and the function name. 'var T'
declares a type parameter; 'const N: s32' declares a compile-time value
parameter.

The compiler normally deduces type parameters from call arguments:
*/

func(var T) genericTwice(value: T)->T
{
    return value + value
}

#test
{
    @assert(genericTwice(21's32) == 42)
    @assert(genericTwice(1.5'f32) == 3.0'f32)

    // An apostrophe supplies generic arguments explicitly.
    @assert(genericTwice's64(12) == 24)
}

/**
# Multiple and Explicit Arguments

Use parentheses after the apostrophe when a specialization has more than one
generic argument.
*/

func(var Key, var Value) genericSelect(key: Key, value: Value)->Value
{
    discard key
    return value
}

#test
{
    @assert(genericSelect(7'u32, "seven") == "seven")
    @assert(genericSelect'(u32, bool)(7, true))
}

/**
# Defaults

A generic default is used when deduction and explicit arguments do not provide
that parameter.
*/

func(var T = s32) genericZero()->T
{
    return 0
}

#test
{
    #assert(#typeof(genericZero()) == s32)
    #assert(#typeof(genericZero'f64()) == f64)
    @assert(genericZero'f64() == 0.0'f64)
}

/**
# Compile-Time Value Parameters

Value parameters can shape types and declarations. They are constants inside
the specialization.
*/

func(var T, const Count: s32) genericRepeat(value: T)->[Count] T
    where Count >= 0
{
    var result: [Count] T
    for [index] in Count do
        result[index] = value
    return result
}

#test
{
    let values = genericRepeat'(s32, 3)(9)
    #assert(#typeof(values) == #type [3] s32)
    @assert(values[0] == 9 and values[1] == 9 and values[2] == 9)
}

/**
When the role is unambiguous, Swag also accepts the shorter forms 'T' for a
type parameter and 'N: s32' for a value parameter. Both spellings mean the same
thing; this reference uses the explicit 'var' and 'const' forms wherever it
states a contract, and the short form in introductory examples.

# Specialization Aliases

An alias can capture some or all generic arguments:
*/

alias RepeatFourBytes = genericRepeat'(u8, 4)

#test
{
    let bytes = RepeatFourBytes(0xA5)
    #assert(#typeof(bytes) == #type [4] u8)
    @assert(bytes[3] == 0xA5)
}

/**
A specialization is compiled when used. Its body must be valid for the selected
arguments; use 'where' constraints to exclude unsupported candidates with a
clear overload contract.
*/
