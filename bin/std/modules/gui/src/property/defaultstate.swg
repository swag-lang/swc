using Core, Pixel

// "Reset to default" feature of the property grid, modeled on the inspectors of Unity/Godot/
// Unreal: a field that no longer holds the value declared in its struct is flagged as "modified"
// and shows a revert button that restores it (also available as a "Reset to default" context menu
// action).
//
// The default value a field is compared against is a real, default-constructed instance of the
// edited struct (one per addStruct, owned by the grid, see Properties.defaultRoots). Every row's
// `defaultData` points into it at the field's fixed offset, exactly like `dataInstances` points
// into the edited instances — so the comparison naturally covers scalars, enums, nested structs,
// static arrays, colors and vectors. Rows with no comparable default (under a dynamic array, or a
// non-POD aggregate) keep `defaultData == null` and never show the marker.
//
// The test is customizable: IPropertyNotify.isItemAtDefault can force the answer when a plain
// value comparison is not what the user wants, and IPropertyNotify.resetItemToDefault can take
// over the reset itself.

// Result of IPropertyNotify.isItemAtDefault. Auto lets the grid run its built-in comparison.
public enum PropDefaultState
{
    Auto
    AtDefault
    Modified
}

// One default-constructed instance backing a struct added to the grid (owned; freed on destroy).
public struct PropDefaultRoot
{
    base:   *u8
    type:   typeinfo
}

// Size of the revert arrow icon inside its (square, editBox-height) button, and the gap kept on
// each side of the button so it reads as an airy action, not packed against the editor.
const PropRevertIconSize = 18'f32
const PropRevertGap      = 4'f32

impl Properties
{
    // Build the default-constructed instance for the struct whose rows start at 'fromIdx', and
    // point every such row's defaultData into it. Called right after assignInstances, so it uses
    // the same fixed-offset trick: a field at offset O from the struct base sits at defBase + O.
    mtd assignDefaults(fromIdx: u64, rootType: typeinfo, base0: [*] u8)
    {
        if !rootType or rootType.kind != Swag.TypeInfoKind.Struct do
            return

        // A pristine instance with every field at its declared default value.
        let def = Memory.new(rootType)
        .defaultRoots.add({def, rootType})

        let defBase  = cast([*] u8) def
        let rootSize = cast(u64) rootType.sizeof

        for i in fromIdx until .items.count
        {
            let it = .items[i]
            it.defaultData = null

            if !it.data do
                continue

            // Items under a dynamic array live in a heap buffer, not at a fixed offset from the
            // struct base — no meaningful declared default to compare against.
            if .isUnderDynamicArray(it) do
                continue

            if !canHaveDefault(it.type) do
                continue

            let off = cast([*] u8) it.data - base0
            if off < 0 or cast(u64) off >= rootSize do
                continue

            it.defaultData = cast(*u8) (defBase + off)
        }
    }

    // Drop + free the owned default instances (from onDestroyEvent).
    mtd freeDefaultRoots()
    {
        foreach r in .defaultRoots do
            Memory.delete(r.base, r.type)
        .defaultRoots.clear()
    }

    // True when the field can be reset to a declared default: the feature is on, the row has a
    // comparable default, is not read-only, and its type is one the grid can copy back safely.
    mtd canReset(item: *PropertiesItem)->bool
    {
        if !.showReverts or !item.defaultData or !item.data or !item.type do
            return false
        if .isItemReadOnly(item) do
            return false
        return canHaveDefault(item.type)
    }

    // Whether the field currently differs from its declared default (drives the marker/revert).
    // IPropertyNotify.isItemAtDefault (first non-Auto along the parent chain) overrides the
    // built-in per-instance comparison.
    mtd computeItemModified(item: *PropertiesItem)->bool
    {
        if !.canReset(item) do
            return false

        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if scan.ntfyItf
            {
                let st = scan.ntfyItf.isItemAtDefault(me, item)
                if st != .Auto do
                    return st == .Modified
            }
            scan = scan.parent
        }

        // Built-in: modified when any edited instance differs from the default.
        let n = .instanceCount(item)

        if item.type == Core.String
        {
            let d = cast(*String) item.defaultData
            for k in n
            {
                if dref cast(*String) .instanceAddr(item, k) != dref d do
                    return true
            }
            return false
        }

        let sz = .fieldSize(item)
        if sz == 0 do
            return false

        for k in n
        {
            if Memory.compare(cast(const [*] void) .instanceAddr(item, k), cast(const [*] void) item.defaultData, sz) != 0 do
                return true
        }
        return false
    }

    // Reset 'item' to its default value. IPropertyNotify.resetItemToDefault (along the parent
    // chain) may take over; otherwise the declared default is written into every edited instance.
    mtd resetItemDefault(item: *PropertiesItem)
    {
        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if scan.ntfyItf and scan.ntfyItf.resetItemToDefault(me, item)
            {
                .refreshItem(item)
                .hasChanged(item)
                return
            }
            scan = scan.parent
        }

        if !.canReset(item) do
            return

        // Write the default into every instance ourselves (composite editors set selfPropagate,
        // so hasChanged would not propagate a whole-field write for us).
        let n = .instanceCount(item)
        if item.type == Core.String
        {
            for k in n do
                dref cast(*String) .instanceAddr(item, k) = dref cast(*String) item.defaultData
        }
        else
        {
            let sz = .fieldSize(item)
            for k in n do
                Memory.copy(cast([*] void) .instanceAddr(item, k), cast(const [*] void) item.defaultData, sz)
        }

        .refreshItem(item)
        .hasChanged(item)
    }

    // Recompute every row's modified state and sync its revert button. Returns true when a
    // button appeared/disappeared, so the caller re-runs the layout.
    #[Swag.Discardable]
    mtd updateDefaults()->bool
    {
        var changed = false
        foreach it in .items
        {
            if .updateItemDefaultState(it) do
                changed = true
        }
        return changed
    }
}

impl Properties
{
    // Types the grid knows how to compare and copy back for the default feature: dynamic strings
    // (compared/assigned by content) and any POD value (native, enum, bool, color, vector, a POD
    // struct, a static array of POD). Non-POD aggregates (dynamic arrays, structs owning heap
    // buffers) are left out — a raw byte copy would corrupt them.
    func canHaveDefault(type: typeinfo)->bool
    {
        if !type do
            return false
        if type == Core.String do
            return true
        return Reflection.isPod(type)
    }

    // Update one row: refresh its cached modified state and sync its revert arrow.
    //  - Grid (like the Godot/Unreal inspectors): the arrow lives in a revert column docked to the
    //    right of the row, reserved on EVERY resettable row so the value editor never resizes when
    //    the arrow toggles. Toggling only swaps the icon in/out, so it needs no relayout.
    //  - List: the row is a vertical stack, so the arrow is shown/hidden on the name label instead
    //    (the stacked editor below is unaffected either way).
    // Returns true only when a list row's arrow visibility changed (grid never triggers relayout).
    mtd updateItemDefaultState(item: *PropertiesItem)->bool
    {
        item.isModified = .computeItemModified(item)
        let grid = .isGridLike()

        if grid
        {
            if .canReset(item) do
                .ensureRevertButton(item)
            if !item.revertButton do
                return false

            let btn = item.revertButton
            if item.isModified
            {
                if !btn.icon.isValid() do
                    btn.icon = .getTheme().getIcon24(.Undo, 16)
                btn.enable(true)
            }
            else
            {
                btn.icon.clear()             // hide the arrow; the docked button still holds the column
                btn.enable(false)
            }
            btn.invalidate()
            return false
        }

        if item.isModified do
            .ensureRevertButton(item)
        if !item.revertButton do
            return false
        if item.revertButton.isVisible() == item.isModified do
            return false
        item.revertButton.show(item.isModified)
        return true
    }

    // Create the revert arrow in the row's trailing action margin — a square Overlay icon button
    // (translucent hover, no opaque box that would clash with a pastel/selected row). Grid docks it
    // to the right of the row and starts it hidden-but-present (empty icon + disabled) so the
    // reserved column keeps the editor from resizing when the arrow toggles; list positions it by
    // hand at the right of the edit column (positionListRevert) and starts it hidden.
    mtd ensureRevertButton(item: *PropertiesItem)
    {
        if item.revertButton do
            return

        let host = .rowActionArea(item)
        if !host do
            return

        let grid = .isGridLike()
        let h    = .getThemeMetrics().editBox_Height
        let prop = me
        with item.revertButton = IconButton.create(host, .getTheme().getIcon24(.Undo, PropRevertIconSize), {0, 0, h, h})
        {
            .setForm(.Round)
            .iconBtnFlags.add(.Overlay)      // elegant translucent hover, no opaque box
            .maxSize       = {h, h}          // square: symmetric horizontally and vertically
            .minSize       = {h, h}
            .focusStrategy = .None           // stays out of the keyboard nav order

            if grid
            {
                .dockStyle = .Right
                .margin.x  = PropRevertGap   // breathing room from the editor / previous action
                .margin.z  = PropRevertGap
            }
            else do
                .dockStyle = .None           // placed by positionListRevert, at the edit column

            .sigPressed += func|prop, item|(b)
            {
                prop.resetItemDefault(item)
            }
        }

        if grid
        {
            item.revertButton.icon.clear()   // reserved column, arrow hidden until modified
            item.revertButton.enable(false)
        }
        else
        {
            // The arrow is a child of the name label; let it paint beyond the label's short
            // single-line bounds so it is never clipped (it is sized + centered on the title line
            // by positionListRevert).
            item.label.wndFlags.remove(.ClipChildren)
            item.revertButton.show(false)
        }
    }

    // List mode: line the revert arrow up with the right edge of the edit column (the value
    // widgets) and center it on the name's title line, instead of leaving it stranded at the far
    // right of the full-width row. Called from the resize loop once the value widgets are
    // positioned. The button is a child of the name label, so its geometry is in the label's local
    // space; it is sized to the title line height so a big square does not overrun the row below.
    mtd positionListRevert(item: *PropertiesItem)
    {
        let btn = item.revertButton
        if .isGridLike() or !btn or !item.label do
            return

        // Fit the arrow to the title line (a single-line name is shorter than the grid button).
        let sz = Math.min(item.label.position.height, me.getThemeMetrics().editBox_Height)
        btn.position.width  = sz
        btn.position.height = sz
        btn.maxSize         = {sz, sz}
        btn.minSize         = {sz, sz}
        btn.icon.sizeX      = Math.max(sz - 4, 8.0)
        btn.icon.sizeY      = btn.icon.sizeX

        let span = .valueWidgetsSpan(item)             // [left, right] in line space
        let lx   = item.label.position.x               // label origin in line space
        btn.position.x = Math.round(span.right - lx - sz)
        btn.position.y = Math.round((item.label.position.height - sz) * 0.5)
    }
}
