#global private

alias Action  = func(*s32)
alias Value   = func(s32)->s32
alias Pointer = func()->*u8?

func increment(value: *s32) { value[] += 1 }
func twice(value: s32)->s32 => value * 2
func absent()->*u8?         => null

func(T) checked(value: T)->T fail      => value
func action()->Action fail             => &increment
func relay(value: Action)->Action fail => try checked(value)
func apply(value: Action, target: *s32) { value(target) }

#test
{
    var count: s32
    let callback = expect checked'Action(&increment)
    callback(&count)
    let zeroArguments = expect action()
    zeroArguments(&count)
    let propagated = expect relay(callback)
    propagated(&count)
    let caught = catch checked(callback) orelse &increment
    caught(&count)
    let parenthesized = (expect checked(callback))
    apply(value: (expect checked(callback)), target: &count)
    parenthesized(&count)
    Swag.assert(count == 6)
}

#test
{
    let callback = expect checked'Value(&twice)
    Swag.assert(callback(21) == 42)
    let pointer = expect checked'Pointer(&absent)
    Swag.assert(pointer() == null)
}

struct CallbackValues
{
    action:  Action
    value:   Value
    pointer: Pointer
}

#test
{
    var callbacks: CallbackValues
    callbacks.action  = expect checked'Action(&increment)
    callbacks.value   = expect checked'Value(&twice)
    callbacks.pointer = expect checked'Pointer(&absent)
    var count: s32
    defer Swag.assert(count == 1)
    defer callbacks.action(&count)
    Swag.assert(callbacks.value(12) == 24)
    Swag.assert(callbacks.pointer() == null)
}
