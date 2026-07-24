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
    base: #null *u8
    type: #null typeinfo
}

// Size of the revert arrow icon inside its (square, editBox-height) button, and the gap kept on
// each side of the button so it reads as an airy action, not packed against the editor.
const PropRevertIconSize = 18'f32
const PropRevertGap      = 4'f32

impl Properties
{
    mtd revertButtonSize()->f32
    {
        return .kind == .Condensed ? PropCondensedControlHeight : .getThemeMetrics().editBox_Height
    }

    mtd revertIconSize(buttonSize: f32)->f32
    {
        return Math.max(Math.min(PropRevertIconSize, buttonSize - 4), 8.0)
    }

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

        let defBase  = notnull cast(#null [*] u8) def
        let rootSize = cast(u64) rootType.sizeof

        for i in fromIdx until .items.count
        {
            let it = notnull .items[i]
            it.defaultData = null

            if !it.data do
                continue

            // Items under a dynamic array live in a heap buffer, not at a fixed offset from the
            // struct base — no meaningful declared default to compare against.
            if .isUnderDynamicArray(notnull it) do
                continue

            if !canHaveDefault(it.type) do
                continue

            let off = cast(#null [*] u8) it.data - base0
            if off < 0 or cast(u64) off >= rootSize do
                continue

            it.defaultData = cast(*u8) (defBase + off)
        }
    }

    // Drop + free the owned default instances (from onDestroyEvent).
    mtd freeDefaultRoots()
    {
        for r in .defaultRoots do
            Memory.delete(notnull r.base, notnull r.type)
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
            let d = notnull cast(#null *String) item.defaultData
            for k in n
            {
                if (dref notnull cast(#null *String) .instanceAddr(item, k)) != dref d do
                    return true
            }

            return false
        }

        let sz = .fieldSize(item)
        if sz == 0 do
            return false

        for k in n
        {
            if Memory.compare(cast(#null const [*] void) .instanceAddr(item, k), cast(#null const [*] void) item.defaultData, sz) != 0 do
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
                dref notnull cast(#null *String) .instanceAddr(item, k) = dref notnull cast(#null *String) item.defaultData
        }
        else
        {
            let sz = .fieldSize(item)
            for k in n do
                Memory.copy(cast(#null [*] void) .instanceAddr(item, k), cast(#null const [*] void) item.defaultData, sz)
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
        for it in .items
        {
            if .updateItemDefaultState(notnull it) do
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
    func canHaveDefault(type: #null typeinfo)->bool
    {
        if !type do
            return false
        if type == Core.String do
            return true
        return Reflection.isPod(type)
    }

    // Update one row: refresh its cached modified state and sync its marker.
    //  - Grid (like the Godot/Unreal inspectors): a revert arrow lives in a column docked to the
    //    right of the row, reserved on EVERY resettable row so the value editor never resizes when
    //    the arrow toggles. Toggling only swaps the icon in/out, so it needs no relayout.
    //  - List (like the VSCode settings page): a vertical accent bar along the row's left edge
    //    marks the modified field (painted by paintBackItem); the reset stays available through
    //    the context menu. No floating button, whose alignment reads oddly in full-width rows.
    // Never triggers a relayout (the marker has no layout footprint in either mode).
    mtd updateItemDefaultState(item: *PropertiesItem)->bool
    {
        let wasModified = item.isModified
        item.isModified = .computeItemModified(item)

        if !.isGridLike()
        {
            if item.isModified != wasModified do
                item.line.invalidate()
            return false
        }

        if .canReset(item) do
            .ensureRevertButton(item)
        if !@isset(item.revertButton) do
            return false

        let btn = item.revertButton
        if item.isModified
        {
            if !btn.icon.isValid() do
                btn.icon = .getTheme().getIcon24(.Undo, .revertIconSize(btn.position.height))
            btn.enable(true)
        }
        else
        {
            btn.icon.clear()     // hide the arrow; the docked button still holds the column
            btn.enable(false)
        }

        btn.invalidate()
        return false
    }

    // Create the revert arrow in the row's trailing action margin — a square Overlay icon button
    // (translucent hover, no opaque box that would clash with a pastel/selected row). Grid only:
    // docked to the right of the row and started hidden-but-present (empty icon + disabled) so
    // the reserved column keeps the editor from resizing when the arrow toggles. List rows use
    // the painted modified bar instead (see updateItemDefaultState).
    mtd ensureRevertButton(item: *PropertiesItem)
    {
        if @isset(item.revertButton) or !.isGridLike() do
            return

        let host = .rowActionArea(item)
        if !host do
            return

        let h = .revertButtonSize()
        with item.revertButton = IconButton.create(host, .getTheme().getIcon24(.Undo, .revertIconSize(h)), {0, 0, h, h})
        {
            .setForm(.Round)
            .iconBtnFlags.add(.Overlay)     // elegant translucent hover, no opaque box
            .maxSize       = {h, h}         // square: symmetric horizontally and vertically
            .minSize       = {h, h}
            .focusStrategy = .None     // stays out of the keyboard nav order
            .dockStyle     = .Right
            .margin.x      = PropRevertGap     // breathing room from the editor / previous action
            .margin.z      = PropRevertGap

            .sigPressed += func|prop = me, item|(b) { prop.resetItemDefault(item) }
        }

        item.revertButton.icon.clear()     // reserved column, arrow hidden until modified
        item.revertButton.enable(false)
    }
}
