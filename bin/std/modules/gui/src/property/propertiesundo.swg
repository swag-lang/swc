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
struct PropFieldValue
{
    valid:      bool
    isString:   bool
    n:          u64             // number of instances captured
    sz:         u64             // per-instance byte size (raw-bytes case only)
    bytes:      Array'u8        // n * sz contiguous raw bytes (raw-bytes case)
    strings:    Array'String    // n strings (String case)
}

impl PropFieldValue
{
    // True for the types the grid can snapshot/restore safely: dynamic String (by content) or
    // any POD value (native/enum/bool/color/vector/POD struct/static array of POD).
    func canSnapshot(type: typeinfo)->bool
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

        if item.type == Core.String
        {
            .isString = true
            .strings.reserve(.n)
            for k in .n do
                .strings.add(dref cast(*String) prop.instanceAddr(item, k))
        }
        else
        {
            .sz = item.type.sizeof
            if .sz == 0 do
                return
            .bytes.resize(.n * .sz)
            for k in .n do
                Memory.copy(cast([*] void) (.bytes.buffer + k * .sz), cast(const [*] void) prop.instanceAddr(item, k), .sz)
        }

        .valid = true
    }

    // Write the captured value back into every edited instance (up to the number of instances
    // currently bound, in case the selection shrank).
    mtd restore(prop: *Properties, item: *PropertiesItem)
    {
        if !.valid do
            return

        let cnt = Math.min(.n, prop.instanceCount(item))
        if .isString
        {
            for k in cnt do
                dref cast(*String) prop.instanceAddr(item, k) = .strings[k]
        }
        else
        {
            for k in cnt do
                Memory.copy(cast([*] void) prop.instanceAddr(item, k), cast(const [*] void) (.bytes.buffer + k * .sz), .sz)
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
            for k in .n
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
        for i in .bytes.count
        {
            if .bytes[i] != o.bytes[i] do
                return false
        }
        return true
    }
}

// One undoable property edit: restore the old/new value of 'item' in 'prop'.
struct PropUndoCommand
{
    prop:       *Properties
    item:       *PropertiesItem
    oldVal:     PropFieldValue
    newVal:     PropFieldValue
}

impl IUndoCommand for PropUndoCommand
{
    mtd impl redo()
    {
        .prop.applyUndoValue(.item, &.newVal)
    }

    mtd impl undo()
    {
        .prop.applyUndoValue(.item, &.oldVal)
    }
}

internal impl Properties
{
    // Capture the undo snapshot of every row created since 'fromIdx' (called at build time,
    // after the instance addresses are assigned).
    mtd assignUndoSnapshots(fromIdx: u64)
    {
        for i in fromIdx until .items.count do
            .items[i].undoValue.capture(me, .items[i])
    }

    // Diff the row's current value against its snapshot; on a real change, push one undo
    // command holding the before/after value, then resync the snapshot. Called from hasChanged.
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
            let cmd = Memory.new'PropUndoCommand()
            cmd.prop   = me
            cmd.item   = item
            cmd.oldVal = item.undoValue
            cmd.newVal = cur
            .undoMgr.pushCmd(cast(IUndoCommand) cmd, 0, false)
        }

        item.undoValue = cur
    }

    // Restore a recorded value into the row and refresh the grid, without re-recording it.
    mtd applyUndoValue(item: *PropertiesItem, val: *PropFieldValue)
    {
        .applyingUndo = true
        val.restore(me, item)
        item.undoValue = dref val    // keep the snapshot in sync with the timeline position
        .postChange(item)
        .applyingUndo = false
        .invalidate()
    }
}

// Public undo/redo entry points for hosts (menus, toolbars, shortcuts).
public impl Properties
{
    mtd canUndo()->bool
    {
        return .undoMgr.canUndo()
    }

    mtd canRedo()->bool
    {
        return .undoMgr.canRedo()
    }

    mtd undo()
    {
        .undoMgr.undo()
    }

    mtd redo()
    {
        .undoMgr.redo()
    }

    // Drop the whole undo history (e.g. after loading a fresh object into the grid).
    mtd clearUndo()
    {
        .undoMgr.clear()
        foreach it in .items do
            it.undoValue.capture(me, it)
    }

    // Turn recording on/off (e.g. to batch programmatic changes without polluting the history).
    mtd setUndoEnabled(on: bool)
    {
        .undoEnabled = on
    }
}
