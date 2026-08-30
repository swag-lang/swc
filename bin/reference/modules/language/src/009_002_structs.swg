#global private

/**
# Generic Structs

A generic struct uses the same parameter syntax as a generic function. Each
specialization is a distinct type with its own layout.
*/

struct(var T) GenericBox
{
    value: T
}

#test
{
    let integer = GenericBox's32{value: 42}
    let text    = GenericBox'string{value: "answer"}

    #assert(#typeof(integer) == GenericBox's32)
    #assert(#typeof(integer.value) == s32)
    #assert(#typeof(text.value) == string)
    Swag.assert(integer.value == 42)
    Swag.assert(text.value == "answer")
}

/**
# Type and Value Parameters

Compile-time values can determine field types and array dimensions.
*/

struct(var T, const Count: s32) GenericBuffer
    where Count > 0
{
    values: [Count] T
}

#test
{
    let flags: GenericBuffer'(bool, 3) = {values: [true, false, true]}

    #assert(#typeof(flags.values) == #type [3] bool)
    Swag.assert(flags.values[0] and !flags.values[1] and flags.values[2])
}

/**
# Generic Methods

An 'impl' for a generic struct sees the struct's parameters. Methods can add
their own generic parameters.
*/

impl GenericBox
{
    mtd const get()->T
    {
        return .value
    }

    func(var U) pair(const me, other: U)->{first: T, second: U}
    {
        return {first: me.value, second: other}
    }
}

#test
{
    let box  = GenericBox'u16{value: 12}
    let pair = box.pair("items")

    Swag.assert(box.get() == 12)
    #assert(#typeof(pair.first) == u16)
    #assert(#typeof(pair.second) == string)
    Swag.assert(pair.second == "items")
}

/**
Use a default when one specialization is the natural choice:
*/

struct(var T = s32) GenericCounter
{
    value: T
}

#test
{
    let defaultCounter: GenericCounter     = {value: 1}
    let wideCounter:    GenericCounter'u64 = {value: 2}

    #assert(#typeof(defaultCounter.value) == s32)
    #assert(#typeof(wideCounter.value) == u64)
}
