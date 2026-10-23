#global private

struct HandlerError
{
    code: s32
}

struct RequiredResult
{
    text: string
    tag:  s32 = 19
}

enum HandlerEnum
{
    First  = 5,
    Second = 9
}

struct HandlerDefaults
{
    value: s32 = 57
}

func handlerDefaults()->HandlerDefaults fail
{
    fail HandlerError{code: 10}
}

func handlerValue(succeeds: bool)->s32 fail
{
    if not succeeds do
        fail HandlerError{code: 7}
    return 42
}

func requiredResult(succeeds: bool)->RequiredResult fail
{
    if not succeeds do
        fail HandlerError{code: 8}
    return {text: "ready"}
}

func handlerEnum()->HandlerEnum fail
{
    fail HandlerError{code: 9}
}

func handlerEarlyReturn(succeeds: bool)->s32
{
    let value = catch handlerValue(succeeds) as error else
    {
        return -assume cast(HandlerError, error).code
    }
    return value
}

func handlerRequired(succeeds: bool)->RequiredResult
{
    return catch requiredResult(succeeds) else { return {text: "fallback", tag: 23} }
}

func handlerRethrow() fail
{
    discard catch handlerValue(false) as error else { fail error }
}

var HandlerDrops: s32

struct HandlerOwnedError
{
    code: s32
}

impl HandlerOwnedError
{
    mtd opDrop() { HandlerDrops += 1 }
}

func handlerOwnedFailure() fail
{
    fail HandlerOwnedError{code: 11}
}

#test
{
    Swag.assert(handlerEarlyReturn(true) == 42)
    Swag.assert(handlerEarlyReturn(false) == -7)
    let first  = handlerRequired(true)
    let second = handlerRequired(false)
    Swag.assert(first.text == "ready" and first.tag == 19)
    Swag.assert(second.text == "fallback" and second.tag == 23)
    let enumValue = catch handlerEnum() else .Second
    Swag.assert(enumValue == .Second)
    let defaults = catch handlerDefaults() else HandlerDefaults{}
    Swag.assert(defaults.value == 57)
}

#test
{
    var total  = 0
    let first  = catch handlerValue(false) as error else assume cast(HandlerError, error).code
    let second = catch handlerValue(false) as error else assume cast(HandlerError, error).code + 1
    Swag.assert(first == 7 and second == 8)

    let error = 100
    discard catch handlerValue(false) as error else
    {
        total += assume cast(HandlerError, error).code
        discard catch handlerValue(false) as error else
        {
            total += assume cast(HandlerError, error).code
        }
        total += assume cast(HandlerError, error).code
    }
    Swag.assert(error == 100 and total == 21)
}

#test
{
    var total = 0
    for index in 4
    {
        let value = catch handlerValue(index == 1) else { continue }
        total += value
    }
    Swag.assert(total == 42)
    for 3
    {
        let value = catch handlerValue(false) else { break }
        total += value
    }
    Swag.assert(total == 42)
}

#test
{
    var saved: Swag.Error
    catch handlerRethrow() as error else do saved.capture(error)
    let error = saved.value()
    Swag.assert(error is HandlerError)
    Swag.assert(assume cast(HandlerError, error).code == 7)
    saved.reset()
    Swag.assert(saved.isEmpty())
}

#test
{
    var dropsInside = -1
    catch handlerOwnedFailure() as error else
    {
        Swag.assert(assume cast(HandlerOwnedError, error).code == 11)
        defer dropsInside = HandlerDrops
    }
    Swag.assert(dropsInside >= 0 and HandlerDrops == dropsInside + 1)
}

func handlerStoreInto(owner: *Swag.Error)
{
    catch handlerRethrow() as &owner[]
}

#test
{
    var owner: Swag.Error
    var value = -1
    catch { value = try handlerValue(true) } as &owner
    Swag.assert(value == 42 and owner.isEmpty())
    catch { value = try handlerValue(false) } as &owner
    Swag.assert(value == 42 and not owner.isEmpty())
}

var HandlerOwnerEvaluations: s32
var HandlerTypeEvaluations:  s32

#[Swag.NoInline]
func handlerTypeProbe()->s32 fail
{
    HandlerTypeEvaluations += 1
    fail 7
}

#test
{
    HandlerTypeEvaluations = 0
    var result: #decltype(expect handlerTypeProbe())
    Swag.assert(result == 0 and HandlerTypeEvaluations == 0)
}

func handlerOwnerIndex()->u64
{
    HandlerOwnerEvaluations += 1
    return 0
}

#test
{
    var owners: [1] Swag.Error
    HandlerOwnerEvaluations = 0
    let value = catch handlerValue(false) as &owners[handlerOwnerIndex()] else 17
    Swag.assert(value == 17 and HandlerOwnerEvaluations == 1)
    Swag.assert(not owners[0].isEmpty())
}

#test
{
    var error: Swag.Error
    handlerStoreInto(&error)
    let caught = error.value()
    Swag.assert(assume cast(HandlerError, caught).code == 7)
    discard catch handlerValue(true) as &error
    Swag.assert(error.isEmpty())

    let value = catch handlerValue(false) as &error else 17
    Swag.assert(value == 17 and not error.isEmpty())
    catch handlerRethrow() as &error
    Swag.assert(assume cast(HandlerError, error.value()).code == 7)
}

#test
{
    var owner: Swag.Error
    var handlers = 0
    catch {
        discard catch handlerValue(false) as error else
        {
            handlers += 1
            fail error
        }
    } as &owner
    Swag.assert(handlers == 1)
    Swag.assert(assume cast(HandlerError, owner.value()).code == 7)
}

#test
{
    var owner: Swag.Error
    catch {
        catch { fail 19's32 } as error else { fail error }
    } as &owner
    Swag.assert(assume cast(s32, owner.value()) == 19)
}

func handlerIdentity(value: s32)->s32 fail
{
    return value
}

#test
{
    var owner: Swag.Error
    let value: s64 = catch handlerIdentity(catch handlerValue(false) as error else { fail error }) as &owner else 41
    Swag.assert(value == 41)
    Swag.assert(assume cast(HandlerError, owner.value()).code == 7)
}
