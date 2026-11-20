#global private

enum State
{
    Ready = 0
    Alias = Ready
    Running
    Done
}

#[Swag.Inline]
func rank(state: State, preferReady: bool)->s32
{
    switch state
    {
    case .Ready where preferReady: return 1
    case .Ready where true:        return 2
    case .Running to .Done:        return 3
    }
}

func skipUnrelatedStates(state: State)->s32
{
    switch state
    {
    case .Running: return 1
    default:       break
    }

    return 0
}

#[Swag.EnumFlags]
enum Flags { Read, Write }

func readOnly(flags: Flags)->bool
{
    switch flags
    {
    case .Read: return true
    }

    return false
}

#[Swag.Incomplete]
enum OpenState { Found }

func wasFound(state: OpenState)->bool
{
    switch state
    {
    case .Found: return true
    }

    return false
}

func isSmallInteger(value: const any)->bool
{
    switch value
    {
    case s32 as integer where integer[] < 10: return true
    }

    return false
}

#test
{
    Swag.require(rank(State.Alias, false) == 2)
    Swag.require(rank(State.Ready, true) == 1)
    Swag.require(rank(State.Done, false) == 3)
    Swag.require(skipUnrelatedStates(State.Ready) == 0)
    Swag.require(skipUnrelatedStates(State.Running) == 1)
    Swag.require(readOnly(Flags.Read))
    Swag.require(not readOnly(Flags.Read | Flags.Write))
    Swag.require(wasFound(OpenState.Found))
    Swag.require(not wasFound(cast(OpenState, 9)))
    Swag.require(isSmallInteger(5's32))
    Swag.require(not isSmallInteger("5"))
}

enum FloatState: f32
{
    Zero         = 0.0
    NegativeZero = -0.0
    One          = 1.0
}

func floatRank(state: FloatState)->s32
{
    switch state
    {
    case .Zero: return 0
    case .One:  return 1
    }
}

#test
{
    Swag.require(floatRank(FloatState.NegativeZero) == 0)
    Swag.require(floatRank(FloatState.One) == 1)
}

enum Kind { Absent = 1, Number }

union Value(Kind)
{
    case .Number:
    number: s32
}

func numberOrZero(value: Value)->s32
{
    switch value
    {
    case .Absent: return 0
    case .Number: return value.number
    }
}

func hasNumber(value: Value)->bool
{
    switch Swag.kindOf(value)
    {
    case .Absent: return false
    case .Number: return true
    }
}

#test
{
    let absent:  Value = .Absent
    let present: Value = .Number{42}
    Swag.require(numberOrZero(absent) == 0)
    Swag.require(numberOrZero(present) == 42)
    Swag.require(not hasNumber(absent))
    Swag.require(hasNumber(present))
}

enum NonZeroState { Ready = 1, Done }

#[Swag.Safety(.Switch, true)]
func isReadyOrDone(state: NonZeroState)->bool
{
    switch state
    {
    case .Ready, .Done: return true
    }

    return false
}

enum SignedState { Before = -1, After = 1 }

func coveredByRange(state: SignedState)->bool
{
    switch state
    {
    case .Before to .After: return true
    }
}

enum TextState: string? { Active = "active", Idle = "idle" }

func isNamed(state: TextState)->bool
{
    switch state
    {
    case .Active, .Idle: return true
    }

    return false
}

enum TextWithEmpty: string? { Empty = "", Active = "active" }

func isEmpty(state: TextWithEmpty)->bool
{
    switch state
    {
    case .Empty:  return true
    case .Active: return false
    }
}

enum NamedText: string { Active = "active", Idle = "idle" }

func isActive(state: NamedText)->bool
{
    switch state
    {
    case .Active: return true
    case .Idle:   return false
    }
}

#test
{
    var unnamedNumber: NonZeroState
    var insideRange:   SignedState
    var unnamedText:   TextState
    var namedEmpty:    TextWithEmpty

    Swag.require(isReadyOrDone(NonZeroState.Ready))
    Swag.require(not isReadyOrDone(unnamedNumber))
    Swag.require(coveredByRange(insideRange))
    Swag.require(isNamed(TextState.Active))
    Swag.require(not isNamed(unnamedText))
    Swag.require(isEmpty(namedEmpty))
    Swag.require(isActive(NamedText.Active))
}
