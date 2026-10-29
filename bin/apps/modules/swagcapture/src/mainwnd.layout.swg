// Width of the step number on the mini-bar.
const StepperWidth = 88.0

// The most recent captures the lens shows as pictures.
const MaxLensRecents = 6

// Paints the preview of a recent capture into a picture of the lens, filling it.
func paintLensRecent(painter: *Painter, rect: Math.Rectangle, preview: Texture)
{
    if not preview.isValid() do
        return
    let ratio = Math.max(rect.width / preview.width, rect.height / preview.height)
    let w     = preview.width * ratio
    let h     = preview.height * ratio
    painter.setInterpolationMode(.Linear)
    painter.drawTexture(Math.Rectangle{rect.horzCenter() - w * 0.5, rect.vertCenter() - h * 0.5, w, h}, preview)
}

// The alignment a glyph of the text mini-bar stands for, and whether it is down the box rather
// than across it, kept in the user data of the glyph.
func alignUserData(align: FormTextAlign, vertical: bool)->*void => cast(*void, cast(u64, align) + (vertical ? AlignVerticalFlag : 0))
func alignOfUserData(data: *void?)->FormTextAlign => cast(FormTextAlign, cast(u64, data) & ~AlignVerticalFlag)
func alignIsVertical(data: *void?)->bool => (cast(u64, data) & AlignVerticalFlag) != 0
const AlignVerticalFlag = 0x100'u64

// The faces a text can be set in, listed by the face of the mini-bar, enumerated once.
var g_MiniBarFonts: Array'SystemFontFamilyInfo

// The room the floating parts of the editor take over the edges of the work.
struct FloatingInsets
{
    left:  f32     // Taken over the leading edge, by the dock.
    right: f32     // Taken over the trailing edge, by the unfolded inspector.
}

impl MainWnd
{
    // Speech-bubble glyph drawn for the Callout tool: the icon sheet has no sprite for this
    // tool, so it paints its own rounded body plus a small tail. Its round corners are deliberate:
    // the glyph depicts a shape the user draws, not chrome.
    func drawCalloutGlyph(btn: *IconButton, bc: *PaintContext, pos: Math.Rectangle, _: PaintItemFlags)
    {
        bc.painter.setParams(.Antialiased)
        let col = btn.isChecked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon

        // A custom painter is handed the whole content rectangle, not the icon extent, so the
        // glyph places itself where a sprite of the set would have landed: centred in its cell.
        let glyphSize = btn.themeMetrics().toolDock_Glyph
        let box       = Math.Rectangle{pos.horzCenter() - glyphSize * 0.5, pos.vertCenter() - glyphSize * 0.5, glyphSize, glyphSize}

        // The sprites of the set are outlines on about three fifths of their box; the bubble
        // matches that weight so the dock reads as one column of glyphs.
        var body = box
        body.inflate(-box.width * 0.18, -box.height * 0.22)
        body.height *= 0.72

        let stroke = 1.4'f32
        let tx     = body.x + body.width * 0.28
        let tip    = body.bottom() + box.height * 0.18
        bc.painter.drawLine(tx, body.bottom(), tx, tip, col, stroke)
        bc.painter.drawLine(tx, tip, tx + body.width * 0.28, body.bottom(), col, stroke)
        bc.painter.drawRoundRect(body, 3, 3, col, stroke)
    }

    // The work area: the capture on the ground, and the floating parts that serve it.
    //
    // The editor takes the whole window, under the strip too; the dock, the inspector, the
    // mini-bar and the hint line float over it and take no room from it.
    mtd createEditArea()
    {
        with .editArea = Wnd.create'Wnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Window
        }

        with .editWnd = EditWnd.create(me, me.editArea)
        {
            .dockStyle                = .Center
            .backgroundStyle          = .Transparent
            .sigScrollSizeChanged     += func|main = me|(_, _, _) { main.updateReading() }
            .sigScrollPositionChanged += func|main = me|(_, _, _) { main.placeMiniBar() }
        }
    }

    // The tools, in a floating column at the leading edge of the work. A tool is a command like
    // any other: its button posts it, and the command state checks the tool in use.
    mtd createDock()
    {
        let glyph = .themeMetrics().toolDock_Glyph
        .dock = ToolDock.create(.editArea)

        // Eight cells, as the pictures; a cell with a mark stands for a group of tools, each of
        // which keeps its command and its key.
        .dock.addTool(.icon(.Select, glyph), ActionToolMode.Selection)
        let shape = .dock.addTool(.icon(.Shape, glyph), ActionToolMode.Shape)
        .dock.addToGroup(shape, .icon(.Polygon, glyph), ActionToolMode.Poly)
        let arrow = .dock.addTool(.icon(.Arrow, glyph), ActionToolMode.Arrow)
        .dock.addToGroup(arrow, .icon(.Line, glyph), ActionToolMode.Line)
        .dock.addTool(.icon(.Text, glyph), ActionToolMode.Text)

        // The callout has no sprite of its own: its cell draws the bubble.
        let callout = .dock.addTool(.icon(.Text, glyph), ActionToolMode.Callout)
        callout.iconPainter = func(btn, bc, pos, flags) { drawCalloutGlyph(btn, bc, pos, flags) }

        let draw = .dock.addTool(.icon(.Draw, glyph), ActionToolMode.Draw)
        .dock.addToGroup(draw, .icon(.Highlight, glyph), ActionToolMode.Highlight)
        .dock.addTool(.icon(.Step, glyph), ActionToolMode.Step)
        let image = .dock.addTool(.icon(.Image, glyph), ActionToolMode.Img)
        .dock.addToGroup(image, .icon(.PixSel, glyph), ActionToolMode.PixSel)
        .dock.addToGroup(image, .icon(.Favorites, glyph), ActionToolMode.Favorites)
    }

    // Returns the command of the tool drawing in `mode`.
    func toolCommand(mode: EditMode)->WndId
    {
        switch #complete mode
        {
        case .Shape:     return ActionToolMode.Shape
        case .Arrow:     return ActionToolMode.Arrow
        case .Line:      return ActionToolMode.Line
        case .Polygon:   return ActionToolMode.Poly
        case .Text:      return ActionToolMode.Text
        case .Callout:   return ActionToolMode.Callout
        case .Draw:      return ActionToolMode.Draw
        case .Highlight: return ActionToolMode.Highlight
        case .Step:      return ActionToolMode.Step
        case .Image:     return ActionToolMode.Img
        case .PixSel:    return ActionToolMode.PixSel
        case .Favorites: return ActionToolMode.Favorites
        case .Selection: return ActionToolMode.Selection
        }
    }

    // The properties of the selection, or of the tool when nothing is selected: the quick styles
    // of its kind above the settings the property panel generates for it.
    mtd createInspector()
    {
        .inspector = Inspector.create(.editArea)
        .inspector.sigFoldChanged += func|main = me|(inspector)
        {
            main.inspectorFolded = inspector.folded
            main.fillHintLine()
            let view = main.editWnd.editView
            view.setZoom(view.zoom)
            main.placeMiniBar()
        }

        with let body = Wnd.create'Wnd(.inspector)
        {
            .backgroundStyle = .Transparent
        }

        with .quickWnd = QuickWnd.create(body, me)
        {
            .dockStyle = .Top
        }

        with .propWnd = PropWnd.create(body, me)
        {
            .dockStyle = .Center
        }

        .inspector.setContent(body)
    }

    // The bar that stands next to the selection, carrying what applies to it.
    mtd createMiniBar()
    {
        .miniBar = MiniBar.create(.editArea)
    }

    // Returns the room the dock and the unfolded inspector take over the leading and the trailing
    // edges of the work, which the capture is centred between.
    mtd floatingInsets()->FloatingInsets
    {
        var result: FloatingInsets
        if .dock != null and .dock.isLocallyVisible() do
            result.left = .dock.position.right()
        if .inspector != null and .inspector.isLocallyVisible() and not .inspector.folded do
            result.right = Math.max(.editArea.position.width - .inspector.position.x, 0)
        return result
    }

    // Returns the kind of mini-bar the selection calls for.
    mtd miniBarKindOfSelection()->MiniBarKind
    {
        let capture = .getCapture()
        if .libraryMode or .inPlaceEdit or not capture or capture.selection.isEmpty() do
            return .None
        if capture.selection.count > 1 do
            return .Multi

        switch capture.getSelectedFormType()
        {
        case FormText, FormCallout: return .Text
        case FormStep: return .Step
        }

        return .Single
    }

    // Returns the colour the mini-bar swatch stands for on the selected form: what fills a text,
    // a callout or a step, and the stroke of every other form.
    mtd miniBarColorField()->{type: typeinfo, name: string}
    {
        switch .getCapture()?.getSelectedFormType()
        {
        case FormText, FormCallout, FormStep: return {BaseForm, #nameof(BaseForm.backColor)}
        }

        return {BaseForm, #nameof(BaseForm.borderColor)}
    }

    // Returns the colour of the mini-bar swatch.
    mtd miniBarColor()->Color
    {
        let form = .getCapture()?.getSelectedBaseForm()
        if not form do
            return Argb.Black
        return .miniBarColorField().name == #nameof(BaseForm.backColor) ? form.backColor : form.borderColor
    }

    // Rebuilds the mini-bar when the kind of the selection changed, and places it beside it.
    mtd updateMiniBar()
    {
        if .miniBar == null do
            return

        // The bar shows the face, the size and the style of its form: another form fills it again.
        let kind = .miniBarKindOfSelection()
        let form = kind == .None or kind == .Multi ? null : .getCapture()?.getSelectedBaseForm()
        if kind != .miniBarKind or form != .miniBarForm
        {
            .miniBarKind = kind
            .miniBarForm = form
            .fillMiniBar(kind)
        }

        .miniBar.updateCommandState()
        .placeMiniBar()
    }

    // Fills the mini-bar with what applies to a selection of `kind`. Every button is also a lens
    // entry: the bar only brings the commands of the selection next to it.
    mtd fillMiniBar(kind: MiniBarKind)
    {
        .miniBar.clear()
        if kind == .None do
            return

        let theme = .theme()
        let size  = .themeMetrics().menuPopup_IconSize
        if kind == .Multi
        {
            .miniBar.addButton(.icon(.TextAlignLeft, size), ActionAlign.AlignLeft, appStrings().act_AlignLeft)
            .miniBar.addButton(.icon(.TextAlignCenter, size), ActionAlign.AlignCenter, appStrings().act_AlignCenter)
            .miniBar.addButton(.icon(.TextAlignRight, size), ActionAlign.AlignRight, appStrings().act_AlignRight)
            .miniBar.addButton(.icon(.AlignTop, size), ActionAlign.AlignTop, appStrings().act_AlignTop)
            .miniBar.addButton(.icon(.AlignMiddle, size), ActionAlign.AlignMiddle, appStrings().act_AlignMiddle)
            .miniBar.addButton(.icon(.AlignBottom, size), ActionAlign.AlignBottom, appStrings().act_AlignBottom)
            .miniBar.addSeparator()
            .miniBar.addTextButton(appStrings().act_Group, ActionGroup.Group)
        }
        else
        {
            with let swatch = .miniBar.addButton({}, toolTip: appStrings().ui_PropColor, flags: .Popup)
            {
                .setArrowPosition(.None)
                .iconPainter = func|main = me|(btn, bc, pos, _)
                {
                    let radius = btn.themeMetrics().menuPopup_IconSize * 0.5
                    bc.painter.setParams(.Antialiased)
                    bc.painter.fillCircle(pos.horzCenter(), pos.vertCenter(), radius, main.miniBarColor())
                    bc.painter.drawCircle(pos.horzCenter(), pos.vertCenter(), radius, btn.themeColors().strongLine, 1)
                }

                .sigPopupRequested += func|main = me|(button)
                {
                    let popover = ColorPopover.open(assume cast(*IconButton, button), appStrings().ui_PropColor, main.miniBarColor(), &main.recentColors)
                    popover.sigColorChanged += func|main, button, var first = true|(pop)
                    {
                        let field = main.miniBarColorField()
                        main.propWnd.pushTypedValue(pop.color.argb, field.type, field.name, first, true)
                        first = false
                        button.invalidate()
                    }
                }
            }

            if kind == .Text
            {
                .miniBar.addSeparator()
                .addTextFace()
                .miniBar.addSeparator()
                .addTextStyle()
                .miniBar.addSeparator()
                .addTextAlignment()
            }
            elif kind == .Step
            {
                .miniBar.addSeparator()
                .addStepKinds()
                .miniBar.addSeparator()
                .addStepNumber()
                .miniBar.addSeparator()
                .miniBar.addTextButton(appStrings().ui_ResetSteps).sigPressed += func|main = me|(_) { main.postCommandEvent(ActionEdit.ResetSteps) }
            }
        }

        .miniBar.addSeparator()
        .miniBar.addButton(theme.icon(.Remove, size), ActionSelection.DeleteSelection, appStrings().act_Delete)

        // `•••` opens the inspector; it is not a state of the selection, so it posts the command
        // rather than showing it checked.
        .miniBar.addButton(theme.icon(.More, size), toolTip: appStrings().act_ShowInspector).sigPressed += func|main = me|(_)
        {
            main.inspector.setFolded(false)
        }
    }

    // Returns the face, the size, the style and the horizontal alignment of the selected text or callout.
    mtd selectedTextStyle()->{found: bool, type: typeinfo, face: string, size: f32, style: FontFamilyStyle, align: FormTextAlign, alignVert: FormTextAlign}
    {
        switch .getCapture()?.getSelectedBaseForm()
        {
        case FormText as text:       return {true, FormText, text.fontName.toString(), text.fontSize, text.fontStyle, text.alignHorz, text.alignVert}
        case FormCallout as callout: return {true, FormCallout, callout.fontName.toString(), callout.fontSize, callout.fontStyle, callout.alignHorz, callout.alignVert}
        }

        return {false, FormText, "", 0, .Regular, .Center, .Center}
    }

    // Adds the face of the text and its size to the mini-bar: the face is a quiet list of every
    // face, the interface face first; the size is a number in the fixed-width face, typed over.
    mtd addTextFace()
    {
        let style = .selectedTextStyle()
        if not style.found do
            return

        let metrics = .themeMetrics()
        if g_MiniBarFonts.isEmpty() do
            g_MiniBarFonts = FontFamily.enumerateSystemFonts()

        let defaultFace = .theme().res.defaultTypeFaceR.familyName()
        let shown       = style.face.count ? style.face : defaultFace
        let font        = unwrap .font().regular
        let width       = Math.ceil(Painter.measureString(shown, font).width + 2 * metrics.comboBox_Padding + metrics.miniBar_ButtonSize)
        with let face   = ComboBox.create(.miniBar, {0, 0, width, metrics.miniBar_ButtonSize}, flags: .Flat)
        {
            .toolTip = appStrings().prop_Font
            .addItem(defaultFace)
            .addSeparator()
            var selected = 0'u32
            for &fnt, i in g_MiniBarFonts
            {
                .addItem(fnt.name)
                if fnt.name == style.face do
                    selected = cast(u32, i) + 2
            }

            .setSelectedIndex(selected, notify: false)
            .sigChanged += func|main = me|(_, index)
            {
                main.setSelectedFace(index < 2 ? "" : g_MiniBarFonts[index - 2].name.toString())
            }
        }

        .miniBar.addItem(face)

        let mono      = .theme().createDefaultFontFs(metrics.defaultFontSize)
        let digit     = Painter.measureString("000", mono).width
        with let size = EditBox.create(.miniBar, Format.toString("%", cast(s32, Math.round(style.size))), {0, 0, Math.ceil(digit + 2 * metrics.comboBox_Padding), metrics.miniBar_ButtonSize})
        {
            .toolTip = appStrings().prop_Size
            .setForm(.Transparent)
            .setUnsignedIntegerRange(cast(u64, MinFontSize), cast(u64, MaxFontSize))
            .style.setFont(.theme().createDefaultFontFamilyFs(metrics.defaultFontSize))
            .sigCommitted += func|main = me, type = style.type|(wnd)
            {
                let edit = assume cast(*EditBox, wnd)
                if not edit.isValid() do
                    return
                let {value, eat: _, ovf: _} = catch StrConv.parseU32(edit.text())
                if not value do
                    return
                let size = cast(f32, value)
                main.propWnd.pushTypedValue(cast #bit (u32, size), type, #nameof(FormText.fontSize), true)
            }
        }

        .miniBar.addItem(size)
    }

    // Sets the face of the selected texts to `face`, the interface face when empty, as one step
    // of the history; the style of each stays.
    mtd setSelectedFace(face: string)
    {
        let capture = .getCapture()
        let style   = .selectedTextStyle()
        if not capture or not style.found or face == style.face do
            return

        with let undo = capture.newUndo(.SetFont)
        {
            .text      = face
            .fontStyle = style.style
        }

        capture.pushUndo(undo)
        capture.selectionHasChanged()
    }

    // Adds bold and italic to the mini-bar: two letters, set in the style they turn on, lit when on.
    mtd addTextStyle()
    {
        let style = .selectedTextStyle()
        if not style.found do
            return

        let size      = .themeMetrics().defaultFontSize
        with let bold = .miniBar.addButton({}, toolTip: appStrings().prop_StyleBold, flags: .Toggle)
        {
            .updateFlags(add: .CenterContent, remove: .IconOnly)
            .setText("B")
            .setCheckIndicator(.Ink)
            .style.setFont(.theme().createDefaultFont(size, .Bold), .Regular)
            .setChecked(style.style == .Bold or style.style == .BoldItalic)
            .sigPressed += func|main = me|(_) { main.postCommandEvent(ActionEdit.Bold) }
        }

        with let italic = .miniBar.addButton({}, toolTip: appStrings().prop_StyleItalic, flags: .Toggle)
        {
            .updateFlags(add: .CenterContent, remove: .IconOnly)
            .setText("I")
            .setCheckIndicator(.Ink)
            .style.setFont(.theme().createDefaultFont(size, .Italic), .Regular)
            .setChecked(style.style == .Italic or style.style == .BoldItalic)
            .sigPressed += func|main = me|(_) { main.postCommandEvent(ActionEdit.Italic) }
        }
    }

    // Adds the three horizontal alignments of the text to the mini-bar, the one in force checked.
    mtd addTextAlignment()
    {
        let style = .selectedTextStyle()
        if not style.found do
            return

        // How the lines stand across the box, then down it: two groups of three glyphs.
        const Aligns = [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]
        const Across = [CaptureIcons.TextAlignLeft, CaptureIcons.TextAlignCenter, CaptureIcons.TextAlignRight]
        const Down   = [CaptureIcons.AlignTop, CaptureIcons.AlignMiddle, CaptureIcons.AlignBottom]
        let size = .themeMetrics().menuPopup_IconSize
        for vertical in [false, true]
        {
            if vertical do
                .miniBar.addSeparator()
            for align, i in Aligns
            {
                let glyph       = vertical ? Down[i] : Across[i]
                let tip         = vertical ? appStrings().ui_AnchorVertical : appStrings().ui_Anchor
                with let button = .miniBar.addButton(.icon(glyph, size), toolTip: tip, flags: .Radio)
                {
                    .userData = alignUserData(align, vertical)
                    .setChecked((vertical ? style.alignVert : style.align) == align)
                    .sigPressed += func|main = me, type = style.type, vertical|(btn)
                    {
                        let field = vertical ? #nameof(FormText.alignVert) : #nameof(FormText.alignHorz)
                        main.propWnd.pushTypedValue(cast(u32, alignOfUserData(btn.userData)), type, field, true)
                        for item in main.miniBar.items
                        {
                            if item.wnd is IconButton as other where other.flags.has(.Radio) and alignIsVertical(other.userData) == vertical do
                                other.setChecked(other == btn)
                        }
                    }
                }
            }
        }
    }

    // Adds the shapes a step marker can take to the mini-bar, the one in force checked.
    mtd addStepKinds()
    {
        let found = catch cast(*FormStep?, .getCapture()?.getSelectedBaseForm())
        if not found do
            return
        let current = found.kind
        for kind in FormShapeKind
        {
            with let button = .miniBar.addButton({}, toolTip: appStrings().act_Shape, flags: .Radio)
            {
                .userData = enumToUserData(kind)
                .setChecked(current == kind)
                .iconPainter = func(btn, bc, pos, flags)
                {
                    let colors = btn.themeColors()
                    let color  = flags & .Checked ? colors.btnIcon_CheckedIcon : colors.btnIcon_Icon
                    PropWnd.paintChoice(bc.painter, .StepKind, cast(u32, enumFromUserData'FormShapeKind(btn.userData)), pos, color)
                }
            }

            // The shapes are radios of the bar: choosing one unchecks the others.
            button.sigPressed += func|main = me|(btn)
            {
                main.propWnd.pushTypedValue(cast(u32, enumFromUserData'FormShapeKind(btn.userData)), FormStep, #nameof(FormStep.kind), true)
                for item in main.miniBar.items
                {
                    if item.wnd is IconButton as other where other.flags.has(.Radio) do
                        other.setChecked(other == btn)
                }
            }
        }
    }

    // Adds the number of the selected step marker to the mini-bar, as a stepper.
    mtd addStepNumber()
    {
        let found = catch cast(*FormStep?, .getCapture()?.getSelectedBaseForm())
        if not found do
            return
        let step = found

        with let stepper = Stepper.create(.miniBar, {0, 0, StepperWidth, 0})
        {
            .setRange(1, 999)
            .setValue(cast(s64, step.index))
            .sigChanged += func|main = me|(wnd)
            {
                let value = (assume cast(*Stepper, wnd)).value
                main.propWnd.pushTypedValue(cast(u32, value), FormStep, #nameof(FormStep.index), true)
            }
        }

        .miniBar.addItem(stepper)
    }

    // Places the mini-bar beside the selection, or hides it when nothing is selected.
    mtd placeMiniBar()
    {
        if .miniBar == null do
            return

        let capture = .getCapture()
        if .miniBarKind == .None or not capture or capture.selection.isEmpty()
        {
            discard .app().animator.leave(.miniBar)
            return
        }

        // The selection is measured in capture pixels: the view places the capture at its zoom,
        // and the work area holds the view.
        let view  = .editWnd.editView
        let bound = capture.getSelectionBoundRect()
        let place = view.getCaptureRect()
        let zoom  = view.zoom
        var rect  = Math.Rectangle{place.x + bound.x * zoom - view.scrollPos.x, place.y + bound.y * zoom - view.scrollPos.y, bound.width * zoom, bound.height * zoom}
        let local = .editArea.surfaceToLocal(view.localToSurface(Math.Point{rect.x, rect.y}))
        rect.x = local.x
        rect.y = local.y

        // The bar keeps clear of the dock and of the inspector, and goes below the words being
        // typed in place, where the reader is not looking.
        let insets = .floatingInsets()
        var room   = .editArea.clientRect()
        room.x     += insets.left
        room.width -= insets.left + insets.right
        .miniBar.showNear(.miniBarAnchor(rect, place, view), below: view.isEditingText(), room: room)
    }

    // Returns the rectangle the mini-bar stands next to, for a selection at `rect`: the
    // selection, reaching out to an edge of the capture when the bar would otherwise straddle that
    // edge, so the bar stands either inside the capture or wholly outside it.
    mtd miniBarAnchor(rect: Math.Rectangle, place: Math.Rectangle, view: *EditView)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        let reach   = metrics.miniBar_Distance + .miniBar.bodySize().y
        let corner  = .editArea.surfaceToLocal(view.localToSurface(Math.Point{place.x - view.scrollPos.x, place.y - view.scrollPos.y}))
        let top     = corner.y
        let bottom  = corner.y + place.height

        var result = rect
        if result.y - reach < top and result.y > top
        {
            result.height += result.y - top
            result.y      = top
        }

        if result.bottom() + reach > bottom and result.bottom() < bottom do
            result.height = bottom - result.y
        return result
    }

    // The faint line at the foot of the work: the size and zoom of the capture, then the key
    // that opens everything else.
    mtd createHintLine()
    {
        .hintLine = HintLine.create(.editArea)
        .fillHintLine()
    }

    // Writes the foot line: what the tool in hand does, the key of the inspector while it is
    // folded, and the one door.
    mtd fillHintLine()
    {
        if .hintLine == null do
            return

        // The line stands in the room the dock and the inspector leave, never under them.
        let insets = .floatingInsets()
        .hintLine.margin = {insets.left, 0, insets.right, 0}
        .hintLine.clearHints()
        if .editWnd != null and .editWnd.editView.isEditingText()
        {
            // The keys come first: a line cut by a narrow room loses the advice, not the keys.
            let view = .editWnd.editView
            .hintLine.addHint(view.textSpec.step ? strings().key_Enter : strings().key_CtrlEnter, appStrings().hint_KeepText)
            .hintLine.addHint(strings().key_Escape, appStrings().hint_Cancel)
            if not view.textSpec.step do
                .hintLine.addHint(strings().key_Enter, appStrings().hint_NewLine)
            if view.textEditForm() is FormCallout do
                .hintLine.addHint("", appStrings().hint_CalloutTail)
            return
        }

        // With a selection, the line teaches its keys: nudge, duplicate, then the words of a shape
        // that has some, or delete; four keys are what the room beside the inspector holds. Without
        // one, what the tool in hand does, and the lens.
        let capture  = .getCapture()
        let selected = not .libraryMode and capture and not capture.selection.isEmpty()
        if selected
        {
            .hintLine.addHint(appStrings().key_Arrows, appStrings().hint_Nudge)
            .hintLine.addHint(Input.formatKeyShortcut(.Control, .D), appStrings().hint_Duplicate)
            if capture!.selection.count == 1 and inlineTextOf(capture.forms[capture.selection[0]]).found do
                .hintLine.addHint(strings().key_Enter, appStrings().hint_TypeWords)
            else do
                .hintLine.addHint(Input.formatKeyShortcut(.None, .Delete), appStrings().hint_Delete)
        }
        else
        {
            let tool = .toolHint()
            if not tool.isEmpty() do
                .hintLine.addHint("", tool)
        }

        if .inspector != null and .inspector.folded do
            .hintLine.addHint(.inspector.foldKey, appStrings().hint_AllProperties)
        if not selected do
            .hintLine.addHint(Input.formatKeyShortcut(.Control, .Space), appStrings().hint_Space)
    }

    // Returns what the tool in hand does, in a few words.
    mtd toolHint()->String
    {
        let texts = appStrings()
        switch #complete .editMode
        {
        case .Selection:
            return texts.hint_ToolSelect

        case .Shape:
            return texts.hint_ToolShape

        case .Arrow:
            return texts.hint_ToolArrow

        case .Line:
            return texts.hint_ToolLine

        case .Polygon:
            return texts.hint_ToolPolygon

        case .Text:
            return texts.hint_ToolText

        case .Callout:
            return texts.hint_ToolCallout

        case .Draw:
            return texts.hint_ToolDraw

        case .Highlight:
            return texts.hint_ToolHighlight

        case .Image:
            return texts.hint_ToolImage

        case .PixSel:
            return texts.hint_ToolPixSel

        case .Favorites:
            return texts.hint_ToolFavorites

        case .Step:
            let capture = .getCapture()
            return Format.toString(texts.hint_ToolStep, capture ? capture.nextStepIndex : 1)
        }
    }

    // Every command, recent capture and appearance choice has a route through the lens. At rest
    // capture and output keep their positions, followed by selection actions and recent captures.
    mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            .addRestSource(func|main = me|(results) { main.describeLensContext(results) })
            .addRestSource(func|main = me|(results) { main.describeRecentCaptures(results) })
            .addSource(.None, func|main = me|(results) { main.describeRecentCaptures(results) })
            .addSource(.None, func|main = me|(results)
            {
                if main.libraryMode do
                    main.libWnd.describeLens(results)
            })
            .addCommands(func()->string => appStrings().ui_MenuCapture, [
                ActionCapture.DoIt, ActionCapture.Area, ActionCapture.LastArea, ActionCapture.FullScreen, ActionCapture.ActiveWnd])
            for idx in me.monitors.count do
                .addCommand(func()->string => appStrings().ui_MenuCapture, ActionCapture.screenId(idx))
            .addCommands(func()->string => appStrings().ui_MenuCapture, [
                ActionCaptureDelay.Delay0, ActionCaptureDelay.Delay1, ActionCaptureDelay.Delay2, ActionCaptureDelay.Delay5, ActionCaptureDelay.Delay9,
                ActionCapture.HideEditor, ActionCapture.CaptureCursor, ActionCapture.ToInPlace, ActionCapture.ToEditor, ActionCapture.ToClipboard])
            .addCommands(func()->string => appStrings().ui_MenuFile, [
                ActionFile.NewImage, ActionFile.NewFromClipboard, ActionFile.OpenImage, ActionFile.SaveAsImage,
                ActionFile.SaveAsLinkedImage, ActionFile.UpdateLinkedImage, ActionFile.UnlinkImage,
                ActionFile.DupCapture, ActionFile.RenameCapture, ActionFile.DeleteCapture,
                ActionFile.CaptureFileLocation, ActionFile.LinkedFileLocation, ActionFile.FileDetails])
            .addCommands(func()->string => appStrings().ui_MenuEdit, [
                ActionUndo.DoUndo, ActionUndo.DoRedo, ActionCopyPaste.Copy, ActionCopyPaste.Cut, ActionCopyPaste.Paste,
                ActionCopyPaste.Duplicate, ActionSelection.DeleteSelection, ActionEdit.EditText,
                ActionEdit.Bold, ActionEdit.Italic, ActionEdit.ResetSteps,
                ActionCopyPaste.PasteImageInside, ActionEdit.ClearImageInside,
                ActionSelection.SelectAll, ActionSelection.SelectSameAll, ActionSelection.DeSelectAll, ActionSelection.InvertSelection,
                ActionGroup.Group, ActionGroup.Ungroup, ActionEdit.ResetRotation, ActionSelection.Freeze, ActionSelection.Snap,
                ActionPixSel.Fill, ActionPixSel.SmartFill, ActionPixSel.Clear, ActionPixSel.SmartMove])
            .addCommands(func()->string => appStrings().ui_MenuAlign, [
                ActionAlign.AlignLeft, ActionAlign.AlignCenter, ActionAlign.AlignRight,
                ActionAlign.AlignTop, ActionAlign.AlignMiddle, ActionAlign.AlignBottom])
            .addCommands(func()->string => appStrings().ui_MenuArrange, [
                ActionAlign.SendToFront, ActionAlign.SendToBack, ActionAlign.MoveForward, ActionAlign.MoveBackward])
            .addCommands(func()->string => appStrings().ui_MenuImage, [
                ActionCopyPaste.CopyAsImage, ActionImage.RestoreOrg, ActionImage.ResizeImage, ActionImage.ExpandImage,
                ActionImage.ExpandCapture, ActionImage.TrimCapture, ActionFlatten.Flatten, ActionFlatten.FlattenAll,
                ActionImage.FlipImage, ActionImage.MirrorImage, ActionImage.RotateImageRight, ActionImage.RotateImageLeft])
            .addCommands(func()->string => appStrings().lens_Tools, [
                ActionToolMode.Selection, ActionToolMode.Shape, ActionToolMode.Arrow, ActionToolMode.Line, ActionToolMode.Poly,
                ActionToolMode.Text, ActionToolMode.Callout, ActionToolMode.Draw, ActionToolMode.Highlight, ActionToolMode.Step,
                ActionToolMode.Img, ActionToolMode.PixSel, ActionToolMode.Favorites, ActionQuickStyle.Reset])
            .addCommands(func()->string => appStrings().ui_MenuView, [
                ActionView.Inspector, ActionView.Recent, ActionZoom.ZoomIn, ActionZoom.ZoomOut, ActionZoom.Zoom1, ActionZoom.ZoomFit,
                ActionRecentSize.RecentSmall, ActionRecentSize.RecentMedium, ActionRecentSize.RecentBig, ActionView.Clip])
            .addCommands(func()->string => appStrings().act_Library, [ActionGlobal.ShowLibrary])
            .addCommands(func()->string => strings().lens_Application, [ActionOptions.Options, ActionGlobal.Minimize, ActionGlobal.Exit])
        }

        .appearanceButton.addToLens(.lens)
    }

    // Keeps the capture and output actions in stable positions while a selection changes.
    mtd describeLensContext(results: *Lens.Results)
    {
        if .libraryMode
        {
            .libWnd.describeLensRest(results)
            return
        }

        let capture = results.addSection(appStrings().ui_MenuCapture)
        .lens.addCommandRows(capture, [ActionCapture.Area, ActionCapture.LastArea, ActionFile.OpenImage, ActionGlobal.ShowLibrary])

        let image = results.addSection(appStrings().ui_MenuImage)
        .lens.addCommandRows(image, [ActionFile.SaveAsImage, ActionCopyPaste.CopyAsImage])

        let selection = results.addSection(appStrings().lens_Selection)
        .lens.addCommandRows(selection,
                             [ActionEdit.EditText, ActionCopyPaste.Duplicate, ActionCopyPaste.Copy, ActionSelection.DeleteSelection,
                              ActionAlign.SendToFront, ActionAlign.SendToBack, ActionGroup.Group, ActionGroup.Ungroup, ActionEdit.ResetRotation],
                             enabledOnly: true)
    }

    // Answers the lens with the recent captures whose name matches the query, as a strip of
    // pictures closing the results, then the way to the library.
    mtd describeRecentCaptures(results: *Lens.Results)
    {
        if .recentWnd == null or .libraryMode do
            return

        let view = .recentWnd.recentView
        var section: *Lens.Section?
        for item, index in view.items
        {
            if section and section.pictures.count == MaxLensRecents do
                break
            let name = Path.fileName(item!.file) orelse ""
            if results.query.count and not Lens.match(results.query, name).matched do
                continue
            if not section do
                section = results.addSection(appStrings().lens_Recent)
            with let picture = section.addPicture(name)
            {
                .run   = func|main = me, index|() { main.openRecent(index) }
                .paint = func|item = unwrap item|(painter, rect) { paintLensRecent(painter, rect, item.preview) }
            }
        }

        if section do
            section.setLink(appStrings().lens_LibraryLink, func|main = me|() { main.postCommandEvent(ActionGlobal.ShowLibrary) })
    }

    // Opens the recent capture `index` in the editor, leaving the library if it is on screen.
    mtd openRecent(index: u64)
    {
        if .libraryMode do
            .swapLibraryMode()
        .recentWnd.recentView.select(index)
        .updateState()
    }

    // The strip of recent captures, shown on demand at the foot of the window. Its preview size
    // is a View choice of the lens; its captures are also lens entries.
    mtd createRecentBar()
    {
        let gutter = .themeMetrics().panel_GutterSize
        with .recentBar = Wnd.create'Wnd(me, {0, 0, 0, 136})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .Window
            .padding         = Math.Vector4{gutter, gutter, gutter, gutter}
            .wndFlags.add(.Hidden)
        }

        with .recentWnd = RecentWnd.create(me.recentBar, me)
        {
            .dockStyle = .Center
        }
    }

    // Shows or hides the strip of recent captures. Shown, it opens to its height as a panel
    // changing the layout does; hidden, the work takes the room back at once.
    mtd showRecentBar(show: bool)
    {
        .showRecent = show
        let visible = show and not .libraryMode
        if visible and not .recentBar.isLocallyVisible()
        {
            .recentBar.resize(.recentBar.position.width, 0)
            .recentBar.show()
            .applyLayout()
            discard .app().animator.animateLayoutHeight(.recentBar, .bottomHeight())
            return
        }

        .recentBar.show(visible)
        .applyLayout()
    }

    // The appearance owner of the application: the theme and the language it applies and
    // persists, and About. Its choices are lens entries, so its caption button stays hidden.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(unwrap .surface, "capture.appearance")
        {
            .hide()
            .sigThemeChanged += func|main = me|(button)
            {
                main.editorOptions.theme = button.appearanceTheme
                main.editWnd.getCapture()?.invalidateAllFormCaches()
                main.saveAppState()
            }

            .sigLanguageChanged += func|main = me|(button)
            {
                if button.language.isEmpty() do
                    main.editorOptions.language = .System
                elif button.language == "fr" do
                    main.editorOptions.language = .French
                else do
                    main.editorOptions.language = .English
                main.saveAppState()
            }

            .sigAboutRequested += func|main = me|(_)
            {
                main.postCommandEvent(ActionAbout.About)
            }
        }
    }
}
