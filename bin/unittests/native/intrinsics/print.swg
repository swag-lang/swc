#global private

// 'Swag.print' formats a value from its native kind, not from the identity of its typeinfo.
// A qualified form such as 'string?' owns its own descriptor while still being a
// string: reading it as an unrelated type panics on a null payload, and refusing it
// altogether drops the very text the call was asked to write.
//
// Only payloads that print nothing are exercised here, because the console output of a
// test is not observable; what is proved is that the string forms are accepted.
#test
{
    var missing: string?
    Swag.print(missing)

    var empty: string? = ""
    Swag.print(empty)

    var plain: string = ""
    Swag.print(plain)
}

// Rounding the eighth fractional digit can carry into the integer part.
#test
{
    var buffer: [64] u8

    Swag.__ftoa(&buffer[0], 0.9999999999'f64)
    let positive = cast(string, Swag.makeSlice(&buffer[0], cast(const cstring, &buffer[0]).count))
    Swag.assert(Swag.stringCmp(positive, "1.0"))

    Swag.__ftoa(&buffer[0], -1.9999999999'f64)
    let negative = cast(string, Swag.makeSlice(&buffer[0], cast(const cstring, &buffer[0]).count))
    Swag.assert(Swag.stringCmp(negative, "-2.0"))

    Swag.__ftoa(&buffer[0], 0.000000009'f64)
    let smallPositive = cast(string, Swag.makeSlice(&buffer[0], cast(const cstring, &buffer[0]).count))
    Swag.assert(Swag.stringCmp(smallPositive, "0.00000001"))

    Swag.__ftoa(&buffer[0], -0.000000009'f64)
    let smallNegative = cast(string, Swag.makeSlice(&buffer[0], cast(const cstring, &buffer[0]).count))
    Swag.assert(Swag.stringCmp(smallNegative, "-0.00000001"))
}
