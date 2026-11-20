#global private

struct CaseJob
{
    pending: s32
}

#test
{
    var branches = 0
    switch
    {
    case let count = 0 where count == 0: branches += 1
    }

    switch
    {
    case var enabled = false where not enabled: branches += 2
    }

    switch
    {
    case const paused = false where not paused: branches += 4
    }

    let job = CaseJob{pending: 1}
    switch
    {
    case let candidate = job where candidate.pending: branches += 8
    }

    Swag.require(branches == 15)
}

alias MaybeCaseText = string?

#[Swag.NoInline]
func caseText(trace: *s32, present: bool)->MaybeCaseText
{
    trace[] = trace[] * 10 + 1
    return present ? "" : null
}

#[Swag.NoInline]
func caseGuard(trace: *s32, passed: bool)->bool
{
    trace[] = trace[] * 10 + 2
    return passed
}

func matchCaseText(trace: *s32, present, passed: bool)->bool
{
    switch
    {
    case let text = caseText(trace, present) where caseGuard(trace, passed):
        Swag.require(text.count == 0)
        return true
    default:
        return false
    }
}

#test
{
    var trace = 0
    Swag.require(matchCaseText(&trace, true, true))
    Swag.require(trace == 12)

    trace = 0
    Swag.require(not matchCaseText(&trace, true, false))
    Swag.require(trace == 12)

    trace = 0
    Swag.require(not matchCaseText(&trace, false, true))
    Swag.require(trace == 1)

    trace = 0
    switch
    {
    case var text = caseText(&trace, false) where caseGuard(&trace, text.count == 0):
        Swag.require(false)
    case const text: string? = null where caseGuard(&trace, true):
        Swag.require(false)
    case const text: string? = "text" where caseGuard(&trace, text[0] == 't'):
        Swag.require(text.count == 4)
    default:
        Swag.require(false)
    }
    Swag.require(trace == 12)
}

#[Swag.NoInline]
func caseZero(trace: *s32)->s32
{
    trace[] = trace[] * 10 + 1
    return 0
}

func fallthroughIntoBinding(trace: *s32, passed: bool)->s32
{
    switch
    {
    case true:
        fallthrough
    case let count = caseZero(trace) where caseGuard(trace, passed):
        return count
    default:
        return 1
    }
}

func returnFromGuardedBinding(value: s32)->s32
{
    switch
    {
    case let count = value where true:
        return count
    }
}

func returnFromGuardedIfBinding(value: s32)->s32
{
    if let count = value where true do
        return count
}

#test
{
    var trace = 0
    Swag.require(fallthroughIntoBinding(&trace, true) == 0)
    Swag.require(trace == 12)

    trace = 0
    Swag.require(fallthroughIntoBinding(&trace, false) == 1)
    Swag.require(trace == 12)

    Swag.require(returnFromGuardedBinding(0) == 0)
    Swag.require(returnFromGuardedBinding(5) == 5)
    Swag.require(returnFromGuardedIfBinding(0) == 0)
    Swag.require(returnFromGuardedIfBinding(5) == 5)
}

struct ObservedBinding
{
    drops: *s32?
}

impl ObservedBinding
{
    mtd opDrop()
    {
        if .drops do
            .drops[] += 1
    }
}

#[Swag.NoInline]
func guardWhileBindingAlive(drops: *s32, passed: bool)->bool
{
    Swag.require(drops[] == 0)
    return passed
}

func checkIfBindingLifetime(passed: bool)
{
    var drops = 0
    if let binding = ObservedBinding{&drops} where guardWhileBindingAlive(&drops, passed)
    {
        Swag.require(passed and binding.drops == &drops and drops == 0)
    }
    else
    {
        Swag.require(not passed and binding.drops == &drops and drops == 0)
    }
    Swag.require(drops == 1)
}

#test
{
    checkIfBindingLifetime(true)
    checkIfBindingLifetime(false)
}

#[Swag.NoInline]
func nextObservedBinding(drops, previousDrops: *s32)->ObservedBinding
{
    Swag.require(previousDrops[] == 1 and drops[] == 0)
    return ObservedBinding{drops}
}

#test
{
    var rejectedDrops = 0
    var selectedDrops = 0
    var lastDrops     = 0
    switch
    {
    case let binding = ObservedBinding{&rejectedDrops} where guardWhileBindingAlive(&rejectedDrops, false):
        discard binding
        Swag.require(false)

    case let binding = nextObservedBinding(&selectedDrops, &rejectedDrops) where guardWhileBindingAlive(&selectedDrops, true):
        Swag.require(binding.drops == &selectedDrops and selectedDrops == 0)
        fallthrough

    case let binding = nextObservedBinding(&lastDrops, &selectedDrops) where guardWhileBindingAlive(&lastDrops, true):
        Swag.require(binding.drops == &lastDrops and lastDrops == 0)
    }
    Swag.require(rejectedDrops == 1 and selectedDrops == 1 and lastDrops == 1)
}
