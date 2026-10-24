#global private

// -----------------------------------------------------------------------------
// A function that promises a value must produce one on every path. Falling off the end of a
// block body emits no 'ret' at all, so control runs into whatever was emitted next.
// -----------------------------------------------------------------------------

enum Direction { North, South }

func noReturnAtAll(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    discard flag
}

func onlyOneBranch(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    if flag do
        return 1
}

// A plain 'switch' is not exhaustive, whatever its cases cover: a value outside the enum
// reaches no case and walks past the switch.
func plainSwitch(dir: Direction)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch dir
    {
    case .North: return 1
    case .South: return 2
    }
}

// A loop that can break out leaves the function through the statement after it.
func loopWithBreak()->s32     // swc-expected-error {{sema_err_missing_return}}
{
    for
    {
        break
    }
}

func lambdaWithoutReturn()->s32
{
    let fn: func(bool)->s32 = func(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
    {
        discard flag
    }

    return fn(true)
}

// -----------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// -----------------------------------------------------------------------------

func everyBranch(flag: bool)->s32
{
    if flag do
        return 1
    return 2
}

// '#complete' is the promise that some case always matches, so the switch leaves the function.
func completeSwitch(dir: Direction)->s32
{
    switch #complete dir
    {
    case .North: return 1
    case .South: return 2
    }
}

func switchWithDefault(value: s32)->s32
{
    switch value
    {
    case 0:  return 1
    default: return 2
    }
}

// A case that falls through leaves through the body it continues into.
func switchWithFallthrough(value: s32)->s32
{
    switch value
    {
    case 0:
        fallthrough
    default:
        return 2
    }
}

func expressionBody(value: s32)->s32 => value + 1

func loopWithoutBreak()->s32
{
    for
    {
        if true do
            return 1
    }
}

func whileTrueWithoutBreak()->s32
{
    while true
    {
        if true do
            return 1
    }
}

// A nested loop's own 'break' does not leave the outer one.
func nestedBreak()->s32
{
    for
    {
        for
        {
            break
        }

        return 1
    }
}

func endsInUnreachable(flag: bool)->s32
{
    if flag do
        return 1
    unreachable
}

func endsInFail(flag: bool)->s32 fail
{
    if flag do
        return 1
    fail Swag.BaseError{"no value here"}
}

func voidNeedsNothing(flag: bool)
{
    discard flag
}

#test
{
    Swag.assert(everyBranch(true) == 1)
    Swag.assert(completeSwitch(Direction.South) == 2)
    Swag.assert(switchWithDefault(3) == 2)
    Swag.assert(switchWithFallthrough(0) == 2)
    Swag.assert(expressionBody(1) == 2)
    Swag.assert(loopWithoutBreak() == 1)
    Swag.assert(whileTrueWithoutBreak() == 1)
    Swag.assert(nestedBreak() == 1)
    Swag.assert(endsInUnreachable(true) == 1)
    Swag.assert((catch endsInFail(true)) == 1)
}
