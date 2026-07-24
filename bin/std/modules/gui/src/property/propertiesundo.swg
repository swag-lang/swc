#global public

using Core, Pixel

// Undo/redo for the property grid, built on the generic gui UndoManager (undomgr.swg).
//
// Every field edit funnels through Properties.hasChanged. There, the new value is diffed
// against a per-row snapshot (PropertiesItem.undoValue) captured at build; when it differs a
// PropUndoCommand holding the old and new value (across all edited instances) is pushed. undo
// and redo restore the recorded value with the same content-aware copy the "reset to default"
// feature uses (String by content, everything else by raw bytes), then re-run the grid's
// refresh/notify tail so editors, validation, revert markers and IPropertyNotify all update.
//
// Only rows the grid can byte-copy safely are recorded (POD values and dynamic String, i.e.
// the same set as canHaveDefault). Structural array edits (add/remove/move) are not covered.

// A captured copy of one field's value across every edited instance. Strings are copied by
// content (they own a heap buffer); every other supported type is copied as raw bytes.
// The per-instance addresses are captured too, so a value can be restored without the row
// it was recorded against: undo commands stay valid across a grid rebuild (clearStructs +
// addStruct), as long as the edited instances themselves are still alive.
struct PropFieldValue
{
    valid:    bool
    isString: bool
    n:        u64                   // number of instances captured
    sz:       u64                   // per-instance byte size (raw-bytes case only)
    addrs:    Array'(#null *u8)     // field address in each captured instance
    bytes:    Array'u8              // n * sz contiguous raw bytes (raw-bytes case)
    strings:  Array'String          // n strings (String case)
}

impl PropFieldValue
{
    // True for the types the grid can snapshot/restore safely: dynamic String (by content) or
    // any POD value (native/enum/bool/color/vector/POD struct/static array of POD).
    func canSnapshot(type: #null typeinfo)->bool
    {
        if !type do
            return false
        if type == Core.String do
            return true
        return Reflection.isPod(type)
    }

    // Snapshot the current value of 'item' across all its edited instances. Leaves the value
    // invalid for rows that cannot be snapshotted.
    mtd capture(prop: *Properties, item: *PropertiesItem)
    {
        .valid    = false
        .isString = false
        .n        = 0
        .sz       = 0
        .addrs.clear()
        .bytes.clear()
        .strings.clear()

        if !item.data or !item.type do
            return
        if !canSnapshot(item.type) do
            return

        // Rows inside a dynamic array live in a heap buffer that array add/remove/resize can
        // move or free (taking the row with it). Recording their raw address would dangle, so —
        // like the reset-to-default feature — they are left out of the undo history.
        if prop.isUnderDynamicArray(item) do
            return

        .n = prop.instanceCount(item)
        .addrs.reserve(.n)
        for [k] in .n do
            .addrs.add(prop.instanceAddr(item, k))

        if item.type == Core.String
        {
            .isString = true
            .strings.reserve(.n)
            for [k] in .n do
                .strings.add(dref notnull cast(#null *String) .addrs[k])
        }
        else
        {
            .sz = item.type.sizeof
            if .sz == 0 do
                return
            .bytes.resize(.n * .sz)
            for [k] in .n do
                Memory.copy(cast(#null [*] void) (.bytes.buffer + k * .sz), cast(#null const [*] void) .addrs[k], .sz)
        }

        .valid = true
    }

    // Write the captured value back into every captured instance address. Self-contained on
    // purpose: the row the value was recorded against may be gone (grid rebuilt), only the
    // edited instances need to be alive.
    mtd restore()
    {
        if !.valid do
            return

        if .isString
        {
            for [k] in .n do
                dref notnull cast(#null *String) .addrs[k] = .strings[k]
        }
        else
        {
            for [k] in .n do
                Memory.copy(cast(#null [*] void) .addrs[k], cast(#null const [*] void) (.bytes.buffer + k * .sz), .sz)
        }
    }

    // Value equality (used to skip recording a no-op change).
    mtd isEqual(o: *PropFieldValue)->bool
    {
        if .isString != o.isString do
            return false
        if .n != o.n do
            return false

        if .isString
        {
            for [k] in .n
            {
                if .strings[k] != o.strings[k] do
                    return false
            }

            return true
        }

        if .sz != o.sz do
            return false
        if .bytes.count != o.bytes.count do
            return false
        for [i] in .bytes.count
        {
            if .bytes[i] != o.bytes[i] do
                return false
        }

        return true
    }
}

// One undoable property edit: restore the old/new value at the instance addresses it was
// captured on. The command does not reference the row it came from: 'generation' records
// the grid content it was built against, so a command replayed after a rebuild silently
// skips the row refresh (the values still land at the right addresses).
struct PropUndoCommand
{
    prop:       #late *Properties
    generation: u64
    oldVal:     PropFieldValue
    newVal:     PropFieldValue
}

impl IUndoCommand for PropUndoCommand
{
    mtd impl redo()
    {
        .newVal.restore()
        .prop.postUndoRefresh(.generation)
    }

    mtd impl undo()
    {
        .oldVal.restore()
        .prop.postUndoRefresh(.generation)
    }
}

internal impl Properties
{
    // Capture the undo snapshot of every row created since 'fromIdx' (called at build time,
    // after the instance addresses are assigned).
    mtd assignUndoSnapshots(fromIdx: u64)
    {
        for [i] in fromIdx until .items.count
        {
            let it = notnull .items[i]
            it.undoValue.capture(me, it)
        }
    }

    // Diff the row's current value against its snapshot; on a real change, push one undo
    // command holding the before/after value, then resync the snapshot. Called from hasChanged.
    // While a slider drag is active on the row (beginItemDrag), every move after the first is
    // folded into the command recorded at the first move, so the whole drag is one undo step.
    mtd recordUndo(item: *PropertiesItem)
    {
        if !.undoEnabled do
            return

        var cur: PropFieldValue
        cur.capture(me, item)
        if !cur.valid do
            return

        if item.undoValue.valid and !item.undoValue.isEqual(&cur)
        {
            if .dragItem == item and .dragCmd
            {
                .dragCmd.newVal = cur
            }
            else
            {
                let cmd = Memory.new'PropUndoCommand()
                cmd.prop       = me
                cmd.generation = .generation
                cmd.oldVal     = item.undoValue
                cmd.newVal     = cur
                .activeUndoMgr().pushCmd(cast(IUndoCommand) cmd, 0, false)
                if .dragItem == item do
                    .dragCmd = cmd
            }
        }

        item.undoValue = cur
    }

    // Refresh/notify tail of an undo/redo restore. When the command predates the current grid
    // content (generation mismatch), the rows it knew are gone: the values are already restored
    // at their addresses, there is nothing to refresh here.
    mtd postUndoRefresh(generation: u64)
    {
        if generation != .generation do
            return

        .applyingUndo = true
        .refresh()

        // Resync every row snapshot with the restored values, so the next edit diffs against
        // the timeline position we just moved to.
        for it in .items
        {
            let itn = notnull it
            itn.undoValue.capture(me, itn)
        }

        var relayout = .updateValidation()
        if .updateDefaults() do
            relayout = true
        if relayout
        {
            .applyLayout()
            .scrollWnd.view.sendResizeEvent()
        }

        // Item-agnostic notification: the restored command may span rows that no longer exist,
        // so the signal and the host notify are called without a row.
        .sigChanged.call(me, null)
        if .hostNtfy do
            .hostNtfy.itemHasChanged(me, null)

        .applyingUndo = false
        .invalidate()
    }

    // A slider drag started on 'item': coalesce the undo commands of the drag into one.
    mtd beginItemDrag(item: *PropertiesItem)
    {
        .dragItem = item
        .dragCmd  = null
    }

    mtd endItemDrag()
    {
        .dragItem = null
        .dragCmd  = null
    }
}

// Public undo/redo entry points for hosts (menus, toolbars, shortcuts).
public impl Properties
{
    // Record the grid's undo commands into an external UndoManager instead of the grid's own
    // one, so property edits and the host's other commands share a single undo timeline. The
    // grid must stay alive as long as the external manager holds commands recorded by it.
    // Pass null to go back to the internal manager.
    mtd setExternalUndoMgr(mgr: #null *UndoManager)
    {
        .externUndoMgr = mgr
    }

    mtd canUndo()->bool
    {
        return .activeUndoMgr().canUndo()
    }

    mtd canRedo()->bool
    {
        return .activeUndoMgr().canRedo()
    }

    mtd undo()
    {
        .activeUndoMgr().undo()
    }

    mtd redo()
    {
        .activeUndoMgr().redo()
    }

    // Drop the whole undo history (e.g. after loading a fresh object into the grid).
    mtd clearUndo()
    {
        .activeUndoMgr().clear()
        for it in .items
        {
            let itn = notnull it
            itn.undoValue.capture(me, itn)
        }
    }

    // Turn recording on/off (e.g. to batch programmatic changes without polluting the history).
    mtd setUndoEnabled(on: bool)
    {
        .undoEnabled = on
    }
}

internal impl Properties
{
    mtd activeUndoMgr()->*UndoManager
    {
        if .externUndoMgr do
            return .externUndoMgr
        return &.undoMgr
    }
}
