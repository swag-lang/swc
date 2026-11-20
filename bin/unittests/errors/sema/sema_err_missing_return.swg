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
    if flag do     // swc-expected-note {{sema_note_condition_false_continues}}
        return 1
}

#[Swag.Incomplete]
enum OpenDirection { North, South }

// Listing every named value of an open enum still leaves room for an unmatched value.
func openEnumSwitch(dir: OpenDirection)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch dir     // swc-expected-note {{sema_note_switch_miss_continues}}
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
        break     // swc-expected-note {{sema_note_loop_break_continues}}
    }
}

func completeSwitchPartialCase(dir: Direction, ready: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch #complete dir
    {
    case .North: return 1
    case .South:     // swc-expected-note {{sema_note_switch_case_continues}}
        if ready do     // swc-expected-note {{sema_note_condition_false_continues}}
            return 2
    }
}

func completeSwitchFallthrough(dir: Direction)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch #complete dir
    {
    case .North:
        fallthrough
    case .South:     // swc-expected-note {{sema_note_switch_case_continues}}
        discard dir
    }
}

// A fallthrough that resumes testing can miss every remaining case, even after a default.
func typedFallthroughMiss(value: const any)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch value
    {
    case bool: return 1
    default:   fallthrough     // swc-expected-note {{sema_note_function_continues}}
    case s32:  return 2
    }
}

func bindingFallthroughMiss(value: *s32?, flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch
    {
    default:
        if flag do
            fallthrough     // swc-expected-note {{sema_note_function_continues}}
        else do
            return 1
    case let item = value: return item[]
    }
}

func nestedLoopExit(ready, waiting: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    if ready     // swc-expected-note {{sema_note_condition_false_continues}}
    {
        return 1
    }
    else
    {
        while waiting do     // swc-expected-note {{sema_note_condition_false_continues}}
            return 2
    }
}

func nestedTrueBranch(ready, waiting: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    if ready     // swc-expected-note {{sema_note_condition_true_continues}}
    {
        if waiting do     // swc-expected-note {{sema_note_condition_false_continues}}
            return 1
    }
    else
    {
        return 2
    }
}

func outerBreak(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    while true
    {
        for
        {
            break
        }

        if flag do
            return 1
        break     // swc-expected-note {{sema_note_loop_break_continues}}
    }
}

func countedLoopExit(count: u32)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    for count do     // swc-expected-note {{sema_note_loop_finishes_continues}}
        return 1
}

func cStyleLoopExit(limit: s32)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    for var i = 0; i < limit; i += 1 do     // swc-expected-note {{sema_note_condition_false_continues}}
        return i
}

func collectionLoopExit(values: const [..] s32)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    for value in values do     // swc-expected-note {{sema_note_loop_finishes_continues}}
        return value
}

func matchingBindingContinues(value: s32)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    if var current = value where current > 0     // swc-expected-note {{sema_note_binding_match_continues}}
    {
        discard current
    }
    else
    {
        return 0
    }
}

// An exit before a return can bypass it and leave the function.
func namedScopeExit(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    scope(Done)
    {
        while flag
        {
            break to Done     // swc-expected-note {{sema_note_function_continues}}
        }
        return 1
    }
}

func switchCaseExit(flag: bool, value: s32)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch value
    {
    case 0:     // swc-expected-note {{sema_note_switch_case_continues}}
        if flag do
            break
        return 1
    default:
        return 2
    }
}

func inactiveStaticIfReturn()->s32     // swc-expected-error {{sema_err_missing_return}}
{
    #static if false
    {
        return 1
    }
}

func inactiveStaticSwitchReturn()->s32     // swc-expected-error {{sema_err_missing_return}}
{
    #static switch 1
    {
    case 0:
        return 1
    default:
        discard 0
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

func typedFallthroughWithFallback(value: const any)->s32
{
    switch value
    {
    case bool: fallthrough
    case s32:  return 2
    default:   return 3
    }
}

func typedFallthroughWithTrueGuard(value: const any)->s32
{
    switch value
    {
    default:         fallthrough
    case s32:        return 1
    case where true: return 2
    }
}

func bindingFallthroughWithTrueCase(value: *s32?)->s32
{
    switch
    {
    default:   fallthrough
    case let item = value: return item[]
    case true: return 2
    }
}

func deadFallthroughAfterDefault(value: const any)->s32
{
    switch value
    {
    default:   return 1
    case bool: fallthrough
    case s32:  return 2
    }
}

func valueFallthroughSkipsGuard(value: s32)->s32
{
    switch value
    {
    default: fallthrough
    case 0 where false: return 1
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

func breakToInnerScope(flag: bool)->s32
{
    scope(Done)
    {
        scope(Done)
        {
            if flag do
                break to Done
            return 1
        }
        return 2
    }
}

func excludedScopedBreak()->s32
{
    scope(Done)
    {
        #static if false
        {
            break to Done
        }
        return 3
    }
}

func excludedGuardBreaks(values: const [..] s32)->s32
{
    scope(Done)
    {
        for 0 do
            break to Done

        for value in values where false
        {
            discard value
            break to Done
        }

        if var bound = 1 where false
        {
            discard bound
            break to Done
        }

        return 5
    }
}

func excludedLoopBreak()->s32
{
    for
    {
        if false do
            break
        return 4
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
    Swag.require(everyBranch(true) == 1)
    Swag.require(completeSwitch(Direction.South) == 2)
    Swag.require(switchWithDefault(3) == 2)
    Swag.require(switchWithFallthrough(0) == 2)
    Swag.require(expressionBody(1) == 2)
    Swag.require(loopWithoutBreak() == 1)
    Swag.require(whileTrueWithoutBreak() == 1)
    Swag.require(nestedBreak() == 1)
    Swag.require(breakToInnerScope(false) == 1 and breakToInnerScope(true) == 2)
    Swag.require(excludedScopedBreak() == 3)
    Swag.require(excludedLoopBreak() == 4)
    Swag.require(excludedGuardBreaks([1]) == 5)
    Swag.require(endsInUnreachable(true) == 1)
    Swag.require((catch endsInFail(true) orelse 0) == 1)
}

// Attributes preserve the body's paths; they do not turn a conditional exit into a total one.
func attributedPartialReturn(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    #[Swag.Warning("sema_warn_unreachable_code", .Warning)]
    {
        if flag do return 1
    }
}

// A return in an attributed nested declaration belongs to that declaration.
func attributedNestedFunction()->s32     // swc-expected-error {{sema_err_missing_return}}
{
    #[Swag.Safety(.BoundCheck, false)]
    func nested()->s32
    {
        return 1
    }
    discard nested()
}

func switchNullableBindingWhereTrue(value: *s32?)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch
    {
    case let item = value where true:
        return item[]
    }
}

func ifNullableBindingWhereTrue(value: *s32?)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    if let item = value where true do
        return item[]
}
