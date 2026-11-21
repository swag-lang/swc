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

        .updateCommandState()
        .refreshTextControls()
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

    // Returns the colour the mini-bar swatch stands for on the selected form: what fills a text,
    // a callout, a step or a filled shape, and the stroke of every other form.
    mtd swatchField()->{type: typeinfo, name: string}
    {
        switch .main.getCapture()?.getSelectedFormType()
        {
        case FormText, FormCallout, FormStep:
            return {BaseForm, #nameof(BaseForm.backColor)}

        // A filled shape is seen by its fill, an outlined one by its outline.
        case FormShape, FormPolygon:
            let form = .main.getCapture()?.getSelectedBaseForm()
            if form and form.subKind != .PixSel and form.backColor.a do
                return {BaseForm, #nameof(BaseForm.backColor)}
        }

        return {BaseForm, #nameof(BaseForm.borderColor)}
    }

    // Returns the colour of the mini-bar swatch.
    mtd swatchColor()->Color
    {
        let form = .main.getCapture()?.getSelectedBaseForm()
        if not form do
            return Argb.Black
        return .swatchField().name == #nameof(BaseForm.backColor) ? form.backColor : form.borderColor
    }

    // Keeps the face and the size in step with the inspector and undo.
    mtd refreshTextControls()
    {
        if .main.libraryMode do
            return
        let style = .main.selectedTextStyle()
        if not style.found do
            return
        let defaultFace = .theme().res.defaultTypeFaceR.familyName()
        let shown       = style.face.count ? style.face : defaultFace
        .faceButton?.setText(shown)
        if .faceButton do
            .faceButton.toolTip = Format.toString("%: %", appStrings().prop_Font, shown)
        .sizeButton?.setText(Format.toString("%", cast(s32, Math.round(style.size))))
    }

    // Fills the bar with what applies to a selection of `kind`.
    mtd rebuild(kind: MiniBarKind)
    {
        .faceButton = null
        .sizeButton = null
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
                    let popover = ColorPopover.open(assume cast(*IconButton, button), appStrings().ui_PropColor, bar.swatchColor(), &main.recentColors)
                    popover.hangFrom(button, main.selectionSurfaceRect())
                    popover.sigColorChanged += func|bar, main, button, var first = true|(pop)
                    {
                        let field = bar.swatchField()
                        main.propWnd.pushTypedValue(pop.color.argb, field.type, field.name, first, true)
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
    }

    // Adds the current text face as a quiet popup trigger, level with the size beside it.
    mtd addTextFace()
    {
        let style = .main.selectedTextStyle()
        if not style.found do
            return

        let capture      = unwrap .main.getCapture()
        let selectedForm = capture.selection.back()
        let metrics     = .themeMetrics()
        let defaultFace = .theme().res.defaultTypeFaceR.familyName()
        let shown       = style.face.count ? style.face : defaultFace
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
        let style   = .main.selectedTextStyle()
        let capture      = unwrap .main.getCapture()
        let selectedForm = capture.selection.back()
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFontFs(metrics.defaultFontSize)
        let width   = Math.ceil(Painter.measureString("150", font).width + metrics.miniBar_ButtonSize)
        with .sizeButton = IconButton.createQuiet(me)
        {
            .toolTip = appStrings().prop_Size
            .updateFlags(add: .Popup)
            .setText(Format.toString("%", cast(s32, Math.round(style.size))))
            .resize(width, metrics.miniBar_ButtonSize)
            .sigPopupRequested += func|bar = me, main = me.main, selectedForm|(button) { bar.choicePopover = TextChoicePopover.open(main, assume cast(*IconButton, button), .Size, selectedForm) }
            .sigPopupClosed    += func|bar = me|(_) { bar.choicePopover = null }
        }

        .addItem(.sizeButton)
    }

    // Adds bold and italic to the mini-bar: two letters, set in the style they turn on, lit when on.
    mtd addTextStyle()
    {
        let style = .main.selectedTextStyle()
        if not style.found do
            return

        let size      = .themeMetrics().defaultFontSize
        with let bold = .addButton({}, toolTip: appStrings().prop_StyleBold, flags: .Toggle)
        {
            .updateFlags(add: .CenterContent, remove: .IconOnly)
            .setText("B")
            .setCheckIndicator(.Ink)
            .style.setFont(.theme().createDefaultFont(size, .Bold), .Regular)
            .setChecked(style.style == .Bold or style.style == .BoldItalic)
            .sigPressed += func|main = me.main|(_) { main.postCommandEvent(ActionEdit.Bold) }
        }

        with let italic = .addButton({}, toolTip: appStrings().prop_StyleItalic, flags: .Toggle)
        {
            .updateFlags(add: .CenterContent, remove: .IconOnly)
            .setText("I")
            .setCheckIndicator(.Ink)
            .style.setFont(.theme().createDefaultFont(size, .Italic), .Regular)
            .setChecked(style.style == .Italic or style.style == .BoldItalic)
            .sigPressed += func|main = me.main|(_) { main.postCommandEvent(ActionEdit.Italic) }
        }
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
        let size = .themeMetrics().menuPopup_IconSize
        for vertical in [false, true]
        {
            if vertical do
                .addSeparator()
            for align, i in Aligns
            {
                let glyph       = vertical ? Down[i] : Across[i]
                let tip         = vertical ? appStrings().ui_AnchorVertical : appStrings().ui_Anchor
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
            with let button = .addButton({}, toolTip: appStrings().act_Shape, flags: .Radio)
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

        with let stepper = Stepper.create(me, {0, 0, StepperWidth, 0})
        {
            .setRange(1, 999)
            .setValue(cast(s64, step.index))
            .sigChanged += func|main = me.main|(wnd)
            {
                let value = (assume cast(*Stepper, wnd)).value
                main.propWnd.pushTypedValue(cast(u32, value), FormStep, #nameof(FormStep.index), true)
            }
        }

        .addItem(stepper)
    }
}
