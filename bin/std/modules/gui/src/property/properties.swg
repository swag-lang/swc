#global public
using Core, Pixel

// To specialize the edition of a given struct.
interface IPropertyValue
{
    mtd construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem;
}

// To notify a struct about properties changes
#[Swag.Warning("Wrn0006", .Disable)]
interface IPropertyNotify
{
    mtd itemHasChanged(list: *Properties, item: *PropertiesItem) {}
    mtd isItemVisible(list: *Properties, item: *PropertiesItem)->bool { return true; }
    mtd isItemEnabled(list: *Properties, item: *PropertiesItem)->bool { return true; }
    mtd fillPopupMenu(list: *Properties, item: *PropertiesItem, menu: *MenuCtrl) {}

    // Return a validation state + message for 'item'. Called on build and after every
    // change; the row shows an accent bar + badge in the state color and the message as a
    // tooltip. The most severe result along the item's parent chain wins.
    mtd validateItem(list: *Properties, item: *PropertiesItem)->PropValidationResult { return {}; }
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
}

#[Swag.EnumFlags]
enum AddItemFlags
{
    Zero        = 0
    Name
    Description
}

#[Swag.EnumFlags]
enum ItemFlags
{
    Zero        = 0
    NoSeparator
    NoFocus
    Section
    Category
    Expanded
}

struct PropertiesItem
{
    filter:             String
    line:               *Wnd
    data:               *u8
    // Field address in every edited instance (multi-selection). [0] aliases `data`.
    // Empty or a single entry means a plain single-instance edit. Items under a dynamic
    // array are left single (their element addresses are not at a fixed struct offset).
    dataInstances:      Array'(*u8)
    // When set, the editor writes each instance itself (e.g. a vector component or an
    // enum-flags bit), so hasChanged must not blindly copy the whole field over the
    // others — that would clobber the components/bits the user did not touch.
    selfPropagate:      bool
    type:               typeinfo
    typeValue:          Swag.TypeValue
    parent:             *PropertiesItem
    flags:              ItemFlags
    userData0:          *void
    userData1:          *void

    label:              *Label
    description:        String
    labelDesc:          *Label

    // Per-item validation (info/warning/error) shown as an inline colored message bar
    // stacked under the row.
    validation:         PropValidation
    validationMsg:      String
    validationLabel:    *Label

    editBox:            *EditBox
    checkBox:           *CheckButton
    comboBox:           *ComboBox
    sliderBox:          *SliderCtrl

    sigResize:          SigArray'func||(*PropertiesItem)
    sigRefresh:         SigArray'func||(*PropertiesItem)

    ntfyItf:            IPropertyNotify

    aniFocusBk:         BlendColor
    aniFocusBorder:     BlendColor
    level:              u32
    numChilds:          u32
    section:            u32
    extendFocus:        f32 = 10

    // Grid only: height of the value cell (label + editor) on its own. The row grows below
    // it to host the validation message bar, so we keep the base height to restore/recompute.
    valueCellHeight:    f32
}

impl IWnd for Properties
{
    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        let colorBar = .cursorSet ? .getThemeColors().splitView_BarHot : .getThemeColors().prop_GridColumn
        .aniBar.apply(me, colorBar)
    }
}

impl Properties
{
    // True for the grid-family modes (Grid and Condensed). They share the same
    // column-based layout, expand/collapse behavior and column separator; only
    // their metrics (row height, margins, control size) differ.
    mtd isGridLike()->bool
    {
        return .kind == .Grid or .kind == .Condensed
    }

    // In condensed mode the value editors fill the whole value cell (both axes):
    // the grid lines already provide the visual structure, so the editor stays
    // flat and edge-to-edge instead of floating as a smaller bordered box.
    mtd adaptCondensedControl(wnd: *Wnd)
    {
        if .kind != .Condensed do
            return
        wnd.dockStyle = .Center
        wnd.maxSize.x = 0
    }

    // Flatten an edit box for the condensed cell look: no background/border at
    // rest (only when invalid), with a small horizontal padding so the text does
    // not touch the column separator.
    mtd flattenCondensedEdit(ed: *EditBox)
    {
        if .kind != .Condensed do
            return
        ed.setForm(.Transparent)
        ed.setAllPaddings(Math.Vector4{8, 0, 8, 0})
    }
}

fileprivate impl Properties
{
    mtd clampColumnSize(size: s32)->s32
    {
        let maxSize = cast(s32) .position.width - .gridMarginColumn - .leftMargin - .rightMargin
        if maxSize < .gridMarginColumn do
            return Math.max(size, .gridMarginColumn)
        return Math.clamp(size, .gridMarginColumn, maxSize)
    }

    mtd isGridHeader(item: *PropertiesItem)->bool
    {
        return .isGridLike() and item.flags.has(.Section | .Category)
    }

    mtd getGridHeaderLabelWidth(item: *PropertiesItem)->f32
    {
        var width = .edView.position.width
        if width <= 0 do
            width = .position.width
        if width <= 0 do
            width = item.line.position.width
        return Math.max(width - item.line.margin.x - item.line.margin.z - item.label.margin.x - item.label.margin.z, 1.0)
    }

    mtd syncColumnLabel(item: *PropertiesItem)
    {
        if !item.label do
            return

        if .isGridHeader(item)
        {
            item.label.margin.z      = 0
            item.label.paddingText.x = .leftMargin
            item.label.position.width = .getGridHeaderLabelWidth(item)
        }
        else do
            item.label.position.width = .gridColumnSize
    }

    mtd syncColumnLabels()
    {
        foreach item in .items do
            .syncColumnLabel(item)
    }

    mtd getDisclosureIconPosition(item: *PropertiesItem, r: Math.Rectangle, icon: Icon)->Math.Point
    {
        const OpticalTextCenterY = -2'f32

        let iconX       = r.x + Math.max(.leftMargin - icon.sizeX, 0.0) * 0.5
        let iconCenterY = item.label ? item.label.position.vertCenter() : r.vertCenter()
        return {iconX, iconCenterY - icon.sizeY * 0.5 + OpticalTextCenterY}
    }

    mtd getColumnX()->f32
    {
        return .gridColumnSize + .gridMarginColumn * 0.5
    }

    mtd hitTest(ptLoc: Math.Point)->#null *PropertiesItem
    {
        let pt = ptLoc + .scrollWnd.getScrollPos()
        foreach item in .items
        {
            if !item.line.isVisible() do
                continue
            var r = item.line.position
            r.inflate(item.extendFocus)
            if r.contains(pt) do
                return item
        }

        return null
    }

    mtd popupMenu(item: *PropertiesItem, pt: Math.Point)
    {
        ToolTip.hide(item.line)

        let menu = MenuCtrl.createPopup(me)
        var scan = item
        while scan
        {
            if scan.ntfyItf do
                scan.ntfyItf.fillPopupMenu(me, item, menu)
            scan = scan.parent
        }

        let canChange     = canChangeItem(item)
        var itemDisabled: bool

        if Reflection.isStructArray(item.type)
        {
            let arrData = cast(*Array'u8) item.data
            itemDisabled = !canChange or arrData.isEmpty()
            menu.addItem("Remove All", "ClearArray", .getTheme().getIcon24(.RemoveAll), disabled: itemDisabled)
        }

        if item.parent and item.parent.type and Reflection.isStructArray(item.parent.type)
        {
            itemDisabled = !canChange
            menu.addItem("Remove", "ClearElementArray", .getTheme().getIcon24(.Remove), disabled: itemDisabled)
        }

        if item.data and item.type
        {
            if menu.items.count do
                menu.addSeparator()
            menu.addItem("Copy", "Copy", .getTheme().getIcon24(.Copy))
            itemDisabled = !canChange or !Clipboard.hasTypedValue(item.type)
            menu.addItem("Paste", "Paste", .getTheme().getIcon24(.Paste), disabled: itemDisabled)
        }

        if !menu.items.count
        {
            menu.destroy()
            return
        }

        .editPopup = menu
        let result = menu.doModal(pt)
        .editPopup = null

        switch result
        {
        case "ClearArray":
            if MessageDlg.confirm(.wnd.surface, "This will remove all elements") != Dialog.BtnYes do
                break
            .clearArray(item)

        case "ClearElementArray":
            if MessageDlg.confirm(.wnd.surface, "This will remove the element") != Dialog.BtnYes do
                break
            .removeArrayValue(item)

        case "Copy":
            Clipboard.addTypedValue(item.data, item.type)

        case "Paste":
            if Clipboard.getTypedValue(item.data, item.type)
            {
                .refreshItem(item)
                .hasChanged(item)
            }
        }
    }

    func onHookChildEvent(wnd: *Wnd, evt: IEvent)->bool
    {
        let prop = cast(*Properties) wnd
        if prop.editPopup
        {
            // While an editor popup (e.g. the color picker) is open the popup is anchored
            // to a fixed surface position, so the list must not scroll out from under it.
            // Swallow only wheel events aimed at the grid; let everything else through so
            // the popup can still close on an outside click and the trigger button's hover
            // state can clear normally. Wheel events inside the popup are left alone so it
            // can scroll its own content.
            if let mouseEvt = evt as MouseEvent where mouseEvt.kind == .MouseWheel
            {
                let target = mouseEvt.target
                if !(target and (target == prop.editPopup or prop.editPopup.isParentOf(target))) do
                    return true
            }
            return false
        }

        switch evt
        {
        case FocusEvent as focusEvt where focusEvt.kind == .CanSetFocus:
            if prop.cursorSet do
                focusEvt.canChangeFocus = false

        // While a row editor has the focus, intercept the navigation/mode keys
        // before the editor sees them so the grid is always keyboard-drivable.
        case KeyEvent as keyEvt where keyEvt.kind == .KeyPressed:
            if prop.editKeyEvent(keyEvt) do
                return true

        case MouseEvent as mouseEvt where mouseEvt.kind == .MousePressed:
            let pt = prop.surfaceToLocal(mouseEvt.surfacePos)

            prop.selItem = prop.hitTest(pt)
            wnd.invalidate()

            if mouseEvt.button != .Left do
                break

            // On column bar
            if prop.cursorSet
            {
                prop.resizingColumn = true
                return true
            }

            // Toggle/Expand
            if prop.isGridLike() and
               prop.selItem and
               prop.selItem.numChilds and
               pt.x < prop.leftMargin
            {
                prop.selItem.flags.toggle(.Expanded)
                prop.updateStates()
            }

            // Clicking a row (but not its editor) puts the keyboard focus on the
            // grid in navigation mode, so the arrows work right after a click.
            if !prop.isEditorWnd(mouseEvt.target) do
                prop.focusNav()

        case MouseEvent as mouseEvt where mouseEvt.kind == .MouseDoubleClick and mouseEvt.button == .Left:

            // Toggle/Expand
            if prop.isGridLike() and
               prop.selItem and
               prop.selItem.numChilds
            {
                prop.selItem.flags.toggle(.Expanded)
                prop.updateStates()
            }

            // Toggle checkbox
            elif prop.selItem.checkBox
            {
                prop.selItem.checkBox.toggle()
            }

        case MouseEvent as mouseEvt where mouseEvt.kind == .MouseReleased:
            prop.resizingColumn = false

        case MouseEvent as mouseEvt where mouseEvt.kind == .MouseLeave:
            if prop.hotItem and prop.isGridLike() do
                ToolTip.hide(prop.hotItem.line)
            prop.hotItem = null

        case MouseEvent as mouseEvt where (mouseEvt.kind == .MouseMove or mouseEvt.kind == .MouseSetCursor):
            var pt = prop.surfaceToLocal(mouseEvt.surfacePos)

            // Resize of the grid column
            if prop.resizingColumn
            {
                prop.setColumnSize(cast() (pt.x - prop.gridMarginColumn * 0.5))
                return true
            }

            // Hot item
            let hit = prop.hitTest(pt)
            if hit != prop.hotItem
            {
                // Leaving a row: drop its tooltip so it does not linger over the next row.
                if prop.hotItem do
                    ToolTip.hide(prop.hotItem.line)
                prop.hotItem = hit

                if hit and hit.label and prop.isGridLike()
                {
                    pt = hit.label.surfaceToLocal(mouseEvt.surfacePos)
                    if hit.label.getClientRect().contains(pt) do
                        ToolTip.show(hit.line, mouseEvt.surfacePos, hit.description)
                }

                wnd.invalidate()
            }

            // On the column size bar
            if prop.isGridLike()
            {
                let x = prop.getColumnX()
                if pt.x >= x - 3 and pt.x <= x + 3 and hit and !hit.flags.has(.NoSeparator)
                {
                    prop.getApp().setFrameCursor(Cursor.from(.SizeWE))
                    prop.cursorSet = true
                    prop.invalidate()
                }
                elif prop.cursorSet
                {
                    prop.cursorSet = false
                    prop.invalidate()
                }
            }
        }

        return false
    }

    mtd paintBackItem(painter: *Painter, item: *PropertiesItem, wndItem: *Wnd)
    {
        var colBkBk, colBk, colBorder: Color

        let colors = .wnd.getThemeColors()
        if item == .selItem
        {
            colBk     = colors.prop_FocusBk
            colBorder = colors.prop_FocusBorder
        }
        elif .hotItem == item and .hotItem.line.isEnabled()
        {
            colBk     = colors.prop_HotBk
            colBorder = colors.prop_HotBorder
        }

        item.aniFocusBk.apply(wndItem, colBk)
        item.aniFocusBorder.apply(wndItem, colBorder)

        var r = wndItem.getClientRect()
        r.moveTop(wndItem.childs.front().position.y)
        r.inflate(item.extendFocus)
        if .isGridLike()
        {
            r.x     = 0
            r.width = .edView.position.width - 1
        }
        else
        {
            r.x     = -.leftMargin + 1
            r.width = .edView.position.width - 1
        }

        // When a validation bar grows the grid row, the row chrome (background, border, focus
        // box) wraps the whole thing so the bar reads as part of the row. The column separator
        // is the exception: it must stop at the value cell, since the bar spans full width.
        var valueCellBottom = r.bottom()
        if .isGridLike() and item.validationLabel and item.validationLabel.isVisible() do
            valueCellBottom = item.validationLabel.position.y - .valBarPaddingY

        // Background
        if .isGridLike() and item.flags.has(.Section) do
            colBkBk = colors.prop_SectionBk
        elif .isGridLike() and item.flags.has(.Category) do
            colBkBk = colors.prop_CategBk
        elif .isGridLike() and item.level > 1 do
            colBkBk = colors.prop_Bk1
        painter.fillRect(r, colBkBk)

        // Hot and focus box background
        {
            var r1 = r
            r1.inflate(-2)
            painter.fillRoundRect(r1, 4, 4, item.aniFocusBk.cur())
        }

        // In grid mode, display borders and column separator
        if .isGridLike()
        {
            var r1 = r
            r1.height += 1
            painter.drawRect(r1, colors.prop_GridBorder)

            if !item.flags.has(.NoSeparator)
            {
                let x    = .getColumnX() - item.line.position.x
                let size = .cursorSet ? 4 : 1
                let rect = Math.Rectangle{x - size * 0.5, r1.y, size, valueCellBottom - r1.y}
                painter.fillRect(rect, .aniBar.cur())
            }
        }

        // Hot and focus border
        {
            var r1 = r
            r1.inflate(-2)
            painter.drawRoundRect(r1, 4, 4, item.aniFocusBorder.cur())
        }

        // Validation feedback: an inline colored message bar stacked under the value cell,
        // in both list and grid modes.
        .paintValidationBar(painter, item)

        // Expand/Collapse icon
        if .isGridLike() and item.numChilds
        {
            let expand = .getTheme().getIcon24(item.flags.has(.Expanded) ? .Expanded : .Collapsed)
            let iconColor = item.line.isDisabled() ? colors.label_DisabledIcon : colors.label_Icon
            let iconPos = .getDisclosureIconPosition(item, r, expand)
            expand.paint(painter, iconPos.x, iconPos.y, iconColor)
        }
    }

    mtd onItemEvent(item: *PropertiesItem, wndItem: *Wnd, evt: IEvent)->bool
    {
        if wndItem.childs.isEmpty() do
            return false

        switch evt
        {
        case MouseEvent as mouseEvt where mouseEvt.kind == .MousePressed and mouseEvt.button == .Right:
            .popupMenu(item, mouseEvt.surfacePos)
            return true

        case NotifyEvent as ntfyEvt where ntfyEvt.ntfyKind == .ChildFocusChanged:
            wndItem.invalidate()
            return true

        case PaintEvent as paintEvt where paintEvt.kind == .PrePaint:
            .paintBackItem(paintEvt.bc.painter, item, wndItem)
        }

        return false
    }

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

    mtd addItem(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem, height: f32 = 0, flags = AddItemFlags.Name | AddItemFlags.Description)->*PropertiesItem
    {
        var line: *Wnd

        if .isGridLike() do
            line = Wnd.create'Wnd(.edView, {0, 0, .position.width, height orelse .gridLineHeight})
        else
        {
            let stk = StackLayoutCtrl.create(.edView, .Top, {0, 0, .position.width, height orelse .gridLineHeight})
            stk.fitToContent = true
            line             = stk
        }

        with line
        {
            .margin.z = me.rightMargin
            .wndFlags.add(.PreChildsPaint)

            // Lines never take the keyboard focus themselves: navigation lives on
            // the edView and edition on the row editors. This keeps a click on a
            // row label from stealing focus away from the navigation surface.
            .focusStrategy = .None

            if me.isGridLike()
            {
                .margin.y = me.gridLineMargin * 0.5
                .margin.w = me.gridLineMargin * 0.5
            }
            else do
                .margin.x = me.leftMargin
        }

        with let item = me.items.addNewPtr()
        {
            .line      = line
            .type      = value.pointedType
            .typeValue = value
            .data      = data
            .parent    = parentItem
            .level     = parentItem ? parentItem.level + 1 : 0
            .section   = parentItem ? parentItem.section : 0
            .valueCellHeight = height orelse me.gridLineHeight
            if me.isGridLike() do
                .extendFocus = me.gridLineMargin * 0.5
        }

        let prop = me
        line.hookOnEvent = func|prop, item|(wnd, evt) { return prop.onItemEvent(item, wnd, evt); }

        // Name
        if flags.has(.Name)
        {
            var dispName: String

            let attrName = Reflection.getAttributeValue(value, Properties.Name, "name")
            if attrName != null do
                dispName = cast(string) attrName
            else do
                dispName = Utf8.beautifyName(value.name)

            if !dispName.isEmpty()
            {
                with let label = Label.create(line, dispName, {0, 0, me.gridColumnSize, item.line.position.height})
                {
                    if me.isGridLike()
                    {
                        .vertAlignmentText = .Center
                        .horzAlignmentText = .Left
                        .dockStyle         = .Left
                        .margin.z          = me.gridMarginColumn
                        .paddingText.x     = me.leftMargin
                    }
                    else
                    {
                        .labelFlags |= .WordWrap | .AutoHeight | .DontAdaptSingleLineHeight
                        .vertAlignmentText = .Top
                        .horzAlignmentText = .Left
                        .margin.y          = me.listNameMarginBefore
                        .margin.w          = me.listNameMarginAfter
                    }

                    .style.setFont(me.fontName)
                }

                item.label = label
                if parentItem
                {
                    item.filter += " "
                    item.filter = parentItem.filter
                    item.filter += " "
                }

                item.filter += dispName
            }
        }

        // Description
        let dispDesc = Reflection.getAttributeValue(value, Properties.Description, "desc")
        if dispDesc != null
        {
            item.filter += " "
            item.filter += cast(string) dispDesc
            item.description = cast(string) dispDesc

            if flags.has(.Description)
            {
                if !.isGridLike()
                {
                    with let labelDesc = Label.create(line, "", {0, 0, me.position.width, 0})
                    {
                        .labelFlags |= .WordWrap | .AutoHeight | .DontAdaptSingleLineHeight
                        .vertAlignmentText = .Top
                        .horzAlignmentText = .Left
                        .margin.w          = me.listDescMarginAfter
                        .setText(cast(string) dispDesc)
                        item.labelDesc = labelDesc
                    }
                }
            }
        }

        return item
    }

    mtd addValue(value: Swag.TypeValue, data: [*] u8, parentItem: *PropertiesItem)
    {
        // Value
        switch
        {
        case Reflection.isStaticArray(value.pointedType):
            let item           = .addItem(value, data, parentItem)
            let typeArr        = cast(const *Swag.TypeInfoArray) value.pointedType
            let numItemsBefore = .items.count

            var newData = data
            for i in typeArr.count
            {
                var subValue: Swag.TypeValue
                subValue.name        = Format.toString("%", i).toString()
                subValue.pointedType = typeArr.pointedType
                .addValue(subValue, newData, item)
                newData += typeArr.pointedType.sizeof
            }

            item.numChilds += cast(u32) (.items.count - numItemsBefore)

        case Reflection.isEnum(value.pointedType):
            let typeEnum = cast(const *Swag.TypeInfoEnum) value.pointedType
            .constructEnum(value, typeEnum, data, parentItem)

        case value.pointedType == Core.String:
            .constructDynamicString(value, data, parentItem)

        case Reflection.isString(value.pointedType):
            .constructStaticString(value, data, parentItem)

        case Reflection.isBool(value.pointedType):
            .constructBool(value, data, parentItem)

        case Reflection.isInteger(value.pointedType) or Reflection.isFloat(value.pointedType):
            let typeNative = cast(const *Swag.TypeInfoNative) value.pointedType
            .constructNative(value, typeNative, data, parentItem)

        case value.pointedType == Array:
            .constructArray(value, data, parentItem)

        case Reflection.isStruct(value.pointedType):
            let typeSubStruct = cast(const *Swag.TypeInfoStruct) value.pointedType
            if typeSubStruct.fromGeneric == Array
            {
                .constructArray(value, data, parentItem)
                break
            }

            parentItem.flags.add(.NoSeparator | .NoFocus)
            let iprop = @mkinterface(data, value.pointedType, IPropertyValue)
            if iprop != null
            {
                let item = iprop.construct(me, value, data, parentItem)
                Debug.assert(item != null)
                item.sigRefresh.call(item)
            }
            else
            {
                let item           = .addItem(value, data, parentItem)
                let numItemsBefore = .items.count
                .addStructInternal(typeSubStruct, data, item)
                item.numChilds = cast(u32) (.items.count - numItemsBefore)
            }
        }
    }

    mtd addStructInternal(typeStruct: const *Swag.TypeInfoStruct, addr: [*] u8, parentItem: *PropertiesItem)
    {
        var newParent = parentItem

        // If the struct has implemented the notify interface, store it
        if parentItem do
            parentItem.ntfyItf = @mkinterface(addr, typeStruct, IPropertyNotify)

        var categItem: *PropertiesItem
        foreach value in typeStruct.fields
        {
            // Category
            let subCateg = Reflection.getAttributeValue(value, Properties.Category, "name")
            if subCateg != null
            {
                let v:   Swag.TypeValue{name: cast(string) subCateg}
                let item = .addItem(v, null, parentItem)
                item.label.style.setFont(&.fontCategory)
                item.flags.add(.Category | .NoSeparator | .Expanded | .NoFocus)
                item.level = 0
                .sections.add({item, 1})
                newParent = item
                categItem = item
            }

            let numItemsBefore = .items.count
            .addValue(value, addr + value.offset, newParent)
            if categItem do
                categItem.numChilds += cast(u32) (.items.count - numItemsBefore)
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

        .refresh()

        // A change can add or remove a validation bar, which changes the row height: relay
        // out the grid so the rows below shift and the scroll size stays correct.
        if .updateValidation()
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

    // Returns true if the given item can be changed
    func canChangeItem(item: *PropertiesItem)->bool
    {
        if !item.data or !item.type do
            return false

        if item.type == string do
            return false

        var scan = item
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
        .applyLayout()
        .scrollWnd.view.sendResizeEvent()
    }

    // Set the grid mode column size
    mtd setColumnSize(size: s32)
    {
        if !.isGridLike() do
            return

        .gridColumnSizeReq = size
        .gridColumnSize    = .clampColumnSize(size)
        .syncColumnLabels()
        .applyLayout()
        .invalidate()
    }

    mtd refreshGridColumnLayout()
    {
        if !.isGridLike() do
            return

        .gridColumnSize = .clampColumnSize(.gridColumnSizeReq)
        .syncColumnLabels()
    }
}
