#global private

#[Swag.NoInline]
func raiseDeferredPatternError() fail
{
    fail 7's32
}

// Catch handlers are emitted separately from their managed expression.
#test
{
    var matched = false
    catch raiseDeferredPatternError() else
    {
        if Swag.getContext().curError is s32 as error do
            matched = error[] == 7
    }
    Swag.assert(matched)
}

#[Swag.NoInline]
func deferredPatternBinding(value: s32, result: *s32, early: bool)
{
    defer
    {
        let boxed: any = &value
        if boxed is s32 as number where number[] > 0 do
            result[] += number[]
    }
    if early do
        return
}

// One deferred binding is emitted on two exit paths; neither address can serve the other.
#test
{
    var result = 0
    deferredPatternBinding(7, &result, true)
    deferredPatternBinding(11, &result, false)
    Swag.assert(result == 18)
}

// Switch condition bindings use the same stack-address materialization as if bindings.
#test
{
    var result = 0
    catch raiseDeferredPatternError() else
    {
        let error = Swag.getContext().curError
        switch error
        {
        case s64:
            result = -1
        case s32 as number where number[] == 7:
            result = number[]
        default:
            result = -2
        }
    }
    Swag.assert(result == 7)
}
