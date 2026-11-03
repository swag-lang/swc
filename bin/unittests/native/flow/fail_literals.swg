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
    Swag.require(integerError is s32)
    Swag.require(assume cast(s32, integerError) == 7)

    var negativeErrorOutcome: Swag.Error
    catch failLiteralNegative() as negativeErrorOutcome
    let negativeError = negativeErrorOutcome.value()
    Swag.require(negativeError is s32)
    Swag.require(assume cast(s32, negativeError) == -9)

    var wideErrorOutcome: Swag.Error
    catch failLiteralWideInteger() as wideErrorOutcome
    let wideError = wideErrorOutcome.value()
    Swag.require(wideError is s64)
    Swag.require(assume cast(s64, wideError) == 4294967296)

    var floatErrorOutcome: Swag.Error
    catch failLiteralFloat() as floatErrorOutcome
    let floatError = floatErrorOutcome.value()
    Swag.require(floatError is f32)
    Swag.require(assume cast(f32, floatError) == 1.5'f32)

    var characterErrorOutcome: Swag.Error
    catch failLiteralCharacter() as characterErrorOutcome
    let characterError = characterErrorOutcome.value()
    Swag.require(characterError is rune)
    Swag.require(assume cast(rune, characterError) == 'A')
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
        Swag.require(value[] == "literal failure")
    else do
        Swag.require(false)

    var emptyErrorOutcome: Swag.Error
    catch failLiteralEmptyString() as emptyErrorOutcome
    let emptyError = emptyErrorOutcome.value()
    if emptyError is string as value do
        Swag.require(value[] == "")
    else do
        Swag.require(false)
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
    Swag.require(emptyError is FailLiteralEmpty)

    var falseErrorOutcome: Swag.Error
    catch failLiteralFalse() as falseErrorOutcome
    let falseError = falseErrorOutcome.value()
    Swag.require(falseError is bool)
    Swag.require(not assume cast(bool, falseError))
}
