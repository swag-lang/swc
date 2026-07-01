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

    // Update one row: refresh its cached modified state and show/hide its revert button. Returns
    // true when the button's visibility changed.
    mtd updateItemDefaultState(item: *PropertiesItem)->bool
    {
        item.isModified = .computeItemModified(item)

        if item.isModified do
            .ensureRevertButton(item)

        if !item.revertButton do
            return false

        if item.revertButton.isVisible() == item.isModified do
            return false

        item.revertButton.show(item.isModified)
        return true
    }

    // Lazily create the revert button for a row — a normal hot-tracking icon button.
    //  - Grid: placed in the LEFT gutter (absolutely, not docked), so it never eats into the value
    //    editor's width (the editor keeps a constant size whether or not the row is modified).
    //  - List: docked to the right of the name label (the row is a vertical stack that ignores
    //    docking), like the array "+" button; the stacked editor below is untouched.
    mtd ensureRevertButton(item: *PropertiesItem)
    {
        if item.revertButton do
            return

        let grid = .isGridLike()
        if !grid and !item.label do
            return
        let parentForBtn = grid ? item.line : cast(*Wnd) item.label

        let h = .getThemeMetrics().editBox_Height
        with item.revertButton = IconButton.create(parentForBtn, .getTheme().getIcon24(.Undo, 16), {0, 0, 22, h})
        {
            .setForm(.Round)                 // a real button: hover/pressed tracking
            .toolTip       = "Reset to default value"
            .focusStrategy = .None           // stays out of the keyboard nav order

            if grid
            {
                // Sit in the left gutter, centered on the value cell. Absolute (dockStyle .None,
                // anchorStyle .None) so the row's arrange never repositions it or reserves room
                // for it in the editor column.
                let sz = Math.min(item.valueCellHeight - 4, 22.0)
                .dockStyle = .None
                .setPosition({2, (item.valueCellHeight - sz) * 0.5, sz, sz}, false)
            }
            else
            {
                .dockStyle = .Right
                .maxSize.y = h
                .margin.z  = 2
            }

            let prop = me
            .sigPressed += func|prop, item|(b)
            {
                prop.resetItemDefault(item)
            }
        }

        item.revertButton.show(false)
    }
}
