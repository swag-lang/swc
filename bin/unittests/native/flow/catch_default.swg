#global private

struct CatchDefaultItem
{
    width: s32    = 640
    ratio: f32    = 1.5
    name:  string = "untitled"
}

enum CatchDefaultMode
{
    First
    Second
}

var CatchDefaultReplacements: s32 = 0

#[Swag.NoInline]
func catchDefaultItem(succeed: bool)->CatchDefaultItem fail
{
    if not succeed do
        fail Swag.BaseError{"no item"}
    return CatchDefaultItem{width: 3, ratio: 2.0, name: "item"}
}

#[Swag.NoInline]
func catchDefaultFloat(succeed: bool)->f64 fail
{
    if not succeed do
        fail Swag.BaseError{"no float"}
    return 2.5
}

#[Swag.NoInline]
func catchDefaultName(succeed: bool)->string? fail
{
    if not succeed do
        fail Swag.BaseError{"no name"}
    return "name"
}

#[Swag.NoInline]
func catchDefaultNoName()->string? fail
{
    return null
}

#[Swag.NoInline]
func catchDefaultMode(succeed: bool)->CatchDefaultMode fail
{
    if not succeed do
        fail Swag.BaseError{"no mode"}
    return .Second
}

#[Swag.NoInline]
func catchDefaultCount(succeed: bool)->s32 fail
{
    if not succeed do
        fail Swag.BaseError{"no count"}
    return 7
}

#[Swag.Discardable]
func catchDefaultDiscardable(succeed: bool)->s32 fail
{
    return try catchDefaultCount(succeed)
}

#[Swag.NoInline]
func catchDefaultFlag(succeed: bool)->bool fail
{
    if not succeed do
        fail Swag.BaseError{"no flag"}
    return true
}

#[Swag.NoInline]
func catchDefaultCheck(succeed: bool) fail
{
    if not succeed do
        fail Swag.BaseError{"check failed"}
}

func catchDefaultReplacement()->s32
{
    CatchDefaultReplacements += 1
    return 9
}

func catchDefaultNameReplacement(error: any)->string
{
    CatchDefaultReplacements += 1
    Swag.require(assume cast(Swag.BaseError, error).message == "no name")
    return "error fallback"
}

// An explicit default initializer uses the aggregate's declared field values.
#test
{
    let item = catch catchDefaultItem(false) orelse CatchDefaultItem{}
    Swag.require(item.width == 640 and item.ratio == 1.5 and item.name == "untitled")
    let found = catch catchDefaultItem(true) orelse CatchDefaultItem{}
    Swag.require(found.width == 3 and found.name == "item")

    Swag.require((catch catchDefaultFloat(false) orelse 0.0) == 0.0)
    Swag.require((catch catchDefaultFloat(true) orelse 0.0) == 2.5)
    Swag.require((catch catchDefaultName(false) orelse null) == null)
    Swag.require((catch catchDefaultMode(false) orelse .First) == .First)
    Swag.require((catch catchDefaultMode(true) orelse .First) == .Second)
}

// An assignment replaces the current value with the written fallback on failure.
#test
{
    var item = CatchDefaultItem{width: 1, ratio: 0.5, name: "old"}
    item = catch catchDefaultItem(false) orelse CatchDefaultItem{}
    Swag.require(item.width == 640 and item.name == "untitled")
}

// 'orelse V' replaces the failed result, and is evaluated on failure only.
#test
{
    CatchDefaultReplacements = 0
    Swag.require((catch catchDefaultCount(true) orelse catchDefaultReplacement()) == 7)
    Swag.require(CatchDefaultReplacements == 0)
    Swag.require((catch catchDefaultCount(false) orelse catchDefaultReplacement()) == 9)
    Swag.require(CatchDefaultReplacements == 1)

    // The operand binds tightly: the comparison reads the caught result.
    Swag.require((catch catchDefaultCount(false) orelse 0) == 0)
    Swag.require((catch catchDefaultCount(true) orelse 0) == 7)
}

// 'Swag.err' reads the error in the replacement and in the handler.
#test
{
    let message = catch catchDefaultCount(false) orelse cast(s32, Swag.err != null) * 5
    Swag.require(message == 5)
}

// A caught error and a successful null take separate branches.
#test
{
    CatchDefaultReplacements = 0
    let present = catch catchDefaultName(true) orelse catchDefaultNameReplacement(Swag.err)
    #assert(#typeof(present) == string?)
    Swag.require(present == "name")

    let missing = catch catchDefaultNoName() orelse catchDefaultNameReplacement(Swag.err)
    Swag.require(missing == null)
    Swag.require(CatchDefaultReplacements == 0)

    let failed = catch catchDefaultName(false) orelse catchDefaultNameReplacement(Swag.err)
    Swag.require(failed == "error fallback")
    Swag.require(CatchDefaultReplacements == 1)

    let filled = (catch catchDefaultNoName() orelse "error fallback") orelse "missing fallback"
    #assert(#typeof(filled) == string)
    Swag.require(filled == "missing fallback")
}

// 'as owner' keeps the error in a declared 'Swag.Error'.
#test
{
    var saved: Swag.Error
    let value = catch catchDefaultCount(false) as saved orelse 3
    Swag.require(value == 3 and not saved.isEmpty())
    discard catch catchDefaultCount(true) as saved
    Swag.require(saved.isEmpty())

    discard catch catchDefaultCount(false) as saved
    let error = assume cast(Swag.BaseError, saved.value())
    Swag.require(error.message == "no count")
}

// A discardable call can be caught as a statement with or without an error owner.
#test
{
    catch catchDefaultDiscardable(false)

    var saved: Swag.Error
    catch catchDefaultDiscardable(false) as saved
    Swag.require(assume cast(Swag.BaseError, saved.value()).message == "no count")
    catch catchDefaultDiscardable(true) as saved
    Swag.require(saved.isEmpty())
}

func catchDefaultLeave(succeed: bool)->s32
{
    let value = catch catchDefaultCount(succeed) { return -1 }
    return value
}

// A handler directly follows the operand; on a value it must leave the flow.
#test
{
    Swag.require(catchDefaultLeave(true) == 7)
    Swag.require(catchDefaultLeave(false) == -1)

    var handled = 0
    catch catchDefaultCheck(false) { handled += 1 }
    catch catchDefaultCheck(true) do handled += 10
    catch catchDefaultCheck(false)
    {
        Swag.require(Swag.err != null)
        handled += 100
    }

    Swag.require(handled == 101)
}

// In a control-statement header, the '{' after the operand opens the statement body.
#test
{
    var taken = 0
    if catch catchDefaultFlag(true) orelse false { taken += 1 }
    if catch catchDefaultFlag(false) orelse false { taken += 1000 }
    if catch catchDefaultFlag(true) orelse false do taken += 10
    while catch catchDefaultFlag(false) orelse false { taken += 1000 }
    switch catch catchDefaultCount(false) orelse 0
    {
    case 0:
        taken += 100
    default:
        break
    }

    Swag.require(taken == 111)
}
