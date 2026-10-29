// Typing the words of a form in place, on the canvas: a text, a callout, the label of a step.
//
// A double click on the form, or Enter or F2 on the selected form, lays its words out as fields
// over it, one per line, in the face, the size, the ink and the alignment the form sets them in,
// while the form leaves its words to them. A rotated form straightens while its words are typed,
// and turns back when they are kept or let go. Escape lets them go; Ctrl+Enter or a click
// elsewhere keeps them, as one step of the history. Enter starts a new line, except on a step,
// whose label is one word and which Enter keeps.

// The smallest size the words take while they are typed, whatever the zoom.
const MinInlineFontSize = 8.0

// The highest number a step takes, as the stepper of the mini-bar allows.
const MaxInlineStepNumber = 999

// What a form gives the fields its words are typed in.
struct InlineText
{
    rect:      Math.Rectangle              // Where the words stand, in capture pixels.
    text:      String                      // The words, lines separated by a line feed.
    face:      *TypeFace?                  // The face they are set in.
    size:      f32                         // Their size, in capture pixels.
    spacing:   f32                         // The room between two lines, in capture pixels.
    ink:       Color                       // Their ink.
    alignHorz: FormTextAlign = .Center     // How each line stands across the rectangle.
    alignVert: FormTextAlign = .Center     // How the lines stand down the rectangle.
    step:      bool                        // Whether the words are the label of a step.
    stepType:  FormStepType                // How that step counts.
}

// Returns what `form` gives the fields its words are typed in; `found` is false for a form
// without words.
func inlineTextOf(form: IForm)->{ found: bool, spec: InlineText }
{
    var spec: InlineText
    switch form
    {
    case FormText as text:
        let scale = Math.map(text.scale, 0, 100, 1'f32, 2'f32)
        spec.rect = text.rectFormBound()
        spec.rect.inflate(-text.borderSize * 0.5)
        spec.rect.inflate(-(text.borderSize + text.boldSize) * scale, 0)
        spec.text      = text.text
        spec.face      = text.resolveFace()
        spec.size      = text.fontSize * scale
        spec.spacing   = text.lineSpacing * scale
        spec.ink       = text.backColor
        spec.alignHorz = text.alignHorz
        spec.alignVert = text.alignVert
        return {true, spec}

    case FormCallout as callout:
        spec.rect = callout.textRect()
        spec.rect.inflate(-callout.boldSize, 0)
        spec.text      = callout.text
        spec.face      = callout.render.resolveFace()
        spec.size      = callout.fontSize
        spec.spacing   = callout.lineSpacing
        spec.ink       = callout.textColor
        spec.alignHorz = callout.alignHorz
        spec.alignVert = callout.alignVert
        return {true, spec}

    case FormStep as step:
        spec.rect     = step.rectFormBound()
        spec.text     = stepLabel(step.typeIndex, step.index)
        spec.face     = g_App.theme.res.defaultTypeFaceR
        spec.size     = Math.max(cast(f32, Math.min(step.w, step.h)) * 0.6, 8)
        spec.ink      = step.borderColor
        spec.step     = true
        spec.stepType = step.typeIndex
        return {true, spec}
    }

    return {false, spec}
}

// Returns the label a step of `type` shows for `index`: its number, or its letter.
func stepLabel(type: FormStepType, index: u32)->String
{
    switch #complete type
    {
    case .Number:     return Format.toString("%", index)
    case .LetterUp:   return Format.toString("%", cast(rune, 'A'rune + (index - 1) % 26))
    case .LetterDown: return Format.toString("%", cast(rune, 'a'rune + (index - 1) % 26))
    }
}

// Returns the index a step of `type` labelled `label` stands for, or 0 when the label names none.
func stepIndexOf(type: FormStepType, label: string)->u32
{
    if type == .Number
    {
        let {value, eat, ovf} = catch StrConv.parseU32(label)
        if ovf or eat != label.count or value < 1 or value > MaxInlineStepNumber do
            return 0
        return value
    }

    if label.count != 1 do
        return 0
    let c = label[0]
    if c >= 'A'u8 and c <= 'Z'u8 do
        return cast(u32, c - 'A'u8) + 1
    if c >= 'a'u8 and c <= 'z'u8 do
        return cast(u32, c - 'a'u8) + 1
    return 0
}

// Tells `form` whether its words are being typed in place: it then leaves them to the fields.
func setEditingText(form: IForm, editing: bool)
{
    switch form
    {
    case FormText as text:       text.editingText = editing
    case FormCallout as callout: callout.editingText = editing
    case FormStep as step:       step.editingText = editing
    }
}

impl EditView
{
    // Whether the words of a form are being typed in place.
    mtd isEditingText()->bool => not .textLines.isEmpty()

    // Returns the form whose words are being typed in place, or null.
    mtd textEditForm()->IForm?
    {
        let capture = .capture
        if not capture or not .textForm do
            return null
        for f in capture.forms where cast(*BaseForm, f) == .textForm do
            return f
        return null
    }

    // Returns the words typed in place so far, lines separated by a line feed.
    mtd inlineText()->String
    {
        var result: #returntype
        for line, i in .textLines
        {
            if i do
                result += "\n"
            result += line.text()
        }

        return result
    }

    // Types the words of `form` in place. Does nothing for a form without words.
    mtd beginTextEdit(form: IForm)
    {
        .endTextEdit()
        let {found, spec} = inlineTextOf(form)
        if not found do
            return

        let capture = unwrap .capture
        let size    = cast(u32, Math.max(spec.size * .zoom, MinInlineFontSize))
        let font    = .theme().createFont(unwrap spec.face, size)
        .textFont.regular, .textFont.bold, .textFont.italic, .textFont.boldItalic = font
        .textSpec = spec
        .textForm = cast(*BaseForm, form)

        for line in Tokenize.split(spec.text, '\n'u8, removeEmpty: false) do
            discard .addTextLine(.textLines.count, line)
        if .textLines.isEmpty() do
            discard .addTextLine(0, "")

        setEditingText(form, true)

        // A rotated form straightens while its words are typed level.
        .textRotate = form.rotate
        if form.canRotate() and not Math.isZeroEpsilon(form.rotate) do
            .turnForm(form, form.rotate, 0)

        .placeTextLines()
        let last = .textLines.back()
        last.setFocus()
        if spec.step do
            last.selectAll()
        else do
            last.setSelection(last.text().count, last.text().count)

        capture.invalidateAllFormCaches()
        .main.fillHintLine()
        .main.placeMiniBar()
        .invalidate()
    }

    // Ends typing the words in place: `keep` makes them the words of the form, as one step of the
    // history; otherwise the form keeps its words. A rotated form turns back to its angle. The
    // canvas takes the keyboard back unless `focus` is false, when the focus is already going
    // elsewhere.
    mtd endTextEdit(keep = true, focus = true)
    {
        if not .isEditingText() do
            return

        let text  = .inlineText()
        let form  = .textEditForm()
        let lines = #move .textLines
        .textForm = null
        for line in lines do
            line.destroy()

        if form
        {
            setEditingText(form, false)
            if form.canRotate() and not Math.isZeroEpsilon(.textRotate) do
                .turnForm(form, form.rotate, .textRotate)
            if keep and text != .textSpec.text do
                .commitText(form, text)
        }

        .capture?.invalidateAllFormCaches()
        .main.fillHintLine()
        .main.placeMiniBar()
        if focus do
            .setFocus()
        .invalidate()
    }

    // Makes `text` the words of `form`, as one step of the history.
    mtd commitText(form: IForm, text: String)
    {
        let capture = unwrap .capture

        // The step of the history applies to the selection, which may already be another one:
        // it is made on this form alone, then the selection comes back.
        var saved = capture.selection
        capture.selection.clear()
        for f, i in capture.forms where cast(*BaseForm, f) == cast(*BaseForm, form) do
            capture.selection.add(i)

        if .textSpec.step
        {
            let index = stepIndexOf(.textSpec.stepType, text)
            if index
            {
                .main.propWnd.pushTypedValue(index, FormStep, #nameof(FormStep.index), true)
                if form is FormStep as step do
                    step.isDirty = true
            }
        }
        else
        {
            let undo = capture.newUndo(.SetText)
            undo.text = text
            capture.pushUndo(undo)
        }

        capture.selection = saved
    }

    // Turns `form` from the angle `from` to the angle `target`, over the time of a quick change of
    // state. The form is found again at each step, so a form gone meanwhile is left alone.
    mtd turnForm(form: IForm, from, target: f32)
    {
        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
        options.easing   = .EaseOut

        let base = cast(*BaseForm, form)
        discard .app().animator.animateF32(me,
                                           AnimationChannel.from("Capture.Text.Turn"),
                                           from,
                                           target,
                                           func|base|(view, value)
                                           {
                                               let capture = view.capture
                                               if not capture do
                                                   return
                                               for f in capture.forms where cast(*BaseForm, f) == base
                                               {
                                                   base.rotate = value
                                                   capture.invalidateAllFormCaches()
                                                   view.invalidate()
                                               }
                                           },
                                           options)
    }

    // Adds a field holding `text` as the line at `index`.
    mtd addTextLine(index: u64, text: string)->*EditBox
    {
        let line = EditBox.create(me, text)
        with line
        {
            .setForm(.Transparent)
            .wndFlags.add(.NoFocusRing)
            .style.setFont(me.textFont)
            .style.addStyleSheetColors(Format.toString("edit_Text 0x%{X08}", me.textSpec.ink.argb))
            if me.textSpec.step
            {
                if me.textSpec.stepType == .Number do
                    .setUnsignedIntegerRange(1, MaxInlineStepNumber)
                else do
                    .setMaximumLength(1)
            }

            .sigTextChanged += func|view = me|(_) { view.placeTextLines() }
            .hookOnEvent    = func|view = me|(wnd, evt)->bool => view.textLineEvent(assume cast(*EditBox, wnd), evt)
        }

        .textLines.insertAt(index, line)
        return line
    }

    // Lays the fields over the words, each as wide as its line and standing where the alignment
    // of the form puts it, so the words do not move when they become editable.
    mtd placeTextLines()
    {
        if not .isEditingText() do
            return

        let place = .getCaptureRect()
        var rect  = .textSpec.rect * .zoom
        rect.offset(place.x - .scrollPos.x, place.y - .scrollPos.y)

        // A form stacks the outlines of its lines, about as tall as a capital, with its spacing
        // between them; a field is as tall as a whole line of its font, which eats into it.
        let font    = unwrap .textFont.regular
        let height  = Math.ceil(font.height)
        let count   = cast(f32, .textLines.count)
        let spacing = Math.max(.textSpec.spacing * .zoom - (font.height - font.capHeight), 0)
        let total   = height * count + spacing * (count - 1)

        var y = rect.y
        switch #complete .textSpec.alignVert
        {
        case .LeftTop:     y = rect.y
        case .Center:      y = rect.vertCenter() - total * 0.5
        case .RightBottom: y = rect.bottom() - total
        }

        // The words start where the form starts them; the field reaches past their end by the
        // room of the caret.
        let room = Math.ceil(font.height * 0.25)
        for line in .textLines
        {
            let wordsWidth = Painter.measureStringSnapped(line.text(), font, deviceScale: line.deviceScale())
            var x = rect.x
            switch #complete .textSpec.alignHorz
            {
            case .LeftTop:     x = rect.x
            case .Center:      x = rect.horzCenter() - wordsWidth * 0.5
            case .RightBottom: x = rect.right() - wordsWidth
            }

            line.setPosition(Math.Rectangle{x: Math.round(x), y: Math.round(y), width: Math.ceil(wordsWidth) + room, height: height})
            y += height + spacing
        }
    }

    // The keys and the focus of a line: Escape lets the words go, Ctrl+Enter keeps them, Enter
    // breaks the line, the arrows go from line to line, and the focus leaving every line keeps
    // the words.
    mtd textLineEvent(line: *EditBox, evt: IEvent)->bool
    {
        switch evt
        {
        case KeyEvent as key where key.kind == .Pressed:
            if .textLineKey(line, key.key, key.modifiers)
            {
                key.accepted = true
                return true
            }

        case FocusEvent as focus where focus.kind == .Lost:
            if not .isEditingText() do
                break
            for other in .textLines where focus.other == cast(*Wnd, other) do
                return false
            .endTextEdit(focus: false)
        }

        return false
    }

    // Handles the key `key` pressed in `line`. Returns false for a key the line keeps.
    mtd textLineKey(line: *EditBox, key: Input.Key, modifiers: Input.KeyModifiers)->bool
    {
        var index = 0'u64
        for other, i in .textLines where other == line do
            index = i

        let sel   = line.selection()
        let caret = sel.end
        let empty = sel.start == sel.end
        switch key
        {
        case .Escape:
            .endTextEdit(keep: false)
            return true

        case .Return:
            if modifiers.has(.Control) or .textSpec.step
            {
                .endTextEdit()
                return true
            }

            // The line breaks at the caret, the selection gone.
            if not empty do
                line.deleteSelection()
            let at: String = line.text()
            let cut        = line.selection().end
            let head       = Swag.makeString(at.buffer, cut)
            let tail       = Swag.makeString(at.buffer + cut, at.length - cut)
            let next       = .addTextLine(index + 1, tail)
            line.setText(head)
            next.setFocus()
            next.setSelection(0, 0)
            .placeTextLines()
            return true

        case .Back:
            if not empty or caret or not index do
                return false
            let prev         = .textLines[index - 1]
            let join         = prev.text().count
            var text: String = prev.text()
            text += line.text()
            prev.setText(text)
            prev.setFocus()
            prev.setSelection(join, join)
            .textLines.removeAtOrdered(index)
            line.destroy()
            .placeTextLines()
            return true

        case .Delete:
            if not empty or caret != line.text().count or index + 1 >= .textLines.count do
                return false
            let next         = .textLines[index + 1]
            var text: String = line.text()
            text += next.text()
            line.setText(text)
            line.setSelection(caret, caret)
            .textLines.removeAtOrdered(index + 1)
            next.destroy()
            .placeTextLines()
            return true

        case .Up, .Down:
            if modifiers.has(.Shift) do
                return false
            if (key == .Up and not index) or (key == .Down and index + 1 >= .textLines.count) do
                return true
            let other = .textLines[key == .Up ? index - 1 : index + 1]
            let pos   = runeStart(other.text(), Math.min(caret, other.text().count))
            other.setFocus()
            other.setSelection(pos, pos)
            return true
        }

        return false
    }
}

// Returns `pos` moved back to the start of the rune it falls in, in the UTF-8 bytes of `text`.
func runeStart(text: string, pos: u64)->u64
{
    var result = pos
    while result and result < text.count and (text[result] & 0xC0) == 0x80 do
        result -= 1
    return result
}
