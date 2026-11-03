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
    let value = catch handlerValue(succeeds)
    {
        return -assume cast(HandlerError, Swag.err).code
    }
    return value
}

func handlerRequired(succeeds: bool)->RequiredResult
{
    return catch requiredResult(succeeds) { return {text: "fallback", tag: 23} }
}

func handlerRethrow() fail
{
    discard catch handlerValue(false) { fail Swag.err }
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
    Swag.require(handlerEarlyReturn(true) == 42)
    Swag.require(handlerEarlyReturn(false) == -7)
    let first  = handlerRequired(true)
    let second = handlerRequired(false)
    Swag.require(first.text == "ready" and first.tag == 19)
    Swag.require(second.text == "fallback" and second.tag == 23)
    let enumValue = catch handlerEnum() orelse .Second
    Swag.require(enumValue == .Second)
    let defaults = catch handlerDefaults() orelse HandlerDefaults{}
    Swag.require(defaults.value == 57)
}

#test
{
    var total  = 0
    let first  = catch handlerValue(false) orelse assume cast(HandlerError, Swag.err).code
    let second = catch handlerValue(false) orelse assume cast(HandlerError, Swag.err).code + 1
    Swag.require(first == 7 and second == 8)

    let error = 100
    discard catch handlerValue(false)
    {
        total += assume cast(HandlerError, Swag.err).code
        discard catch handlerValue(false)
        {
            total += assume cast(HandlerError, Swag.err).code
        }
        total += assume cast(HandlerError, Swag.err).code
    }
    Swag.require(error == 100 and total == 21)
}

#test
{
    var total = 0
    for index in 4
    {
        let value = catch handlerValue(index == 1) { continue }
        total += value
    }
    Swag.require(total == 42)
    for 3
    {
        let value = catch handlerValue(false) { break }
        total += value
    }
    Swag.require(total == 42)
}

#test
{
    var saved: Swag.Error
    catch handlerRethrow() do saved.capture(Swag.err)
    let error = saved.value()
    Swag.require(error is HandlerError)
    Swag.require(assume cast(HandlerError, error).code == 7)
    saved.reset()
    Swag.require(saved.isEmpty())
}

#test
{
    var dropsInside = -1
    catch handlerOwnedFailure()
    {
        Swag.require(assume cast(HandlerOwnedError, Swag.err).code == 11)
        defer dropsInside = HandlerDrops
    }
    Swag.require(dropsInside >= 0 and HandlerDrops == dropsInside + 1)
}

func handlerStoreInto(owner: *Swag.Error)
{
    catch handlerRethrow() as owner[]
}

#test
{
    var owner: Swag.Error
    var value = -1
    catch { value = try handlerValue(true) } as owner
    Swag.require(value == 42 and owner.isEmpty())
    catch { value = try handlerValue(false) } as owner
    Swag.require(value == 42 and not owner.isEmpty())
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
    Swag.require(result == 0 and HandlerTypeEvaluations == 0)
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
    let value = catch handlerValue(false) as owners[handlerOwnerIndex()] orelse 17
    Swag.require(value == 17 and HandlerOwnerEvaluations == 1)
    Swag.require(not owners[0].isEmpty())
}

#test
{
    var error: Swag.Error
    handlerStoreInto(&error)
    let caught = error.value()
    Swag.require(assume cast(HandlerError, caught).code == 7)
    discard catch handlerValue(true) as error
    Swag.require(error.isEmpty())

    let value = catch handlerValue(false) as error orelse 17
    Swag.require(value == 17 and not error.isEmpty())
    catch handlerRethrow() as error
    Swag.require(assume cast(HandlerError, error.value()).code == 7)
}

#test
{
    var owner: Swag.Error
    var handlers = 0
    catch {
        discard catch handlerValue(false)
        {
            handlers += 1
            fail Swag.err
        }
    } as owner
    Swag.require(handlers == 1)
    Swag.require(assume cast(HandlerError, owner.value()).code == 7)
}

#test
{
    var owner: Swag.Error
    catch {
        catch { fail 19's32 } { fail Swag.err }
    } as owner
    Swag.require(assume cast(s32, owner.value()) == 19)
}

func handlerIdentity(value: s32)->s32 fail
{
    return value
}

#test
{
    var owner: Swag.Error
    let value: s64 = catch handlerIdentity(catch handlerValue(false) { fail Swag.err }) as owner orelse 41
    Swag.require(value == 41)
    Swag.require(assume cast(HandlerError, owner.value()).code == 7)
}
