#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-478 - Missing default case in multiple condition expression
//
// A switch handles some values and silently does nothing for the rest. The failure is
// invisible when it is written and shows up when a value is ADDED to the enum later, in code
// nobody re-read.
//
// Swag: exhaustiveness exists and is opt-in. A plain 'switch' is deliberately not exhaustive,
// whatever its cases cover; 'switch #complete' asks for the check, and adding a member then
// breaks the build at every site that promised completeness.
//
// The class therefore survives in one form - the switch that SHOULD have said '#complete' and
// did not - and it is now backstopped where it matters most: if the switch was the only thing
// producing the function's result, the missing return is rejected (CWE-758).
// -----------------------------------------------------------------------------

enum Signal
{
    Start
    Stop
    Pause
}

// --- Faults ---

// GAP language.design.001 - a plain switch covering only part of an enum compiles with no
// error and no warning: 'Pause' reaches nothing. Kept LIVE, because falling through a switch
// is defined behavior - the point being pinned is that nothing says anything.
func handleWithoutDefault(signal: Signal)->s32
{
    var handled = 0's32
    switch signal
    {
    case .Start: handled = 1
    case .Stop:  handled = 2
    }

    return handled     // GAP language.design.001: 'Pause' silently yields 0
}

#test
{
    Swag.assert(handleWithoutDefault(Signal.Pause) == 0)
}

// --- Sound ---

// '#complete' is the check. Adding a member to 'Signal' breaks this function, which is the
// whole value of the annotation.
func handleCompletely(signal: Signal)->s32
{
    switch #complete signal
    {
    case .Start: return 1
    case .Stop:  return 2
    case .Pause: return 3
    }
}

// A 'default' arm is the other way to be total.
func handleWithDefault(signal: Signal)->s32
{
    switch signal
    {
    case .Start: return 1
    default:     return 0
    }
}

// A switch that only assigns needs neither: falling through leaves the previous value, which
// is defined. This is the negative a future exhaustiveness rule must not break.
func switchThatOnlyAssigns(signal: Signal)->s32
{
    var result = -1's32
    switch signal
    {
    case .Start: result = 1
    case .Stop:  result = 2
    case .Pause: result = 3
    }

    return result
}

#test
{
    Swag.assert(handleCompletely(Signal.Pause) == 3)
    Swag.assert(handleWithDefault(Signal.Stop) == 0)
    Swag.assert(switchThatOnlyAssigns(Signal.Pause) == 3)
}
