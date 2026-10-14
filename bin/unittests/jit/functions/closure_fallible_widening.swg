#global private

// A callable that never fails converts to a type that allows failure: the caller's error check
// after the call finds nothing raised.

struct WideningFailure
{
    code: u32
}

func runFallible(body: func||() fail) fail
{
    try body()
}

func produce(body: func||()->u64 fail)->u64 fail => try body()

func plainDouble(value: u64)->u64 => value * 2

#test
{
    var hits = 0'u32

    // A closure literal, a closure variable and a plain function all widen.
    expect runFallible(func|&hits|() { hits += 1 })
    let counter = func|&hits|() { hits += 1 }
    expect runFallible(counter)
    let doubled: func(u64)->u64 fail = &plainDouble
    let twice = expect doubled(21)
    Swag.assert(hits == 2 and twice == 42)

    // The widened value is still a fallible callable: a body that does fail keeps failing.
    let seven = expect produce(func()->u64 => 7)
    Swag.assert(seven == 7)
    discard catch produce(func()->u64 fail { fail WideningFailure{3} }) as error
    Swag.assert(error is WideningFailure)
}

// A widened call made while the caller unwinds its own failure sees no error of its own.
func failAfterWidenedCall(counter: func||()) fail
{
    defer #fail expect runFallible(counter)
    fail WideningFailure{9}
}

#test
{
    var hits = 0'u32
    catch failAfterWidenedCall(func|&hits|() { hits += 1 }) as error
    Swag.assert(error is WideningFailure and hits == 1)
}
