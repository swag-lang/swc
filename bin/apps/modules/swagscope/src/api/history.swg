#global public
#global namespace Viewer

using Core

// How many places each direction of a [[Viewer.History]] keeps.
const HistoryLimit = 128'u64

// The places a reader left inside one document, to return to and to come back from.
//
// A viewer records where the reader stood with [[Viewer.History.visit]] just before a jump the
// reader asked for: a bookmark, a link, a typed page. [[Viewer.History.back]] and
// [[Viewer.History.forward]] then exchange the place the reader stands at for the one they
// return, which the viewer shows. `T` is the viewer's own description of a place; it must not
// borrow from the view, because a place outlives every layout it was captured in.
//
// Both directions are bounded: beyond [[Viewer.HistoryLimit]] places, the oldest one is
// forgotten.
struct(T) History
{
    backVisits:    Array'T
    forwardVisits: Array'T
}

impl History
{
    // Reports whether a place was left behind and [[Viewer.History.back]] can return to it.
    mtd const canGoBack()->bool => not .backVisits.isEmpty()

    // Reports whether a return can be undone with [[Viewer.History.forward]].
    mtd const canGoForward()->bool => not .forwardVisits.isEmpty()

    // Records `current`, the place the reader is about to leave for a new one.
    //
    // A new jump starts a new branch: the places a return had left ahead are forgotten.
    mtd visit(current: T)
    {
        push(&.backVisits, current)
        .forwardVisits.clear()
    }

    // Returns the place last left behind, keeping `current` to come back to.
    //
    // The caller checks [[Viewer.History.canGoBack]] first.
    mtd back(current: T)->T
    {
        let result = .backVisits.popBack()
        push(&.forwardVisits, current)
        return result
    }

    // Returns the place the last return left, keeping `current` to return to again.
    //
    // The caller checks [[Viewer.History.canGoForward]] first.
    mtd forward(current: T)->T
    {
        let result = .forwardVisits.popBack()
        push(&.backVisits, current)
        return result
    }

    // Forgets every place, as a viewer does when it shows another document.
    mtd clear()
    {
        .backVisits.clear()
        .forwardVisits.clear()
    }

    private func push(stack: *Array'T, place: T)
    {
        if stack.count >= HistoryLimit do
            stack.removeAtOrdered(0)
        stack.add(place)
    }
}

// Returns the direction a history key asks for: -1 for Alt Left, 1 for Alt Right, zero otherwise.
func historyKeyDirection(key: const *Gui.KeyEvent)->s32
{
    if key.kind != .Pressed or key.modifiers != .Alt do
        return 0
    switch key.key
    {
    case .Left:  return -1
    case .Right: return 1
    default:     return 0
    }
}
