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

// A failure resumes with the value 'var x: T' would hold: field initializers run.
#test
{
    let item = catch catchDefaultItem(false)
    Swag.assert(item.width == 640 and item.ratio == 1.5 and item.name == "untitled")
    let found = catch catchDefaultItem(true)
    Swag.assert(found.width == 3 and found.name == "item")

    Swag.assert((catch catchDefaultFloat(false)) == 0.0)
    Swag.assert((catch catchDefaultFloat(true)) == 2.5)
    Swag.assert((catch catchDefaultName(false)) == null)
    Swag.assert((catch catchDefaultMode(false)) == .First)
    Swag.assert((catch catchDefaultMode(true)) == .Second)
}

// Assigning a caught result writes the default into an existing variable too.
#test
{
    var item = CatchDefaultItem{width: 1, ratio: 0.5, name: "old"}
    item = catch catchDefaultItem(false)
    Swag.assert(item.width == 640 and item.name == "untitled")
}

// 'orelse V' replaces the failed result, and is evaluated on failure only.
#test
{
    CatchDefaultReplacements = 0
    Swag.assert((catch catchDefaultCount(true) orelse catchDefaultReplacement()) == 7)
    Swag.assert(CatchDefaultReplacements == 0)
    Swag.assert((catch catchDefaultCount(false) orelse catchDefaultReplacement()) == 9)
    Swag.assert(CatchDefaultReplacements == 1)

    // The operand binds tightly: the comparison reads the caught result.
    Swag.assert(catch catchDefaultCount(false) == 0)
    Swag.assert(catch catchDefaultCount(true) == 7)
}

// 'Swag.err' reads the error in the replacement and in the handler.
#test
{
    let message = catch catchDefaultCount(false) orelse cast(s32, Swag.err != null) * 5
    Swag.assert(message == 5)
}

// With a nullable result, 'orelse' also replaces a successful null.
#test
{
    let present: string = catch catchDefaultName(true) orelse "fallback"
    Swag.assert(present == "name")
    let failed: string = catch catchDefaultName(false) orelse "fallback"
    Swag.assert(failed == "fallback")
    let empty: string = catch catchDefaultNoName() orelse "fallback"
    Swag.assert(empty == "fallback")
}

// 'as owner' keeps the error in a declared 'Swag.Error'.
#test
{
    var saved: Swag.Error
    let value = catch catchDefaultCount(false) as saved orelse 3
    Swag.assert(value == 3 and not saved.isEmpty())
    discard catch catchDefaultCount(true) as saved
    Swag.assert(saved.isEmpty())
}

func catchDefaultLeave(succeed: bool)->s32
{
    let value = catch catchDefaultCount(succeed) { return -1 }
    return value
}

// A handler directly follows the operand; on a value it must leave the flow.
#test
{
    Swag.assert(catchDefaultLeave(true) == 7)
    Swag.assert(catchDefaultLeave(false) == -1)

    var handled = 0
    catch catchDefaultCheck(false) { handled += 1 }
    catch catchDefaultCheck(true) do handled += 10
    catch catchDefaultCheck(false)
    {
        Swag.assert(Swag.err != null)
        handled += 100
    }

    Swag.assert(handled == 101)
}

// In a control-statement header, the '{' after the operand opens the statement body.
#test
{
    var taken = 0
    if catch catchDefaultFlag(true) { taken += 1 }
    if catch catchDefaultFlag(false) { taken += 1000 }
    if catch catchDefaultFlag(true) do taken += 10
    while catch catchDefaultFlag(false) { taken += 1000 }
    switch catch catchDefaultCount(false)
    {
    case 0:
        taken += 100
    default:
        break
    }

    Swag.assert(taken == 111)
}
