// Width of the step number on the mini-bar.
const StepperWidth = 88.0

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

        .dock.addTool(.icon(.Select, glyph), ActionToolMode.Selection)
        .dock.addTool(.icon(.Shape, glyph), ActionToolMode.Shape)
        .dock.addTool(.icon(.Arrow, glyph), ActionToolMode.Arrow)
        .dock.addTool(.icon(.Line, glyph), ActionToolMode.Line)
        .dock.addTool(.icon(.Polygon, glyph), ActionToolMode.Poly)
        .dock.addTool(.icon(.Text, glyph), ActionToolMode.Text)

        // The callout has no sprite of its own: its cell draws the bubble.
        let callout = .dock.addTool(.icon(.Text, glyph), ActionToolMode.Callout)
        callout.iconPainter = func(btn, bc, pos, flags) { drawCalloutGlyph(btn, bc, pos, flags) }

        .dock.addTool(.icon(.Draw, glyph), ActionToolMode.Draw)
        .dock.addTool(.icon(.Highlight, glyph), ActionToolMode.Highlight)
        .dock.addTool(.icon(.Step, glyph), ActionToolMode.Step)
        .dock.addTool(.icon(.Image, glyph), ActionToolMode.Img)
        .dock.addTool(.icon(.PixSel, glyph), ActionToolMode.PixSel)
        .dock.addTool(.icon(.Favorites, glyph), ActionToolMode.Favorites)
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
        case FormStep:              return .Step
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

        let kind = .miniBarKindOfSelection()
        if kind != .miniBarKind
        {
            .miniBarKind = kind
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
                .miniBar.addTextButton(appStrings().prop_StyleBold, ActionEdit.Bold)
                .miniBar.addTextButton(appStrings().prop_StyleItalic, ActionEdit.Italic)
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

    // Returns the face, the size and the horizontal alignment of the selected text or callout.
    mtd selectedTextStyle()->{found: bool, type: typeinfo, face: string, size: f32, align: FormTextAlign}
    {
        switch .getCapture()?.getSelectedBaseForm()
        {
        case FormText as text:       return {true, FormText, text.fontName.toString(), text.fontSize, text.alignHorz}
        case FormCallout as callout: return {true, FormCallout, callout.fontName.toString(), callout.fontSize, callout.alignHorz}
        }

        return {false, FormText, "", 0, .Center}
    }

    // Adds the face of the text and its size to the mini-bar: the face opens the properties,
    // where every face is listed; the size is a stepper.
    mtd addTextFace()
    {
        let style = .selectedTextStyle()
        if not style.found do
            return

        let name = style.face.count ? style.face : appStrings().prop_Font
        .miniBar.addTextButton(name).sigPressed += func|main = me|(_) { main.inspector.setFolded(false) }

        with let stepper = Stepper.create(.miniBar, {0, 0, StepperWidth, 0})
        {
            .setRange(cast(s64, MinFontSize), cast(s64, MaxFontSize))
            .setValue(cast(s64, Math.round(style.size)))
            .sigChanged += func|main = me, type = style.type|(wnd)
            {
                let value = cast(f32, (assume cast(*Stepper, wnd)).value)
                main.propWnd.pushTypedValue(cast #bit (u32, value), type, #nameof(FormText.fontSize), true)
            }
        }

        .miniBar.addItem(stepper)
    }

    // Adds the three horizontal alignments of the text to the mini-bar, the one in force checked.
    mtd addTextAlignment()
    {
        let style = .selectedTextStyle()
        if not style.found do
            return

        const Aligns = [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]
        const Glyphs = [CaptureIcons.TextAlignLeft, CaptureIcons.TextAlignCenter, CaptureIcons.TextAlignRight]
        let size = .themeMetrics().menuPopup_IconSize
        for align, i in Aligns
        {
            with let button = .miniBar.addButton(.icon(Glyphs[i], size), toolTip: appStrings().ui_Anchor, flags: .Radio)
            {
                .userData = enumToUserData(align)
                .setChecked(style.align == align)
                .sigPressed += func|main = me, type = style.type|(btn)
                {
                    main.propWnd.pushTypedValue(cast(u32, enumFromUserData'FormTextAlign(btn.userData)), type, #nameof(FormText.alignHorz), true)
                    for item in main.miniBar.items
                    {
                        if item.wnd is IconButton as other where other.flags.has(.Radio) do
                            other.setChecked(other == btn)
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
        .miniBar.showNear(rect)
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
        .hintLine.clearHints()
        if .editWnd != null and .editWnd.editView.textForm
        {
            .hintLine.addHint("", appStrings().hint_CalloutTail)
            .hintLine.addHint(strings().key_Escape, appStrings().hint_EndText)
            return
        }

        let tool = .toolHint()
        if not tool.isEmpty() do
            .hintLine.addHint("", tool)
        if .inspector != null and .inspector.folded do
            .hintLine.addHint(.inspector.foldKey, appStrings().hint_AllProperties)
        .hintLine.addHint(strings().key_Space, appStrings().hint_Space)
    }

    // Returns what the tool in hand does, in a few words.
    mtd toolHint()->String
    {
        let texts = appStrings()
        switch #complete .editMode
        {
        case .Selection: return texts.hint_ToolSelect
        case .Shape:     return texts.hint_ToolShape
        case .Arrow:     return texts.hint_ToolArrow
        case .Line:      return texts.hint_ToolLine
        case .Polygon:   return texts.hint_ToolPolygon
        case .Text:      return texts.hint_ToolText
        case .Callout:   return texts.hint_ToolCallout
        case .Draw:      return texts.hint_ToolDraw
        case .Highlight: return texts.hint_ToolHighlight
        case .Image:     return texts.hint_ToolImage
        case .PixSel:    return texts.hint_ToolPixSel
        case .Favorites: return texts.hint_ToolFavorites
        case .Step:
            let capture = .getCapture()
            return Format.toString(texts.hint_ToolStep, capture ? capture.nextStepIndex : 1)
        }
    }

    // The one door: every command of the application, the recent captures, the theme, the
    // language and About. At rest it offers what can be done here and now: the actions of the
    // selection, or the captures when nothing is selected, then the image and the recent captures.
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

    // Offers, at rest, the actions of what is in hand: the selection's when shapes are selected,
    // the captures otherwise, then the image's.
    mtd describeLensContext(results: *Lens.Results)
    {
        if .libraryMode
        {
            .libWnd.describeLens(results)
            return
        }

        let selection = results.addSection(appStrings().lens_Selection)
        .lens.addCommandRows(selection, [
            ActionEdit.EditText, ActionCopyPaste.Duplicate, ActionCopyPaste.Copy, ActionSelection.DeleteSelection,
            ActionAlign.SendToFront, ActionAlign.SendToBack, ActionGroup.Group, ActionGroup.Ungroup, ActionEdit.ResetRotation], enabledOnly: true)

        if selection.entries.isEmpty()
        {
            let capture = results.addSection(appStrings().ui_MenuCapture)
            .lens.addCommandRows(capture, [ActionCapture.Area, ActionCapture.LastArea, ActionCapture.FullScreen, ActionFile.OpenImage], enabledOnly: true)
        }

        let image = results.addSection(appStrings().ui_MenuImage)
        .lens.addCommandRows(image, [ActionFile.SaveAsImage, ActionCopyPaste.CopyAsImage, ActionImage.ResizeImage], enabledOnly: true)
    }

    // Answers the lens with the recent captures whose name matches the query.
    mtd describeRecentCaptures(results: *Lens.Results)
    {
        if .recentWnd == null do
            return

        let view = .recentWnd.recentView
        var section: *Lens.Section?
        for item, index in view.items
        {
            let name = Path.fileName(item!.file) orelse ""
            if not Lens.match(results.query, name).matched do
                continue
            if not section do
                section = results.addSection(appStrings().lens_Recent)
            with let entry = section.addEntry(name)
            {
                .glyph = me.icon(.Image, me.themeMetrics().menuPopup_IconSize)
                .run   = func|main = me, index|() { main.openRecent(index) }
                if index == view.selected do
                    .detail = "✓"
            }
        }
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
