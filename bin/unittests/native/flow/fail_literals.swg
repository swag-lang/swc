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
    var integerErrorOutcome: Swag.Error
    catch failLiteralInteger() as integerErrorOutcome
    let integerError = integerErrorOutcome.value()
    Swag.assert(integerError is s32)
    Swag.assert(assume cast(s32, integerError) == 7)

    var negativeErrorOutcome: Swag.Error
    catch failLiteralNegative() as negativeErrorOutcome
    let negativeError = negativeErrorOutcome.value()
    Swag.assert(negativeError is s32)
    Swag.assert(assume cast(s32, negativeError) == -9)

    var wideErrorOutcome: Swag.Error
    catch failLiteralWideInteger() as wideErrorOutcome
    let wideError = wideErrorOutcome.value()
    Swag.assert(wideError is s64)
    Swag.assert(assume cast(s64, wideError) == 4294967296)

    var floatErrorOutcome: Swag.Error
    catch failLiteralFloat() as floatErrorOutcome
    let floatError = floatErrorOutcome.value()
    Swag.assert(floatError is f32)
    Swag.assert(assume cast(f32, floatError) == 1.5'f32)

    var characterErrorOutcome: Swag.Error
    catch failLiteralCharacter() as characterErrorOutcome
    let characterError = characterErrorOutcome.value()
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
    var textErrorOutcome: Swag.Error
    catch failLiteralString() as textErrorOutcome
    let textError = textErrorOutcome.value()
    if textError is string as value do
        Swag.assert(value[] == "literal failure")
    else do
        Swag.assert(false)

    var emptyErrorOutcome: Swag.Error
    catch failLiteralEmptyString() as emptyErrorOutcome
    let emptyError = emptyErrorOutcome.value()
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
    var emptyErrorOutcome: Swag.Error
    catch failLiteralEmptyStruct() as emptyErrorOutcome
    let emptyError = emptyErrorOutcome.value()
    Swag.assert(emptyError is FailLiteralEmpty)

    var falseErrorOutcome: Swag.Error
    catch failLiteralFalse() as falseErrorOutcome
    let falseError = falseErrorOutcome.value()
    Swag.assert(falseError is bool)
    Swag.assert(not assume cast(bool, falseError))
}
