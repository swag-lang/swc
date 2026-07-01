#global public
using Core, Pixel

// "Reset to default" feature of the property grid, modeled on the inspectors of Unity/Godot/
// Unreal: a field that no longer holds the value declared in its struct is flagged as "modified"
// (a left accent bar + a revert arrow), and the revert arrow — or the "Reset to default" context
// menu action — restores it.
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
enum PropDefaultState
{
    Auto
    AtDefault
    Modified
}

// One default-constructed instance backing a struct added to the grid (owned; freed on destroy).
struct PropDefaultRoot
{
    base:   *u8
    type:   typeinfo
}

moduleprivate impl Properties
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

    // Draw the "not at its default" accent bar on the far left of a modified grid row (the
    // at-a-glance override indicator, Unity-style). List mode relies on the revert arrow alone.
    mtd paintModifiedMark(painter: *Painter, item: *PropertiesItem, r: Math.Rectangle)
    {
        if !item.isModified or !.isGridLike() do
            return

        let bar = Math.Rectangle{r.x + 1, r.y + 3, 3, Math.max(r.height - 6, 1.0)}
        painter.fillRoundRect(bar, 1.5, 1.5, .getThemeColors().prop_ModifiedMark)
    }
}

fileprivate impl Properties
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

    // Lazily create the revert arrow for a row. Mirrors the array "+" button placement: docked to
    // the right of the row cell in grid mode, and to the right of the name label in list mode
    // (where the row is a vertical stack that ignores docking).
    mtd ensureRevertButton(item: *PropertiesItem)
    {
        if item.revertButton do
            return

        // Grid rows dock the arrow to the right of the cell; list rows are a vertical stack that
        // ignores docking, so (like the array "+" button) it goes to the right of the name label.
        if !.isGridLike() and !item.label do
            return
        let parentForBtn = .isGridLike() ? item.line : cast(*Wnd) item.label

        let h    = .getThemeMetrics().editBox_Height
        let prop = me

        with item.revertButton = IconButton.create(parentForBtn, .getTheme().getIcon24(.Undo, 16), {0, 0, 22, h})
        {
            .dockStyle    = .Right
            .maxSize.y    = h
            .margin.z     = 2
            .iconBtnFlags.add(.Flat)                       // no box: just the accent arrow
            .iconColor    = me.getThemeColors().prop_ModifiedMark
            .toolTip      = "Reset to default value"
            .focusStrategy = .None                          // stays out of the keyboard nav order
            .sigPressed += func|prop, item|(b)
            {
                prop.resetItemDefault(item)
            }
        }

        item.revertButton.show(false)
    }
}
