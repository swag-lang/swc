#global private

#[Swag.NoInline]
func failLiteralInteger() fail { fail 7 }

#[Swag.NoInline]
func failLiteralNegative() fail { fail -9 }

#[Swag.NoInline]
func failLiteralWideInteger() fail { fail 4294967296 }

#[Swag.NoInline]
func failLiteralFloat() fail { fail 1.5 }

#[Swag.NoInline]
func failLiteralCharacter() fail { fail 'A' }

// Unsuffixed literals must acquire the same concrete types as boxed constants.
#test
{
    catch failLiteralInteger() as integerError
    Swag.assert(integerError is s32)
    Swag.assert(assume cast(s32, integerError) == 7)

    catch failLiteralNegative() as negativeError
    Swag.assert(negativeError is s32)
    Swag.assert(assume cast(s32, negativeError) == -9)

    catch failLiteralWideInteger() as wideError
    Swag.assert(wideError is s64)
    Swag.assert(assume cast(s64, wideError) == 4294967296)

    catch failLiteralFloat() as floatError
    Swag.assert(floatError is f32)
    Swag.assert(assume cast(f32, floatError) == 1.5'f32)

    catch failLiteralCharacter() as characterError
    Swag.assert(characterError is rune)
    Swag.assert(assume cast(rune, characterError) == 'A')
}

#[Swag.NoInline]
func failLiteralString() fail { fail "literal failure" }

#[Swag.NoInline]
func failLiteralEmptyString() fail { fail "" }

// An empty string remains a typed failure, not an absent error.
#test
{
    catch failLiteralString() as textError
    if textError is string as value do
        Swag.assert(value[] == "literal failure")
    else do
        Swag.assert(false)

    catch failLiteralEmptyString() as emptyError
    if emptyError is string as value do
        Swag.assert(value[] == "")
    else do
        Swag.assert(false)
}

struct FailLiteralEmpty {}

#[Swag.NoInline]
func failLiteralEmptyStruct() fail { fail FailLiteralEmpty{} }

#[Swag.NoInline]
func failLiteralFalse() fail { fail false }

// Empty aggregates and false scalar values still publish their dynamic error type.
#test
{
    catch failLiteralEmptyStruct() as emptyError
    Swag.assert(emptyError is FailLiteralEmpty)

    catch failLiteralFalse() as falseError
    Swag.assert(falseError is bool)
    Swag.assert(not assume cast(bool, falseError))
}
