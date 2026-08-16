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
interface IPropertyNotify
{
    // 'item' is null when the change is not tied to a live row anymore: an undo/redo restore
    // recorded against a previous grid content (the values are already back in the instances).
    mtd itemHasChanged(list: *Properties, item: #null *PropertiesItem) {}

    // Returns whether item visible.
    mtd isItemVisible(list: *Properties, item: *PropertiesItem)->bool
    {
        return true
    }

    // Returns whether item enabled.
    mtd isItemEnabled(list: *Properties, item: *PropertiesItem)->bool
    {
        return true
    }

    // Return false to hide one value of an enum field (a value that makes no sense for the
    // host, e.g. a 'None' entry): the combo omits it, an enum-flags block skips its row.
    // Like isItemVisible, checked on the host notify and along the item's parent chain, but
    // when the row is BUILT: rebuild the grid content to re-evaluate it.
    mtd isEnumValueVisible(list: *Properties, item: *PropertiesItem, enumValue: Swag.TypeValue)->bool
    {
        return true
    }

    // Return true to make 'item' read-only at runtime: shown but not editable, and "Paste" is
    // disabled. Unlike isItemEnabled (which grays the whole row), this only locks the editor.
    // The static equivalent is the Properties.ReadOnly attribute. Checked along the parent chain.
    mtd isItemReadOnly(list: *Properties, item: *PropertiesItem)->bool
    {
        return false
    }

    // Called when the user right-clicks a row: add custom menu items (each with a unique
    // command id) before the built-in ones (Copy/Paste/...). Use a separator to set them apart.
    mtd fillPopupMenu(list: *Properties, item: *PropertiesItem, menu: *MenuCtrl) {}

    // Called with the command id chosen in the popup menu when it is not one of the built-in
    // actions. Return true once handled. This is how custom fillPopupMenu items are executed.
    mtd onPopupCommand(list: *Properties, item: *PropertiesItem, cmdId: string)->bool
    {
        return false
    }

    // Return a validation state + message for 'item'. Called on build and after every
    // change; the row shows an accent bar + badge in the state color and the message as a
    // tooltip. The most severe result along the item's parent chain wins.
    mtd validateItem(list: *Properties, item: *PropertiesItem)->PropValidationResult
    {
        return {}
    }

    // Customize the "is this field still at its default value?" test, used to decide whether the
    // row shows the revert marker. Return .Auto (the default) to let the grid compare the current
    // value against the value the field is initialized to in the struct declaration; return
    // .AtDefault / .Modified to force the answer when the test is more involved than a plain
    // comparison. The first non-Auto result along the item's parent chain wins.
    mtd isItemAtDefault(list: *Properties, item: *PropertiesItem)->PropDefaultState
    {
        return .Auto
    }

    // Reset 'item' to its default value yourself; return true once handled. Return false (the
    // default) to let the grid restore the value declared in the struct. Called by the "Reset to
    // default" action and the revert marker. Checked along the item's parent chain.
    mtd resetItemToDefault(list: *Properties, item: *PropertiesItem)->bool
    {
        return false
    }
}

// Selects the layout density and presentation of a property editor.
enum PropertiesKind
{
    List          // Uses vertically stacked names, descriptions, and editors.
    Grid          // Uses separate name and value columns.
    Condensed     // Uses a compact classic grid with thin rows and controls.
    Panel         // Uses full-width self-labelled controls and separator categories.
}

// Height of the inner value editors in condensed mode, so they fit the thin rows.
internal const PropCondensedControlHeight = 20'f32

// Builds and edits reflected structure fields with validation, filtering, defaults, and undo support.
struct Properties
{
    public
    {
        using frameWnd: FrameWnd     // Embedded frame wnd state.

        // Construction options are read-only to callers. Use the setters below when a value has to
        // change so cached layout state remains synchronized.
        readonly
        {
            kind             = PropertiesKind.List     // Presentation selected at creation.
            editorWidth: s32 = 200                     // Preferred maximum width of value editors.

            // Affects rows added after the option changes.
            usingFieldsLast: bool

            // Whether modified fields expose the reset-to-default affordance.
            revertButtonsVisible: bool = true

            // Whether the view is restricted to fields that differ from their defaults.
            modifiedOnly: bool
        }

        // Theme-derived implementation metrics. They remain private to the control so callers do not
        // have to coordinate dependent geometry manually.
        internal
        {
            // Grid and condensed presentation metrics.
            gridLineHeight:    f32 = 32
            gridLineMargin:    s32 = 4
            gridColumnSize:    s32 = 150
            gridColumnSizeReq: s32 = 150     // Requested width, re-clamped on resize.
            gridMarginColumn:  s32 = 16
            gridIndentSize:    s32 = 14

            // List and panel presentation metrics.
            listNameMarginBefore: s32 = 12
            listNameMarginAfter:  s32 = 0
            listDescMarginAfter:  s32 = 5

            // Inline validation message-bar metrics.
            valBarGlyphWidth: f32 = 32
            valBarIconSize:   f32 = 18
            valBarPaddingX:   f32 = 12
            valBarPaddingY:   f32 = 7
            valBarGap:        f32 = 7
            valBarRadius:     f32

            leftMargin:  s32 = 15
            rightMargin: s32 = 15

            fontSection:  FontFamily
            fontCategory: FontFamily
            fontName:     FontFamily
        }

        sigValueChanged: SigArray'func||(*Properties, #null *PropertiesItem)     // Emitted after an edited value changes; item is null for detached undo/redo.

        // What the grid currently shows. Rows are produced by 'addStruct' and friends and the
        // selection moves with the keyboard and the mouse; a host reads both to follow the grid.
        readonly
        {
            items:   ArrayPtr'PropertiesItem     // Rows of the grid, in display order.
            selItem: #null *PropertiesItem       // Selected row, or 'null'.
        }

        // Scrolling viewport of the grid, established when it is created. A host configures the
        // scrollbars or scrolls the grid through it; the grid decides which window it is.
        #[Swag.Late]
        readonly
        scrollWnd: *ScrollWnd

        // View the rows are painted in, established when the grid is created.
        #[Swag.Late]
        internal
        edView: *PropertiesView

        // Grid state rebuilt from the rows: section index, hover and selection, and the transient
        // state of one gesture. The grid maintains all of it.
        internal
        {
            sections: Array'{ item: #null *PropertiesItem, lvl: s32 }     // Section rows and their depth.

            // Per data-column depth: does any row at that depth show a disclosure triangle? Drives the
            // reclaimed triangle gutter for all-leaf depths (see computeLevelMarks / itemLabelGutter).
            gridLevelHasMark:    Array'bool                // Whether any row at that depth shows a triangle.
            hotItem:             #null *PropertiesItem     // Row under the mouse.
            currentSectionIndex: u32 = Swag.U32.Max        // Section the viewport is scrolled to.
            stringFilter:        String                    // Active row filter.
            cursorSet:           bool                      // Whether the grid set the cursor this frame.
            resizingColumn:      bool                      // Whether a column-resize drag is in progress.
            aniBar:              BlendColor                // Animation of the live column-resize rule.
            editPopup:           #null *Wnd                // Popup owned by the row being edited.

            // "Reset to default" feature (defaultstate.swg). defaultRoots owns one default-constructed
            // instance per added struct, freed on destroy; every row's defaultData points into it.
            defaultRoots: Array'PropDefaultRoot     // One default-constructed instance per added struct.
        }

        // Row the context menu currently operates on. Read by the ActionProperties commands (and
        // any keyboard/toolbar trigger of the same commands); kept set across the async command
        // dispatch that follows doModal.
        internal
        menuItem: #null *PropertiesItem

        // Undo/redo (propertiesundo.swg). Every field edit committed through commitItemChange records
        // command into undoMgr (unless undoEnabled is off). applyingUndo guards against re-recording
        // while a command is restoring a value. externUndoMgr, when set, receives the commands
        // instead, so the grid shares the host's undo timeline. dragItem/dragCmd coalesce the moves
        // of one slider drag into a single command. generation stamps the grid content: it bumps on
        // clear so commands recorded against dropped rows skip their row refresh.
        internal
        externUndoMgr: #null *UndoManager     // Undo timeline of the host, when it shares one.
        internal
        undoEnabled:   bool = true     // Whether edits record undo commands.

        // Recording state of the undo timeline the grid owns.
        internal
        {
            undoMgr:      UndoManager                // Commands recorded by this grid.
            applyingUndo: bool                       // Whether a command is restoring a value right now.
            generation:   u64                        // Content stamp, bumped by 'clear'.
            dragItem:     #null *PropertiesItem      // Row of the slider drag being coalesced.
            dragCmd:      #null *PropUndoCommand     // Command the drag accumulates into.
        }

        // Host-level notify interface (setNotify): consulted for every row, in addition to the
        // per-struct IPropertyNotify implementations bound at build time. This is how a host that
        // does not own the displayed structs (an editor panel showing a document's objects) plugs
        // dynamic visibility, validation and change reactions.
        internal
        hostNtfy: #null IPropertyNotify

        // Build-time state of the opt-in mode (addStructMulti 'onlyNamed'): only fields carrying an
        // explicit Properties.Name attribute get a row.
        internal
        buildOnlyNamed: bool
    }
}

// The control's own IWnd events. Swag does not allow a split interface impl, so both entry points
// live here; the heavy logic they reach into is in the concern files (paintBackItem in
// properties.paint, the notify dispatch below refreshes via refreshItem).
impl IWnd for Properties
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let colorBar = .cursorSet ? .themeColors().splitView_BarHot : .themeColors().prop_GridColumn
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
    // like InfoBar reapplies colors on ThemeChanged) — otherwise a bar built under one theme
    // keeps stale colors under the next (e.g. dark-theme light text nearly invisible on the light
    // pastel background).
    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        for itIt in .items
        {
            let it = itIt!
            if @isset(it.validationLabel) and it.validation != .None do
                .applyValidationVisual(it)
            if it.flags.has(.Note) do
                .applyNoteVisual(it)
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
            if scan.ntfyItf and scan.ntfyItf.onPopupCommand(me, item!, evt.id!)
            {
                .refreshItem(item)
                .commitItemChange(item)
                evt.accepted = true
                return
            }

            scan = scan.parent
        }
    }
}

// Internal helpers shared across the control's files. Sibling concern files and
// value editors can call them, but they are not part of the public API.
internal impl Properties
{
    mtd hasActiveFilter()->bool
    {
        return .modifiedOnly or !.stringFilter.isEmpty()
    }

    mtd itemState(item: *PropertiesItem)->{ visible, enable: bool }
    {
        var result: retval = {true, true}

        if .hostNtfy
        {
            if !.hostNtfy.isItemVisible(me, item) do
                result.visible = false
            if !.hostNtfy.isItemEnabled(me, item) do
                result.enable = false
        }

        var scan = cast(#null *PropertiesItem) item
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

            // A filter is a request to find a field, so a collapsed ancestor must not hide a
            // match. Keep its expansion bit untouched and reveal the matching branch only for
            // as long as the filter is active.
            if scan and .isGridLike() and !.hasActiveFilter() and scan.numChilds and !scan.flags.has(.Expanded) do
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
            elif Reflection.isString(pointed) and @isset(item.editBox)
            {
                item.editBox.setText(item.data![as string])
                .setEditMixed(item, item.editBox)
            }
            elif pointed == Core.String and @isset(item.editBox)
            {
                item.editBox.setText(item.data![as String])
                .setEditMixed(item, item.editBox)
            }
            elif pointed == Core.String and @isset(item.comboBox) do
                .refreshFontName(item)
            elif Reflection.isStruct(pointed)
            {
                let typeStruct = cast(#null const *Swag.TypeInfoStruct) pointed
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
    func create(parent: *Wnd, position: Math.Rectangle = {}, kind = PropertiesKind.List, id: #null WndId = null)->*Properties
    {
        Debug.assert(parent)
        let ed = Wnd.create'Properties(parent, "", position, id)

        with ed
        {
            .kind = kind

            // The grid is one stop of the keyboard traversal. Its rows and their editors are
            // parts of it, not controls of the surface, and it moves between them itself: see
            // the navigation and edition modes of properties.keyboard.swg.
            .focusPolicy         = .Tab
            .wndFlags            |= .NoFocusRing
            .scrollWnd           = .createView'ScrollWnd()
            .scrollWnd.dockStyle = .Center
            .scrollWnd.padding   = 0
            .scrollWnd.updateFlags(.TransparentBars)

            .edView             = .scrollWnd.createView'PropertiesView()
            .edView.ed          = ed
            .edView.mode        = .Top
            .edView.spacing     = 0
            .edView.focusPolicy = .Inner
            .edView.wndFlags    |= .NoScroll
            .focusDelegate      = .edView

            let theme = parent.theme()

            if kind == .List
            {
                const FontSectionSize  = 24'u32
                const FontCategorySize = 18'u32
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
                .leftMargin           = 20
                .rightMargin          = 8
            }

            // Condensed: a dense, classic property grid with thin rows and tight
            // margins. Inherits the grid-family fonts/layout set just above.
            if kind == .Condensed
            {
                .gridLineHeight = 24
                .gridLineMargin = 4
                .leftMargin     = 16
            }

            // Panel: full-width self-labeled rows, tight side margins. The line margin
            // is the vertical breathing room between two rows (half above, half below).
            if kind == .Panel
            {
                .leftMargin     = 8
                .rightMargin    = 8
                .gridLineMargin = 8
            }

            .hookOnChildEvent = func(wnd, evt) { return onHookChildEvent(wnd, evt); }

            // Built-in context-menu commands (Copy/Paste/array ops) go through the shared gui
            // action system instead of a hardcoded id switch. See actionproperties.swg.
            .registerAction'ActionProperties()
        }

        return ed
    }

    // Set the host-level notify interface, consulted for every row in addition to the
    // per-struct implementations. Lets a host that does not own the displayed structs plug
    // dynamic visibility/enabling, read-only state and change reactions.
    mtd setNotify(itf: #null IPropertyNotify)
    {
        .hostNtfy = itf
    }

    // Sets the preferred maximum width of value editors and refreshes the current layout.
    mtd setEditorWidth(width: s32)
    {
        Debug.assert(width > 0)
        if .editorWidth == width do
            return
        .editorWidth = width
        .updateStates()
    }

    // Controls whether reflected `using` fields are appended after the struct's own fields.
    // The option applies to structures added after this call.
    mtd setUsingFieldsLast(enabled: bool)
    {
        .usingFieldsLast = enabled
    }

    // Shows or hides reset-to-default affordances for modified values.
    mtd setRevertButtonsVisible(visible: bool)
    {
        if .revertButtonsVisible == visible do
            return
        .revertButtonsVisible = visible
        discard .updateDefaults()
        .invalidate()
    }

    // Drop every displayed struct and row, keeping the widget alive so a new content can be
    // bound with addStruct/addStructMulti (an editor panel re-targeting the current selection).
    // The undo history recorded so far survives on an external manager (its commands are
    // detached from the rows); the internal one is cleared with the content it refers to.
    mtd clear()
    {
        if !.externUndoMgr do
            .undoMgr.clear()

        .generation += 1
        .dragItem   = null
        .dragCmd    = null
        .hotItem, .selItem, .menuItem = null

        .freeDefaultRoots()

        for it in .items
        {
            let itn = it!
            itn.line.destroyNow()
        }

        .items.clear()
        .sections.clear()
        .gridLevelHasMark.clear()
        .currentSectionIndex = Swag.U32.Max
        .updateStates()
    }

    // Add a new struct to display.
    mtd addStruct(val: any, section: #null string = null)
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
    // With 'onlyNamed', only the fields carrying an explicit Properties.Name attribute get a
    // row: the grid becomes opt-in, for structs whose fields are mostly internal state.
    mtd addStructMulti(typeof: typeinfo, bases: [..] *u8, section: #null string = null, onlyNamed = false)
    {
        Debug.assert(typeof.kind == .Struct)
        Debug.assert(@countof(bases) >= 1)

        .buildOnlyNamed = onlyNamed
        defer .buildOnlyNamed = false

        let firstItemIdx   = .items.count
        var item: #null *PropertiesItem
        let numItemsBefore = .items.count

        // Section
        if section != null
        {
            let v = Swag.TypeValue{name: section}
            item = .addItem(v, null, null)
            item.flags.add(.Section | .NoSeparator | .Expanded | .NoFocus)
            item.label.style.setFont(&.fontSection)
            item.section = cast(u32) .sections.count
            .sections.add({item, 0})
        }

        // Creates an empty parent item. The placeholder row is invisible: it must not
        // consume any vertical room (addItem turns a zero height into gridLineHeight,
        // and gives Panel rows their inter-row margins).
        else
        {
            let v: Swag.TypeValue
            item = .addItem(v, null, null, 0, .None)
            item.flags.add(.Section | .NoSeparator | .Expanded | .NoFocus)
            item.valueCellHeight                   = 0
            item.line.position.height              = 0
            item.line.preferredSize.y              = 0
            item.line.margin.y, item.line.margin.w = 0
        }

        let typeStruct = cast(const *Swag.TypeInfoStruct) typeof
        .addStructInternal(typeStruct, cast([*] u8) bases[0], item)

        let itemn = item!
        itemn.numChilds = cast(u32) (.items.count - numItemsBefore)

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
    internal mtd assignInstances(fromIdx: u64, bases: [..] *u8)
    {
        if @countof(bases) <= 1 do
            return

        let base0 = cast([*] u8) bases[0]
        for i in fromIdx until .items.count
        {
            let it = .items[i]!
            it.dataInstances.clear()
            if !it.data do
                continue

            if .isUnderDynamicArray(it!)
            {
                it.dataInstances.add(it.data)
                continue
            }

            let off = cast(#null [*] u8) it.data - base0
            for b in bases do
                it.dataInstances.add(cast(*u8) (cast([*] u8) b + off))
        }
    }

    // Refresh all displayed values.
    mtd refresh()
    {
        for it in .items do
            .refreshItem(it!)
    }

    // Commits a value written by an editor, including propagation, undo, refresh, validation,
    // layout and notifications. Custom IPropertyEditor implementations call this once per
    // logical edit after updating the bound data.
    mtd commitItemChange(item: *PropertiesItem)
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

        .finishItemChange(item)
    }

    // The refresh/relayout/notify tail shared by a user edit and by an undo/redo
    // restore (applyUndoValue) — everything except propagation and undo recording.
    internal mtd finishItemChange(item: *PropertiesItem)
    {
        .refresh()

        // A change can add/remove a validation bar (row height) or flip a row's revert marker
        // (row layout): relay out the grid so the rows below shift and the scroll size stays
        // correct.
        var relayout        = .updateValidation()
        let defaultsChanged = .updateDefaults()
        if defaultsChanged do
            relayout = true
        if .modifiedOnly
        {
            // The edited row may have entered or left the modified-only result set.
            .updateStates()
            relayout = false
        }
        elif relayout
        {
            .applyLayout()
            .scrollWnd.view.sendResizeEvent()
        }

        .sigValueChanged.call(me, item)

        // Notify the host, then all the hierarchy
        if .hostNtfy do
            .hostNtfy.itemHasChanged(me, item)

        var scan = cast(#null *PropertiesItem) item
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
    mtd setFilter(filter: string)
    {
        if .stringFilter == filter do
            return
        .stringFilter = filter
        .updateStates()
    }

    // Restricts the view to fields that differ from their declared defaults. Text filtering and
    // the modified-only filter compose, and matching descendants remain visible through collapsed
    // categories while either filter is active.
    mtd setModifiedOnly(enabled: bool)
    {
        if .modifiedOnly == enabled do
            return
        .modifiedOnly = enabled
        .updateStates()
    }

    // Expands every collapsible section and category in grid presentations.
    mtd expandAll()
    {
        if !.isGridLike() do
            return

        for item in .items where item!.numChilds do
            item!.flags.add(.Expanded)
        .updateStates()
    }

    // Collapses every visible section and category in grid presentations.
    //
    // The invisible root used when [[Gui.Properties.addStruct]] has no section label remains
    // expanded so collapsing the view never hides the complete editor behind a row the user
    // cannot reopen.
    mtd collapseAll()
    {
        if !.isGridLike() do
            return

        for item in .items where item!.numChilds and item!.line.position.height > 0 do
            item!.flags.remove(.Expanded)
        .updateStates()
    }

    // Expands only the branches containing fields that differ from their declared defaults.
    // Other visible branches are collapsed; the current text and modified-only filters remain
    // unchanged.
    mtd expandModified()
    {
        if !.isGridLike() do
            return

        for item in .items where item!.numChilds and item!.line.position.height > 0 do
            item!.flags.remove(.Expanded)

        for item in .items where item!.isModified
        {
            var parent = item!.parent
            while parent
            {
                if parent.numChilds do
                    parent.flags.add(.Expanded)
                parent = parent.parent
            }
        }

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
        if item.type == #null string do
            return true

        if Reflection.hasAttribute(item.typeValue, .ReadOnly) do
            return true

        if .hostNtfy and .hostNtfy.isItemReadOnly(me, item) do
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
    internal mtd canChangeItem(item: *PropertiesItem)->bool
    {
        if !item.data or !item.type do
            return false

        if .isItemReadOnly(item) do
            return false

        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if @isset(scan.line) and scan.line.isDisabled() do
                return false
            scan = scan.parent
        }

        return true
    }

    // Update the state of the given item
    internal mtd updateItemState(item: *PropertiesItem)
    {
        var mustShow   = false
        var mustEnable = false

        if item.section == .currentSectionIndex or .currentSectionIndex >= .sections.count
        {
            mustShow = !.modifiedOnly or (item.data != null and item.isModified)
            if mustShow and !.stringFilter.isEmpty() do
                mustShow = Utf8.indexOf(item.filter.toSlice(), .stringFilter, comparisonType: Utf8.ComparisonType.Latin1NoCase) != Swag.U64.Max

            if mustShow do
                {
                    mustShow, mustEnable
                } = .itemState(item)
        }

        item.line.show(mustShow)
        item.line.enable(mustEnable)

        // Read-only items stay visible and selectable (so they can still be copied and the
        // context menu opened). An edit box becomes read-only — focusable but not editable,
        // exactly like a static string; any other editor (slider, combo, checkbox, ...) is
        // grayed instead, since those have no read-only mode.
        let readOnly = .isItemReadOnly(item)
        if @isset(item.editBox)
        {
            if readOnly do
                item.editBox.updateFlags(.ReadOnly)
            else do
                item.editBox.updateFlags(remove: .ReadOnly)
        }

        for c in item.line.children
        {
            if @isset(item.label) and c == item.label do
                continue
            if @isset(item.labelDesc) and c == item.labelDesc do
                continue
            if @isset(item.validationLabel) and c == item.validationLabel do
                continue
            if @isset(item.editBox) and c == cast(#null *Wnd) item.editBox do
                continue

            // The revert arrow manages its own enabled state (enabled only while modified), so it
            // must not be swept along with the row's read-only state here.
            if @isset(item.revertButton) and c == cast(#null *Wnd) item.revertButton do
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

                {?, mustEnable} = .itemState(scan)
                scan.line.enable(mustEnable)

                scan = scan.parent
            }
        }
    }

    // Update the show/hide state of all content
    internal mtd updateStates()
    {
        // Refresh which depths reserve a triangle slot before the layout below re-syncs the label
        // paddings (syncColumnLabels, via applyLayout -> resize) that depend on it.
        .computeLevelMarks()

        .updateValidation()
        .updateDefaults()
        for it in .items do
            .updateItemState(it!)
        .applyLayout()
        .scrollWnd.view.sendResizeEvent()
    }
}
