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
// Swag: a runtime switch over a closed enum needs cases for all declared values or a default.
// -----------------------------------------------------------------------------

enum Signal
{
    Start
    Stop
    Pause
}

// --- Faults ---

func handleWithoutDefault(signal: Signal)
{
    switch signal     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case .Start, .Stop: break
    }
}

// --- Sound ---

// Adding a member to 'Signal' requires choosing its behavior here.
func handleCompletely(signal: Signal)->s32
{
    switch signal
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

// The default explicitly preserves the current value for other signals.
func handleStartOnly(signal: Signal)->s32
{
    var result = -1's32
    switch signal
    {
    case .Start: result = 1
    default:     break
    }

    return result
}

#test
{
    Swag.require(handleCompletely(Signal.Pause) == 3)
    Swag.require(handleWithDefault(Signal.Stop) == 0)
    Swag.require(handleStartOnly(Signal.Pause) == -1)
}
