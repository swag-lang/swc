#global public
using Core, Pixel

// The property control. This file holds the Properties struct and its lifecycle/state API. Its
// pure theme-split extensions (only `impl Properties`, no new type) use the dotted form
// `properties.<subpart>.swg`, the same way the compiler names `Pass.<subpart>.cpp`:
//   properties.build       — reflection -> rows (addItem/addValue/addStructInternal)
//   properties.layout      — grid/condensed modes + resizable label column
//   properties.paint       — row background/border/separator/disclosure rendering
//   properties.input       — hit-testing, mouse hook, per-row events
//   properties.menu        — the right-click context menu
//   properties.attributes / properties.keyboard / properties.multi
// Files that declare their own type keep a concatenated name after that type: propertiesitem
// (PropertiesItem), actionproperties (ActionProperties), propertiesctrl, propertiesview,
// propertieseditors (IPropertyEditor), validation (PropValidation), + values/.

// To notify a struct about properties changes
#[Swag.Warning("Wrn0006", .Disable)]
interface IPropertyNotify
{
    mtd itemHasChanged(list: *Properties, item: *PropertiesItem) {}
    mtd isItemVisible(list: *Properties, item: *PropertiesItem)->bool { return true; }
    mtd isItemEnabled(list: *Properties, item: *PropertiesItem)->bool { return true; }

    // Return true to make 'item' read-only at runtime: shown but not editable, and "Paste" is
    // disabled. Unlike isItemEnabled (which grays the whole row), this only locks the editor.
    // The static equivalent is the Properties.ReadOnly attribute. Checked along the parent chain.
    mtd isItemReadOnly(list: *Properties, item: *PropertiesItem)->bool { return false; }

    // Called when the user right-clicks a row: add custom menu items (each with a unique
    // command id) before the built-in ones (Copy/Paste/...). Use a separator to set them apart.
    mtd fillPopupMenu(list: *Properties, item: *PropertiesItem, menu: *MenuCtrl) {}

    // Called with the command id chosen in the popup menu when it is not one of the built-in
    // actions. Return true once handled. This is how custom fillPopupMenu items are executed.
    mtd onPopupCommand(list: *Properties, item: *PropertiesItem, cmdId: string)->bool { return false; }

    // Return a validation state + message for 'item'. Called on build and after every
    // change; the row shows an accent bar + badge in the state color and the message as a
    // tooltip. The most severe result along the item's parent chain wins.
    mtd validateItem(list: *Properties, item: *PropertiesItem)->PropValidationResult { return {}; }

    // Customize the "is this field still at its default value?" test, used to decide whether the
    // row shows the revert marker. Return .Auto (the default) to let the grid compare the current
    // value against the value the field is initialized to in the struct declaration; return
    // .AtDefault / .Modified to force the answer when the test is more involved than a plain
    // comparison. The first non-Auto result along the item's parent chain wins.
    mtd isItemAtDefault(list: *Properties, item: *PropertiesItem)->PropDefaultState { return .Auto; }

    // Reset 'item' to its default value yourself; return true once handled. Return false (the
    // default) to let the grid restore the value declared in the struct. Called by the "Reset to
    // default" action and the revert marker. Checked along the item's parent chain.
    mtd resetItemToDefault(list: *Properties, item: *PropertiesItem)->bool { return false; }
}

enum PropertiesKind
{
    List       // This is a flat list
    Grid       // This is a more compact property grid
    Condensed  // A dense, classic property grid: thin rows, compact controls
}

// Height of the inner value editors in condensed mode, so they fit the thin rows.
const PropCondensedControlHeight = 20'f32

struct Properties
{
    using frameWnd:     FrameWnd

    kind                = PropertiesKind.List

    sizeEditValue:      s32 = 200

    // For grid kind
    gridLineHeight:       f32 = 35
    gridLineMargin:       s32 = 12
    gridColumnSize:       s32 = 150
    gridColumnSizeReq:    s32 = 150   // Requested column size, re-clamped to the current width on resize
    gridMarginColumn:     s32 = 16

    // For list kind
    listNameMarginBefore:     s32 = 20
    listNameMarginAfter:      s32 = 0
    listDescMarginAfter:      s32 = 5

    // Inline validation message bar (info/warning/error)
    valBarGlyphWidth:         f32 = 32   // left room reserved for the severity icon
    valBarIconSize:           f32 = 18   // size of the severity icon
    valBarPaddingX:           f32 = 12   // horizontal text inset from the colored background
    valBarPaddingY:           f32 = 7    // vertical breathing room added around the text
    valBarGap:                f32 = 7    // gap between the row editor and the bar
    valBarRadius:             f32 = 6    // corner radius of the colored background

    sigChanged:               SigArray'func||(*Properties, *PropertiesItem)

    leftMargin:               s32 = 15
    rightMargin:              s32 = 15
    fontSection:              FontFamily
    fontCategory:             FontFamily
    fontName:                 FontFamily
    scrollWnd:                *ScrollWnd
    edView:                   *PropertiesView
    items:                    ArrayPtr'PropertiesItem
    sections:                 Array'{ item: *PropertiesItem, lvl: s32 }
    hotItem:                  *PropertiesItem
    selItem:                  *PropertiesItem
    currentSectionIndex:      u32 = Swag.U32.Max
    stringFilter:             String
    cursorSet:                bool
    resizingColumn:           bool
    aniBar:                   BlendColor
    editPopup:                *Wnd

    // "Reset to default" feature (defaultstate.swg). defaultRoots owns one default-constructed
    // instance per added struct, freed on destroy; every row's defaultData points into it.
    // showReverts is the master switch for the revert markers.
    defaultRoots:             Array'PropDefaultRoot
    showReverts:              bool = true

    // Row the context menu currently operates on. Read by the ActionProperties commands (and
    // any keyboard/toolbar trigger of the same commands); kept set across the async command
    // dispatch that follows doModal.
    menuItem:                 #null *PropertiesItem

    // Undo/redo (propertiesundo.swg). Every field edit that goes through hasChanged records one
    // command into undoMgr (unless undoEnabled is off). applyingUndo guards against re-recording
    // while a command is restoring a value.
    undoMgr:                  UndoManager
    undoEnabled:              bool = true
    applyingUndo:             bool
}

// The control's own IWnd events. Swag does not allow a split interface impl, so both entry points
// live here; the heavy logic they reach into is in the concern files (paintBackItem in
// properties.paint, the notify dispatch below refreshes via refreshItem).
impl IWnd for Properties
{
    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        let colorBar = .cursorSet ? .getThemeColors().splitView_BarHot : .getThemeColors().prop_GridColumn
        .aniBar.apply(me, colorBar)
    }

    // Free the default-constructed instances backing the "reset to default" feature. They are
    // heap-allocated per added struct (assignDefaults), so their drop+free is not covered by the
    // struct's automatic field drop.
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .freeDefaultRoots()
    }

    // The validation bar's icon + colors are manually-set Label fields (not theme styles), so they
    // do not follow a theme switch on their own. Re-apply them from the current theme here (exactly
    // like EmbInfoCtrl re-runs setColors on ThemeChanged) — otherwise a bar built under one theme
    // keeps stale colors under the next (e.g. dark-theme light text nearly invisible on the light
    // pastel background).
    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        foreach it in .items
        {
            if it.validationLabel and it.validation != .None do
                .applyValidationVisual(it)
        }
    }

    // Built-in commands are handled by ActionProperties (registered in create). A command id
    // that no action claims comes from a custom fillPopupMenu item: dispatch it to the notify
    // interface(s) along the clicked row's parent chain, then refresh — the same contract the
    // old inline `default:` switch case had.
    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        evt.accepted = false

        let item = .menuItem
        if !item do
            return

        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if scan.ntfyItf and scan.ntfyItf.onPopupCommand(me, item, evt.id)
            {
                .refreshItem(item)
                .hasChanged(item)
                evt.accepted = true
                return
            }
            scan = scan.parent
        }
    }
}

// Internal helpers shared across the control's files. Moduleprivate so the sibling concern files
// (and the value editors) can call them, but not part of the public API.
moduleprivate impl Properties
{
    mtd getItemState(item: *PropertiesItem)->{ visible, enable: bool }
    {
        var result: retval{true, true}
        var scan    = item

        while scan
        {
            if scan.ntfyItf
            {
                if !scan.ntfyItf.isItemVisible(me, item) do
                    result.visible = false
                if !scan.ntfyItf.isItemEnabled(me, item) do
                    result.enable = false
            }

            if !result.visible and !result.enable do
                return result

            scan = scan.parent

            if scan and .isGridLike() and scan.numChilds and !scan.flags.has(.Expanded) do
                result.visible = false
        }

        return result
    }

    mtd refreshItem(item: *PropertiesItem)
    {
        if !item.sigRefresh.isEmpty()
        {
            item.sigRefresh.call(item)
            return
        }

        let pointed = item.type orelse item.typeValue.pointedType
        if pointed
        {
            if Reflection.isEnum(pointed) and Reflection.hasAttribute(pointed, Swag.EnumFlags) do
                .refreshEnumFlags(item)
            elif Reflection.isEnum(pointed) do
                .refreshEnum(item)
            elif Reflection.isBool(pointed) do
                .refreshBool(item)
            elif Reflection.isInteger(pointed) or Reflection.isFloat(pointed) do
                .refreshNative(item)
            elif Reflection.isString(pointed) and item.editBox
            {
                item.editBox.setText(dref cast(*string) item.data)
                .setEditMixed(item, item.editBox)
            }
            elif pointed == Core.String and item.editBox
            {
                item.editBox.setText(dref cast(*String) item.data)
                .setEditMixed(item, item.editBox)
            }
            elif Reflection.isStruct(pointed)
            {
                let typeStruct = cast(const *Swag.TypeInfoStruct) pointed
                if typeStruct.fromGeneric == Array do
                    .refreshArray(item)
            }
        }
    }
}

impl Properties
{
    // Creates a new Properties instance
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, kind = PropertiesKind.List, id: WndId = null)->*Properties
    {
        let ed = Wnd.create'Properties(parent, "", position, id)

        with ed
        {
            .kind = kind

            .scrollWnd               = .createView'ScrollWnd()
            .scrollWnd.dockStyle     = .Center
            .scrollWnd.focusStrategy = .None
            .scrollWnd.padding       = 0
            .scrollWnd.scrollWndFlags |= .TransparentBar

            .edView            = .scrollWnd.createView'PropertiesView()
            .edView.ed         = ed
            .edView.layoutKind = .Top
            .edView.spacing    = 0
            .edView.wndFlags |= .NoScroll

            let theme = parent.getTheme()

            if kind == .List
            {
                const FontSectionSize  = 30'u32
                const FontCategorySize = 24'u32
                .fontName             = theme.res.fontDefault
                .fontSection          = theme.createDefaultFontfamily(FontSectionSize)
                .fontCategory         = theme.createDefaultFontfamily(FontCategorySize)
                .fontSection.regular  = .fontSection.bold
                .fontCategory.regular = .fontCategory.bold
                .fontName.regular     = .fontName.bold
                .leftMargin           = 15
                .rightMargin          = 15
            }
            else
            {
                .fontName             = theme.res.fontDefault
                .fontSection          = theme.res.fontDefault
                .fontCategory         = theme.res.fontDefault
                .fontSection.regular  = .fontSection.bold
                .fontCategory.regular = .fontCategory.bold
                .leftMargin           = 25
                .rightMargin          = 15
            }

            // Condensed: a dense, classic property grid with thin rows and tight
            // margins. Inherits the grid-family fonts/layout set just above.
            if kind == .Condensed
            {
                .gridLineHeight = 24
                .gridLineMargin = 4
                .leftMargin     = 18
            }

            .hookOnChildEvent = func(wnd, evt) { return onHookChildEvent(wnd, evt); }

            // Built-in context-menu commands (Copy/Paste/array ops) go through the shared gui
            // action system instead of a hardcoded id switch. See actionproperties.swg.
            .registerAction'ActionProperties()
        }

        return ed
    }

    // Add a new struct to display.
    mtd addStruct(val: any, section: string = null)
    {
        let typeof = @kindof(val)
        Debug.assert(typeof.kind == .Struct)

        var bases: Array'(*u8)
        bases.add(cast(*u8) @dataof(val))
        .addStructMulti(typeof, bases.toSlice(), section)
    }

    // Add several instances of the SAME struct type for multi-selection editing.
    // 'bases' holds the base address of each instance to edit together (>= 1). Editing
    // a field writes it into every instance; a field whose value differs across the
    // instances is shown as "mixed". With a single base this behaves like addStruct.
    mtd addStructMulti(typeof: typeinfo, bases: [..] *u8, section: string = null)
    {
        Debug.assert(typeof.kind == .Struct)
        Debug.assert(@countof(bases) >= 1)

        let firstItemIdx   = .items.count
        var item:          *PropertiesItem
        let numItemsBefore = .items.count

        // Section
        if section != null
        {
            let v: Swag.TypeValue{name: section}
            item = .addItem(v, null, null)
            item.flags.add(.Section | .NoSeparator | .Expanded | .NoFocus)
            item.label.style.setFont(&.fontSection)
            item.section = cast(u32) .sections.count
            .sections.add({item, 0})
        }

        // Creates an empty parent item
        else
        {
            let v: Swag.TypeValue
            item = .addItem(v, null, null, 0, .Zero)
            item.flags.add(.Section | .NoSeparator | .Expanded | .NoFocus)
        }

        let typeStruct = cast(const *Swag.TypeInfoStruct) typeof
        .addStructInternal(typeStruct, cast([*] u8) bases[0], item)

        item.numChilds = cast(u32) (.items.count - numItemsBefore)

        .assignInstances(firstItemIdx, bases)
        .assignDefaults(firstItemIdx, typeof, cast([*] u8) bases[0])
        .assignUndoSnapshots(firstItemIdx)

        // Editors were first filled from instance 0 before the instance addresses existed;
        // refresh so any field that differs across instances now shows as "mixed".
        if @countof(bases) > 1 do
            .refresh()

        .updateStates()
        .edView.sendResizeEvent()
    }

    // Fill in the per-instance field addresses of every item created since 'fromIdx'.
    // Each field sits at a fixed offset from its struct base, so its address in instance
    // k is `base[k] + (item.data - base[0])`. Items under a dynamic array keep a single
    // address (their element storage is not at a fixed struct offset).
    mtd assignInstances(fromIdx: u64, bases: [..] *u8)
    {
        if @countof(bases) <= 1 do
            return

        let base0 = cast([*] u8) bases[0]
        for i in fromIdx until .items.count
        {
            let it = .items[i]
            it.dataInstances.clear()
            if !it.data do
                continue

            if .isUnderDynamicArray(it)
            {
                it.dataInstances.add(it.data)
                continue
            }

            let off = cast([*] u8) it.data - base0
            foreach b in bases do
                it.dataInstances.add(cast(*u8) (cast([*] u8) b + off))
        }
    }

    // Refresh all displayed values.
    mtd refresh()
    {
        foreach it in .items do
            .refreshItem(it)
    }

    // To be called when a value has changed.
    mtd hasChanged(item: *PropertiesItem)
    {
        // Multi-selection: the editor wrote the new value into instance 0; mirror it into
        // the other edited instances so they all change together. Composite editors that
        // touch only part of the field (vector component, enum-flags bit) write every
        // instance themselves and opt out, so we don't overwrite the untouched parts.
        if !item.selfPropagate do
            .propagateField(item)

        // Record the edit for undo/redo (diff against the row's snapshot). Skipped while a
        // command is itself restoring a value (applyingUndo), so undo/redo don't re-record.
        if !.applyingUndo do
            .recordUndo(item)

        .postChange(item)
    }

    // The refresh/relayout/notify tail shared by a user edit (hasChanged) and by an undo/redo
    // restore (applyUndoValue) — everything except propagation and undo recording.
    mtd postChange(item: *PropertiesItem)
    {
        .refresh()

        // A change can add/remove a validation bar (row height) or flip a row's revert marker
        // (row layout): relay out the grid so the rows below shift and the scroll size stays
        // correct.
        var relayout = .updateValidation()
        if .updateDefaults() do
            relayout = true
        if relayout
        {
            .applyLayout()
            .scrollWnd.view.sendResizeEvent()
        }

        .sigChanged.call(me, item)

        // Notify all the hierarchy
        var scan = item
        while scan
        {
            if scan.ntfyItf do
                scan.ntfyItf.itemHasChanged(me, item)
            scan = scan.parent
        }

        if Reflection.hasAttribute(item.typeValue, .RecalcLayout) do
            .updateStates()
    }

    // Show hidden content depending on the input 'filter'.
    mtd setStringFilter(filter: string)
    {
        if .stringFilter == filter do
            return
        .stringFilter = filter
        .updateStates()
    }

    // Only display a given section.
    // If 'sectionIndex' is too big, all sections will be displayed.
    mtd setCurrentSection(sectionIndex: u32)
    {
        .currentSectionIndex = sectionIndex
        .updateStates()
    }

    // Returns true if the given item is read-only: a static string, a field tagged with the
    // ReadOnly attribute, or made read-only at runtime by a notify interface along the parent
    // chain. Read-only items are shown but cannot be edited or pasted into.
    mtd isItemReadOnly(item: *PropertiesItem)->bool
    {
        if !item.type do
            return false

        // Static strings are inherently read-only (shown with a read-only editor).
        if item.type == string do
            return true

        if Reflection.hasAttribute(item.typeValue, .ReadOnly) do
            return true

        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if scan.ntfyItf and scan.ntfyItf.isItemReadOnly(me, item) do
                return true
            scan = scan.parent
        }

        return false
    }

    // Returns true if the given item can be changed (edited / pasted into)
    mtd canChangeItem(item: *PropertiesItem)->bool
    {
        if !item.data or !item.type do
            return false

        if .isItemReadOnly(item) do
            return false

        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if scan.line and scan.line.isDisabled() do
                return false
            scan = scan.parent
        }

        return true
    }

    // Update the state of the given item
    mtd updateItemState(item: *PropertiesItem)
    {
        var mustShow   = false
        var mustEnable = false

        if item.section == .currentSectionIndex or .currentSectionIndex >= .sections.count
        {
            if .stringFilter.length == 0 do
                mustShow = true
            elif Utf8.indexOf(item.filter.toSlice(), .stringFilter, comparisonType: Utf8.ComparisonType.Latin1NoCase) != Swag.U64.Max do
                mustShow = true

            if mustShow do
                (mustShow, mustEnable) = .getItemState(item)
        }

        item.line.show(mustShow)
        item.line.enable(mustEnable)

        // Read-only items stay visible and selectable (so they can still be copied and the
        // context menu opened). An edit box becomes read-only — focusable but not editable,
        // exactly like a static string; any other editor (slider, combo, checkbox, ...) is
        // grayed instead, since those have no read-only mode.
        let readOnly = .isItemReadOnly(item)
        if item.editBox
        {
            if readOnly do
                item.editBox.editBoxFlags.add(.ReadOnly)
            else do
                item.editBox.editBoxFlags.remove(.ReadOnly)
        }

        foreach c in item.line.childs
        {
            if c == item.label or c == item.labelDesc or c == item.validationLabel do
                continue
            if item.editBox and c == cast(*Wnd) item.editBox do
                continue
            // The revert arrow manages its own enabled state (enabled only while modified), so it
            // must not be swept along with the row's read-only state here.
            if item.revertButton and c == cast(*Wnd) item.revertButton do
                continue
            c.enable(!readOnly)
        }

        // If an item is visible, then we show also all of its parents, in order
        // to put the item in context
        if mustShow
        {
            var scan = item.parent
            while scan and !scan.line.isVisible()
            {
                scan.line.show()

                (?, mustEnable) = .getItemState(scan)
                scan.line.enable(mustEnable)

                scan = scan.parent
            }
        }
    }

    // Update the show/hide state of all content
    mtd updateStates()
    {
        foreach it in .items do
            .updateItemState(it)
        .updateValidation()
        .updateDefaults()
        .applyLayout()
        .scrollWnd.view.sendResizeEvent()
    }
}
