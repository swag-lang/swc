// Width of the step number on the mini-bar.
const StepperWidth = 88.0

// What the mini-bar beside the selection carries: nothing without a selection, the colour of one
// object, the face of a text, the counter of a step, or the alignment of several objects.
enum MiniBarKind { None, Single, Text, Step, Multi }

// The alignment a glyph of the text mini-bar stands for, and whether it is down the box rather
// than across it, kept in the user data of the glyph.
func alignUserData(align: FormTextAlign, vertical: bool)->*void => cast(*void, cast(u64, align) + (vertical ? AlignVerticalFlag : 0))

func alignOfUserData(data: *void?)->FormTextAlign
{
    switch cast(u64, data) & ~AlignVerticalFlag
    {
    case cast(u64, FormTextAlign.LeftTop):     return .LeftTop
    case cast(u64, FormTextAlign.RightBottom): return .RightBottom
    case cast(u64, FormTextAlign.Center):      return .Center
    default: return .Center
    }
}

func alignIsVertical(data: *void?)->bool => (cast(u64, data) & AlignVerticalFlag) != 0
const AlignVerticalFlag = 0x100'u64

// The bar that stands next to the selection, carrying what applies to it. Every button is also a
// lens entry: the bar only brings the commands of the selection next to it.
//
// The bar fills itself from the selection of its main window; the window places it beside the
// selection, clear of its other floating parts (see `MainWnd.placeMiniBar`).
struct SelectionBar
{
    using miniBar: MiniBar
    late main:     *MainWnd

    shownKind:     MiniBarKind = .None     // The kind of selection the bar was last filled for.
    shownForm:     *BaseForm?              // The form the bar was filled for, whose face, size and style it shows.
    faceButton:    *IconButton?            // Current text face, opened as a filtered choice popup.
    sizeButton:    *IconButton?            // Current text size, opened through the same choice popup.
    stepNumber:    *Stepper?
    choicePopover: *TextChoicePopover?     // Open face or size list, if any.
}

impl SelectionBar
{
    // Creates the empty, hidden bar of `main` over `parent`.
    func create(main: *MainWnd, parent: *Wnd)->*SelectionBar
    {
        with let result = Wnd.create'SelectionBar(parent)
        {
            .main = main
            .backgroundStyle = .Transparent
            .wndFlags.add(.Hidden)
        }

        return result
    }

    // Fills the bar again when the kind of the selection or its form changed, and keeps its
    // commands and text controls in step.
    mtd refresh()
    {
        // The bar shows the face, the size and the style of its form: another form fills it again.
        let kind = .selectionKind()
        let form = kind == .None or kind == .Multi ? null : .main.getCapture()?.getSelectedBaseForm()
        if kind != .shownKind or form != .shownForm
        {
            .shownKind = kind
            .shownForm = form
            .rebuild(kind)
        }

        .refreshControls()
    }

    // Returns the kind of mini-bar the selection calls for.
    mtd selectionKind()->MiniBarKind
    {
        let capture = .main.getCapture()
        if .main.libraryMode or .main.inPlaceEdit or not capture or capture.selection.isEmpty() do
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

    // Shares the inspector's colour roles, including the fill ink of a pixel selection.
    mtd swatchSlot()->ColorSlot
    {
        let form = unwrap .main.getCapture()!.getSelectedBaseForm()
        if form.subKind == .PixSel do
            return .Fill

        switch .main.getCapture()!.getSelectedFormType()
        {
        case FormText, FormCallout, FormStep:
            return .Fill

        case FormShape, FormPolygon:
            if form.backColor.a do
                return .Fill
        }

        return .Border
    }

    mtd swatchColor()->Color => .main.propWnd.slotColor(.swatchSlot())

    // Updates controls in place so undo and inspector edits preserve the current keyboard stop.
    mtd refreshControls()
    {
        .updateCommandState()
        if .shownKind == .Text
        {
            let style = .main.selectedTextStyle()
            if not style.found do
                return

            let defaultFace = .theme().res.defaultTypeFaceR.familyName()
            let shown       = style.face.count ? style.face : defaultFace
            .faceButton?.setText(shown)
            if .faceButton do
                .faceButton.toolTip = Format.toString("%: %", appStrings().prop_Font, shown)
            .sizeButton?.setText(Format.toString("%", cast(s32, Math.round(style.size))))

            for item in .items
            {
                if item.wnd is IconButton as button where button.flags.has(.Radio)
                {
                    let align = alignIsVertical(button.userData) ? style.alignVert : style.align
                    button.setChecked(alignOfUserData(button.userData) == align)
                }
            }
        }
        elif .shownKind == .Step
        {
            let form = .main.getCapture()?.getSelectedBaseForm()
            if form is FormStep as step
            {
                .stepNumber?.setValue(cast(s64, step.index))
                for item in .items
                {
                    if item.wnd is IconButton as button where button.flags.has(.Radio) do
                        button.setChecked(enumFromUserData'FormShapeKind(button.userData) == step.kind)
                }
            }
        }

        .invalidate()
    }

    // Fills the bar with what applies to a selection of `kind`.
    mtd rebuild(kind: MiniBarKind)
    {
        .faceButton = null
        .sizeButton = null
        .stepNumber = null
        .clear()
        if kind == .None do
            return

        let theme = .theme()
        let size  = .themeMetrics().menuPopup_IconSize
        if kind == .Multi
        {
            .addButton(.main.icon(.TextAlignLeft, size), ActionAlign.AlignLeft, appStrings().act_AlignLeft)
            .addButton(.main.icon(.TextAlignCenter, size), ActionAlign.AlignCenter, appStrings().act_AlignCenter)
            .addButton(.main.icon(.TextAlignRight, size), ActionAlign.AlignRight, appStrings().act_AlignRight)
            .addButton(.main.icon(.AlignTop, size), ActionAlign.AlignTop, appStrings().act_AlignTop)
            .addButton(.main.icon(.AlignMiddle, size), ActionAlign.AlignMiddle, appStrings().act_AlignMiddle)
            .addButton(.main.icon(.AlignBottom, size), ActionAlign.AlignBottom, appStrings().act_AlignBottom)
            .addSeparator()
            .addTextButton(appStrings().act_Group, ActionGroup.Group)
        }
        else
        {
            with let swatch = .addButton({}, toolTip: appStrings().ui_PropColor, flags: .Popup)
            {
                .setArrowPosition(.None)
                .iconPainter = func|bar = me|(btn, bc, pos, _)
                {
                    let radius = btn.themeMetrics().menuPopup_IconSize * 0.5
                    bc.painter.setParams(.Antialiased)
                    bc.painter.fillCircle(pos.horzCenter(), pos.vertCenter(), radius, bar.swatchColor())
                    bc.painter.drawCircle(pos.horzCenter(), pos.vertCenter(), radius, btn.themeColors().strongLine, 1)
                }

                .sigPopupRequested += func|bar = me, main = me.main|(button)
                {
                    let slot    = bar.swatchSlot()
                    let popover = ColorPopover.open(assume cast(*IconButton, button),
                                                    appStrings().ui_PropColor,
                                                    main.propWnd.slotColor(slot),
                                                    &main.recentColors)
                    popover.hangFrom(button, main.selectionSurfaceRect())
                    popover.sigColorChanged += func|main, button, slot, var first = true|(pop)
                    {
                        main.propWnd.setSlotColor(slot, pop.color, first)
                        first = false
                        button.invalidate()
                    }
                }
            }

            if kind == .Text
            {
                .addSeparator()
                .addTextFace()
                .addTextSize()
                .addSeparator()
                .addTextStyle()
                .addSeparator()
                .addTextAlignment()
            }
            elif kind == .Step
            {
                .addSeparator()
                .addStepKinds()
                .addSeparator()
                .addStepNumber()
                .addSeparator()
                .addTextButton(appStrings().ui_ResetSteps).sigPressed += func|main = me.main|(_) { main.postCommandEvent(ActionEdit.ResetSteps) }
            }
        }

        .addSeparator()
        .addButton(theme.icon(.Remove, size), ActionSelection.DeleteSelection, appStrings().act_Delete)

        if kind == .Text
        {
            let more = .addButton(theme.icon(.More, size), toolTip: appStrings().tip_SelectionActions)
            more.sigPressed += func|main = me.main|(button)
            {
                let menu = MenuCtrl.createPopup(main)
                menu.addItem(ActionEdit.EditText)
                menu.addItem(ActionCopyPaste.Duplicate)
                menu.addItem(ActionCopyPaste.Copy)
                menu.addItem(ActionCopyPaste.Cut)
                menu.addSeparator()
                menu.addItem(ActionEdit.ResetRotation)
                discard menu.doModal(assume cast(*IconButton, button), autoDestroy: true)
            }
        }
    }

    // Adds the current text face as a quiet popup trigger, level with the size beside it.
    mtd addTextFace()
    {
        let style = .main.selectedTextStyle()
        if not style.found do
            return

        let capture      = unwrap .main.getCapture()
        let selectedForm = capture.selection.back()
        let metrics      = .themeMetrics()
        let defaultFace  = .theme().res.defaultTypeFaceR.familyName()
        let shown        = style.face.count ? style.face : defaultFace
        with .faceButton = IconButton.createQuiet(me)
        {
            .toolTip = Format.toString("%: %", appStrings().prop_Font, shown)
            .updateFlags(add: .Popup)
            .setText(shown)
            .resize(112, metrics.miniBar_ButtonSize)
            .sigPopupRequested += func|bar = me, main = me.main, selectedForm|(button) { bar.choicePopover = TextChoicePopover.open(main, assume cast(*IconButton, button), .Face, selectedForm) }
            .sigPopupClosed    += func|bar = me|(_) { bar.choicePopover = null }
        }

        .addItem(.faceButton)
    }

    // The size uses the same trigger and popup as the face. Exact values stay in the inspector.
    mtd addTextSize()
    {
        let style        = .main.selectedTextStyle()
        let capture      = unwrap .main.getCapture()
        let selectedForm = capture.selection.back()
        let metrics      = .themeMetrics()
        let font         = .theme().createDefaultFontFs(metrics.defaultFontSize)
        let width        = Math.ceil(Painter.measureString("150", font).width + metrics.miniBar_ButtonSize)
        with .sizeButton = IconButton.createQuiet(me)
        {
            .toolTip = appStrings().prop_Size
            .updateFlags(add: .Popup)
            .setText(Format.toString("%", cast(s32, Math.round(style.size))))
            .style.setFont(font, .Regular)
            .resize(width, metrics.miniBar_ButtonSize)
            .sigPopupRequested += func|bar = me, main = me.main, selectedForm|(button) { bar.choicePopover = TextChoicePopover.open(main, assume cast(*IconButton, button), .Size, selectedForm) }
            .sigPopupClosed    += func|bar = me|(_) { bar.choicePopover = null }
        }

        .addItem(.sizeButton)
    }

    // The typography toggles share their glyph and checked state with the lens.
    mtd addTextStyle()
    {
        .addButton(.main.icon(.Bold), ActionEdit.Bold, appStrings().prop_StyleBold, flags: .Toggle)
        .addButton(.main.icon(.Italic), ActionEdit.Italic, appStrings().prop_StyleItalic, flags: .Toggle)
    }

    // Adds the three horizontal alignments of the text to the mini-bar, the one in force checked.
    mtd addTextAlignment()
    {
        let style = .main.selectedTextStyle()
        if not style.found do
            return

        // How the lines stand across the box, then down it: two groups of three glyphs.
        const Aligns = [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]
        const Across = [CaptureIcons.TextAlignLeft, CaptureIcons.TextAlignCenter, CaptureIcons.TextAlignRight]
        const Down   = [CaptureIcons.AlignTop, CaptureIcons.AlignMiddle, CaptureIcons.AlignBottom]
        let texts      = appStrings()
        let acrossTips = [texts.act_AlignLeft, texts.act_AlignCenter, texts.act_AlignRight]
        let downTips   = [texts.act_AlignTop, texts.act_AlignMiddle, texts.act_AlignBottom]
        let size       = .themeMetrics().menuPopup_IconSize
        for vertical in [false, true]
        {
            if vertical do
                .addSeparator()
            for align, i in Aligns
            {
                let glyph       = vertical ? Down[i] : Across[i]
                let tip         = vertical ? downTips[i] : acrossTips[i]
                with let button = .addButton(.main.icon(glyph, size), toolTip: tip, flags: .Radio)
                {
                    .userData = alignUserData(align, vertical)
                    .setChecked((vertical ? style.alignVert : style.align) == align)
                    .sigPressed += func|bar = me, main = me.main, type = style.type, vertical|(btn)
                    {
                        let field = vertical ? #nameof(FormText.alignVert) : #nameof(FormText.alignHorz)
                        main.propWnd.pushTypedValue(cast(u32, alignOfUserData(btn.userData)), type, field, true)
                        for item in bar.items
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
        let found = catch cast(*FormStep?, .main.getCapture()?.getSelectedBaseForm()) orelse null
        if not found do
            return
        let current = found.kind
        for kind in FormShapeKind
        {
            with let button = .addButton({}, toolTip: shapeChoiceName(kind), flags: .Radio)
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
            button.sigPressed += func|bar = me, main = me.main|(btn)
            {
                main.propWnd.pushTypedValue(cast(u32, enumFromUserData'FormShapeKind(btn.userData)), FormStep, #nameof(FormStep.kind), true)
                for item in bar.items
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
        let found = catch cast(*FormStep?, .main.getCapture()?.getSelectedBaseForm()) orelse null
        if not found do
            return
        let step = found

        with .stepNumber = Stepper.create(me, {0, 0, StepperWidth, 0})
        {
            .setRange(1, 999)
            .setValue(cast(s64, step.index))
            .sigChanged += func|main = me.main|(wnd)
            {
                let value = (assume cast(*Stepper, wnd)).value
                main.propWnd.pushTypedValue(cast(u32, value), FormStep, #nameof(FormStep.index), true)
            }
        }

        .addItem(.stepNumber)
    }
}
