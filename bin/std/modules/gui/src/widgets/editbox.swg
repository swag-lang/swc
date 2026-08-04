#global public

using Core, Pixel

// Specifies the visual geometry of the EditBox.
enum EditBoxForm
{
    Rectangle            // Uses a rectangular background and standard border.
    RoundedRectangle     // Uses a rounded rectangular background and border.
    Flat                 // Uses a flat background and border.
    Transparent          // Draws no background unless validation fails.
}

// Defines the type of input that the EditBox should accept and validate.
enum EditBoxInputMode
{
    Text                // Accepts unrestricted UTF-8 text.
    SignedInteger       // Accepts a signed 64-bit integer in the configured range.
    UnsignedInteger     // Accepts an unsigned 64-bit integer in the configured range.
    FloatingPoint       // Accepts a 64-bit floating-point value in the configured range.
    Hexadecimal         // Accepts an unsigned 64-bit hexadecimal value in the configured range.
}

// Possible outcomes when validating the EditBox content.
enum EditBoxCheckResult
{
    Incomplete         // Allows an incomplete prefix, such as "-" or "0x", while editing.
    Valid              // Accepts the content.
    InvalidSilent      // Rejects the latest edit without showing an error state.
    InvalidVisible     // Keeps the content and shows an error state.
}

#[Swag.EnumFlags]
// Optional behaviour modifiers for the EditBox.
enum EditBoxFlags
{
    None = 0                        // Uses editable left-aligned text without a clear button.
    ReleaseFocusOnEnterOrEscape     // Releases focus after Enter or Escape.
    ReadOnly                        // Prevents edits while preserving focus and selection.
    RightAligned                    // Aligns text to the trailing edge.
    ClearButton                     // Shows a clear button while content is non-empty.
}

// Edits and validates a single line of text, optionally as a bounded numeric value.
struct EditBox
{
    using wnd: Wnd     // Embedded window behavior and presentation.

    internal
    textStorage: String     // Current UTF-8 text content.

    sigTextChanged: SigArray'func||(*EditBox)     // Emitted once after text changes.
    sigFocusLost:   SigArray'func||(*EditBox)     // Emitted after keyboard focus is lost.
    sigSubmitted:   SigArray'func||(*EditBox)     // Emitted when Enter is pressed.
    sigCancelled:   SigArray'func||(*EditBox)     // Emitted when Escape is pressed.
    readonly
    {
        icon:           Icon                                           // Optional leading icon.
        unit:           String                                         // Optional trailing unit, such as "kg".
        form      = EditBoxForm.Rectangle                              // Current background geometry.
        flags     = EditBoxFlags.ReleaseFocusOnEnterOrEscape           // Active interaction and presentation options.
        inputMode = EditBoxInputMode.Text                              // Current built-in validation mode.
        maximumLength:  s32                                            // Maximum rune count, or zero for no limit.
        trailingMargin: f32                                            // Extra trailing inset in logical units.
        validator:      #null func||(*EditBox)->EditBoxCheckResult     // Custom validator, or null for built-in validation.
    }

    internal
    {
        originalText: String     // Text captured when focus was gained

        // Numeric bounds used when inputMode is S64/U64/X64/F64.
        using minMax: union
        {
            minMaxS64: { min: s64, max: s64 } = {Swag.S64.Min, Swag.S64.Max}      // Signed integer bounds
            minMaxU64: { min: u64, max: u64 } = {0, Swag.U64.Max}                 // Unsigned integer bounds
            minMaxF64: { min: f64, max: f64 } = {-Swag.F64.Max, Swag.F64.Max}     // Floating‑point bounds
        }

        aniBk:     BlendColor = {speed: 4}     // Background colour animation
        aniBorder: BlendColor = {speed: 4}     // Border colour animation

        isInvalid:          bool                  // True if current content is invalid
        isHot:              bool                  // True while the mouse is hovering
        isDragging:         bool                  // True while the user is selecting text
        selBeg, selEnd:     u64                   // Selection start/end (byte indices)
        timerCaret:         #null *Timer          // Blinking‑caret timer
        clearBtn:           #null *IconButton     // Optional clear button instance
        clearBtnTextMargin: f32                   // Text margin reserved for the clear button
        visibleCaret:       bool                  // True when the caret should be visible
        posSelBeg:          f32                   // X‑position of selection start in pixels
        posSelEnd:          f32                   // X‑position of selection end in pixels
        scrollPosX:         f32                   // Horizontal scroll offset
        countRunes:         s32                   // Number of runes currently in text
    }
}

impl IWnd for EditBox
{
    // Handles gaining and losing keyboard focus.
    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        switch evt.kind
        {
        case .Gained:
            .originalText = .textStorage
            .timerCaret   = .surface!.app.addTimer(500'ms, me)
            .visibleCaret = true
            .computeCaretPos()
            .invalidate()

        case .Lost:
            .sigFocusLost.call(me)
            let srf = notnull .surface
            srf.app.removeTimer(notnull .timerCaret)
            .timerCaret   = null
            .visibleCaret = false
            .invalidate()
        }
    }

    // Renders the EditBox, including background, border, text, selection and caret.
    mtd impl onPaint(evt: *PaintEvent)
    {
        .syncClearButton()

        let bc      = evt.paintContext
        let painter = evt.paintContext.painter

        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let rects   = .themeRects()

        var subRectBk:     #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var colorBk:       Color = undefined
        var colorBorder:   Color = undefined
        var colorText:     Color = undefined
        var colorUnit:     Color = undefined

        switch .form
        {
        case .Rectangle, .Transparent:
            subRectBk     = &rects.edit_SquareBk
            subRectBorder = &rects.edit_SquareBorder

        case .RoundedRectangle:
            subRectBk     = &rects.edit_RoundBk
            subRectBorder = &rects.edit_RoundBorder

        case .Flat:
            subRectBk     = &rects.edit_FlatBk
            subRectBorder = &rects.edit_FlatBorder
        }

        colorText = colors.edit_Text
        colorUnit = colors.edit_TextUnit

        switch
        {
        case bc.isDisabled:
            colorBorder = colors.edit_DisabledBorder
            colorBk     = colors.edit_DisabledBk
            colorText   = colors.edit_DisabledText

        case .isInvalid:
            colorBorder = colors.edit_ErrorBorder
            colorBk     = colors.edit_ErrorBk

        case .flags.has(.ReadOnly):

            // Shown but not editable: render like a disabled box so it reads as read-only,
            // while the widget stays focusable (it can be navigated to and copied from).
            colorBorder = colors.edit_DisabledBorder
            colorBk     = colors.edit_DisabledBk
            colorText   = colors.edit_DisabledText

        case .hasFocus():
            colorBorder = colors.edit_FocusBorder
            colorBk     = colors.edit_FocusBk

        case .isHot:
            colorBorder = colors.edit_HotBorder
            colorBk     = colors.edit_HotBk

        default:
            colorBorder = colors.edit_Border
            colorBk     = colors.edit_Bk
        }

        .aniBk.apply(me, colorBk)
        .aniBorder.apply(me, colorBorder)

        var clientRect = .clientRect()
        if .form != .Transparent do
            theme.drawSubRect(painter, clientRect, subRectBk, .aniBk.cur())
        if .form != .Transparent or .isInvalid do
            theme.drawSubRect(painter, clientRect, subRectBorder, .aniBorder.cur())

        clientRect = .editRect()

        // Icon
        if .icon.isValid()
        {
            .icon.paint(bc.painter, clientRect.x, clientRect.vertCenter() - .icon.sizeY * 0.5, colors.edit_Text)
            clientRect.x     += .icon.sizeX + metrics.iconText_Margin
            clientRect.width -= .icon.sizeX + metrics.iconText_Margin
        }

        // Placeholder note
        if !.name.isEmpty() and .textStorage.isEmpty()
        {
            var format: RichStringFormat
            format.palette[0]    = colors.edit_Note
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .font()
            Theme.drawIconText(bc.painter, clientRect, {}, &.name, format, metrics.iconText_Margin)
        }

        // Caret rectangle and the snapped run width are reused below to place the
        // selection, the content and the caret. Text is measured with the same pixel
        // snapping it is drawn with, otherwise the drawn run is a touch wider than
        // measured and the last glyph spills past the clip (or the trailing unit sits
        // a few pixels off). This must match caretRect/computeCaretPos so the caret
        // tracks the scrolled text. The scroll offset itself is computed by
        // updateScroll (which mirrors this clientRect) so it can be unit-tested.
        let fontR    = nnFont(.font().regular)
        let caretPos = .caretRect()
        let sizeX    = Painter.measureStringSnapped(.textStorage.toString(), fontR, deviceScale: .deviceScale())
        .updateScroll()

        painter.pushClippingRect(clientRect)
        painter.translateTransform(-.scrollPosX, 0)

        // Selection
        if .selBeg != .selEnd and .hasFocus()
        {
            var pos = clientRect
            if .flags.has(.RightAligned) do
                pos.x = pos.right() - sizeX + .posSelBeg
            else do
                pos.x += .posSelBeg
            pos.x      -= .rightTextMargin()
            pos.y      = clientRect.vertCenter() - fontR.height * 0.5
            pos.height = fontR.height
            pos.width  = .posSelEnd - .posSelBeg
            bc.painter.fillRect(pos, colors.edit_SelectedBk)
        }

        // Content
        let y         = clientRect.vertCenter() - fontR.height * 0.5
        let editRight = clientRect.right()
        if .flags.has(.RightAligned)
        {
            clientRect.x = clientRect.right() - sizeX - .rightTextMargin()
        }

        bc.painter.drawString(clientRect.x, y, .textStorage, fontR, colorText)

        // Left-aligned boxes let the unit trail the value inside the scrolled content.
        if !.unit.isEmpty() and !.flags.has(.RightAligned)
        {
            bc.painter.drawString(clientRect.x + sizeX + metrics.editBox_UnitMargin, y, .unit, fontR, colorUnit)
        }

        // Caret
        if .visibleCaret and .hasFocus()
        {
            // Snap the caret to whole device pixels so it stays a crisp bar on
            // scaled displays.
            var cp = caretPos
            cp.x     = painter.snapToDeviceX(cp.x)
            cp.width = painter.hairline(cp.width)
            painter.fillRect(cp, colors.edit_Text)
        }

        painter.popClippingRect()
        painter.translateTransform(.scrollPosX, 0)

        // Right-aligned boxes pin the unit to the right edge, outside the scroll
        // transform, so it stays put while the value text scrolls underneath.
        if !.unit.isEmpty() and .flags.has(.RightAligned)
        {
            let unitW = Painter.measureString(.unit, fontR).width
            bc.painter.drawString(editRight - unitW, y, .unit, fontR, colorUnit)
        }
    }

    // Processes mouse interaction with the EditBox (clicks, drags, hover, wheel).
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false
            return

        case .DoubleClick:
            if evt.button != .Left do
                break
            let x = .moveCaretLeftStartWord(.selBeg)
            let y = .moveCaretRightEndWord(.selEnd)
            .setSelection(x, y)

        case .Pressed:
            if evt.button != .Left do
                break
            let x = .byteIndexAt(pos.x)
            .setSelection(x, x)
            .forceVisibleCaret()
            evt.accepted = true
            .isDragging  = true
            .captureMouse()

        case .Released:
            if evt.button != .Left do
                break
            if .isDragging do
                .releaseMouse()
            .isDragging  = false
            evt.accepted = true

        case .Move:
            if !.isDragging do
                break
            evt.accepted = true
            let x = .byteIndexAt(pos.x)
            .setSelection(.selBeg, x)

        case .Enter:
            .isHot = true
            .invalidate()

        case .Leave:
            .isHot = false
            .invalidate()
        }
    }

    // Blinking caret timer handler.
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        .visibleCaret = !.visibleCaret

        // Repaint the whole (small) edit box on each blink. Invalidating only the
        // caret rectangle is fragile: the caret is painted inside the horizontal
        // scroll transform (translateTransform(-scrollPosX)), so for a scrolled
        // right-aligned box a caret-rect in widget space lands far off, and the
        // surface unions it into a huge dirty region drawn as a black bar. A full
        // (bounded) invalidate has no rectangle to misplace.
        .invalidate()
    }

    // Handles keyboard input (navigation, edition, clipboard shortcuts, etc.).
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed
        {
            evt.accepted = .keyPressed(evt.key, evt.modifiers)
            if evt.accepted do
                .forceVisibleCaret()
        }
        elif evt.kind == .Character and !.flags.has(.ReadOnly)
        {
            if evt.character < 32 do
                evt.accepted = false
            else
            {
                .forceVisibleCaret()
                .deleteSelectionPrivate()
                .insertRune(evt.character)
            }
        }
    }
}

private impl EditBox
{
    // Keeps the optional clear button in sync with the current flags and text.
    mtd syncClearButton()
    {
        let mustShow = .flags.has(.ClearButton) and .textStorage != null and @countof(.textStorage)
        if !mustShow
        {
            if .clearBtn
            {
                .clearBtn.destroy()
                .clearBtn           = null
                .clearBtnTextMargin = 0
                .applyLayout()
            }

            return
        }

        if !.clearBtn
        {
            .clearBtn           = IconButton.create(me, .theme().icon24(ThemeIcons24.WndClose, 18), {0, 0, 24, 24})
            .clearBtn.dockStyle = .Right
            .clearBtn.setForm(IconButtonForm.Circle)
            .clearBtn.sigPressed += func|edit = me|(btn) { edit.setText(null); }
            .clearBtnTextMargin  = .clearBtn.position.width + .themeMetrics().iconText_Margin
            .applyLayout()
        }
    }

    // Handles individual key presses as well as shortcut combinations.
    mtd keyPressed(key: Input.Key, modifiers: Input.KeyModifiers)->bool
    {
        let ctrl  = modifiers & .Control
        let shift = modifiers & .Shift

        switch key
        {
        case .A:
            if ctrl and !shift
            {
                .setSelection(0, .textStorage.length)
                return true
            }

        case .Insert:
            if ctrl and !shift and .selBeg != .selEnd
            {
                Clipboard.addString(@mkstring(.textStorage.buffer + .selectionStartIndex(), .selectionEndIndex() - .selectionStartIndex()))
                return true
            }
            elif shift and !ctrl
            {
                let str = Clipboard.getString()
                .insertString(str.toString())
                return true
            }

        case .C:
            if ctrl and .selBeg != .selEnd
            {
                Clipboard.addString(@mkstring(.textStorage.buffer + .selectionStartIndex(), .selectionEndIndex() - .selectionStartIndex()))
                return true
            }

        case .X:
            if ctrl and .selBeg != .selEnd
            {
                Clipboard.addString(@mkstring(.textStorage.buffer + .selectionStartIndex(), .selectionEndIndex() - .selectionStartIndex()))
                .deleteSelection()
                return true
            }

        case .V:
            if ctrl
            {
                let str = Clipboard.getString()
                .insertString(str.toString())
                return true
            }

        case .Return:
            .sigSubmitted.call(me)
            if .flags.has(.ReleaseFocusOnEnterOrEscape) do
                .topView().setFocus()
            return true

        case .Escape:
            .sigCancelled.call(me)
            if .flags.has(.ReleaseFocusOnEnterOrEscape) do
                .topView().setFocus()
            return true

        case .Left:
            if ctrl do
                .selEnd = .moveCaretLeftStartWord(.selEnd)
            else do
                .selEnd = .moveCaretLeft(.selEnd)
            if shift do
                .setSelection(.selBeg, .selEnd)
            else do
                .setSelection(.selEnd, .selEnd)
            return true

        case .Right:
            if ctrl do
                .selEnd = .moveCaretRightEndWord(.selEnd)
            else do
                .selEnd = .moveCaretRight(.selEnd)
            if shift do
                .setSelection(.selBeg, .selEnd)
            else do
                .setSelection(.selEnd, .selEnd)
            return true

        case .Home:
            if shift do
                .setSelection(.selBeg, 0)
            else do
                .setSelection(0, 0)
            return true

        case .End:
            if shift do
                .setSelection(.selBeg, .textStorage.length)
            else do
                .setSelection(.textStorage.length, .textStorage.length)
            return true

        case .Back:
            if .selBeg == .selEnd
            {
                if !.selBeg do
                    return true
                .selBeg = .moveCaretLeft(.selBeg)
            }

            .deleteSelection()
            return true

        case .Delete:
            if .selBeg == .selEnd
            {
                .selEnd = .moveCaretRight(.selBeg)
            }

            .deleteSelection()
            return true
        }

        return false
    }

    // Inserts an arbitrary UTF‑8 string (after deleting the current selection).
    mtd insertString(str: #null string)
    {
        let safeStr = str orelse ""
        Utf8.visitRunes(safeStr) #code(r)
        {
            .insertRune(r)
        }
    }

    // Inserts a raw UTF‑8 slice without validation.
    mtd insertUtf8(s: string)
    {
        .deleteSelectionPrivate()
        .textStorage.insert(.selEnd, s)
        .setSelection(.selEnd + @countof(s), .selEnd + @countof(s))
        .countRunes += 1
    }

    // Validates the current content according to inputMode or custom callback.
    mtd checkContent()->EditBoxCheckResult
    {
        var res = EditBoxCheckResult.Valid
        if .validator
        {
            res = .validator(me)
        }
        else
        {
            var eat = 0'u32
            var parseErr: #null any
            switch .inputMode
            {
            case .SignedInteger:
                let val = catch StrConv.parseS64(.textStorage) as err
                parseErr = err
                eat      = val.eat
                if err == null and eat == .textStorage.length and (val.value < .minMaxS64.min or val.value > .minMaxS64.max) do
                    res = .InvalidVisible

            case .UnsignedInteger:
                let val = catch StrConv.parseU64(.textStorage) as err
                parseErr = err
                eat      = val.eat
                if err == null and eat == .textStorage.length and (val.value < .minMaxU64.min or val.value > .minMaxU64.max) do
                    res = .InvalidVisible

            case .Hexadecimal:
                let val = catch StrConv.parseX64(.textStorage) as err
                parseErr = err
                eat      = val.eat
                if err == null and eat == .textStorage.length and (val.value < .minMaxU64.min or val.value > .minMaxU64.max) do
                    res = .InvalidVisible

            case .FloatingPoint:
                let val = catch StrConv.parseF64(.textStorage) as err
                parseErr = err
                eat      = val.eat
                if err == null and eat == .textStorage.length and (val.value < .minMaxF64.min or val.value > .minMaxF64.max) do
                    res = .InvalidVisible
            }

            if res == .Valid
            {
                if parseErr == Errors.ParseIncompleteError do
                    res = .Incomplete
                elif parseErr == Errors.OverflowError do
                    res = .InvalidVisible
                elif parseErr != null or eat != @countof(.textStorage) do
                    res = .InvalidSilent
            }
        }

        .isInvalid = res == .InvalidVisible

        return res
    }

    // Inserts a single Unicode rune, enforcing maximum length and validation.
    mtd insertRune(r: rune)
    {
        if .maximumLength and .countRunes == .maximumLength do
            return

        // Convert rune to UTF‑8.
        var utf8: [5] u8
        let cpt = Utf8.fromUnicode(utf8, [r])
        if !cpt do
            return
        utf8[cpt] = 0

        // Determine whether we need to validate the content.
        let mustValidate = .validator or .inputMode != .Text
        if !mustValidate
        {
            .insertUtf8(@mkstring(&utf8[0], cpt))
            .notifyChanged()
            return
        }

        let saveText   = .textStorage
        let saveSelBeg = .selBeg
        let saveSelEnd = .selEnd
        .insertUtf8(@mkstring(&utf8[0], cpt))

        let res = .checkContent()
        if res == .InvalidSilent
        {
            .textStorage = saveText
            .setSelection(saveSelBeg, saveSelEnd)
            .countRunes -= 1
        }
        else do
            .notifyChanged()
    }

    #[Swag.Inline]
    {
        // Returns the first byte of the current selection.
        mtd selectionStartIndex() => .selBeg <= .selEnd ? .selBeg : .selEnd

        // Returns the last byte of the current selection.
        mtd selectionEndIndex() => .selBeg <= .selEnd ? .selEnd : .selBeg
    }

    #[Swag.Discardable]
    // Deletes the current selection without emitting change notifications.
    mtd deleteSelectionPrivate()->bool
    {
        if .selBeg == .selEnd do
            return false

        .checkSelection()

        let selB = .selectionStartIndex()
        let selE = .selectionEndIndex()
        if selB == .textStorage.length do
            return false

        .countRunes -= cast(s32) Utf8.countRunes(.textStorage[selB to selE - 1])
        .textStorage.remove(selB, selE - selB)
        discard .checkContent()

        .setSelection(selB, selB)
        return true
    }

    // Returns the client rectangle adjusted by padding and right margin.
    mtd editRect()->Math.Rectangle
    {
        var rect = .paddedClientRect()
        rect.moveRight(-.trailingMargin - .clearBtnTextMargin)
        return rect
    }

    // Returns the left padding for text rendering (accounts for icon).
    mtd leftTextMargin()->f32
    {
        var rect = .editRect()
        if .icon.isValid() do
            rect.x += .icon.sizeX + .themeMetrics().iconText_Margin
        return rect.x
    }

    // Returns the right padding for text rendering (accounts for 'unit').
    mtd rightTextMargin()->f32
    {
        if !.flags.has(.RightAligned) do
            return 0
        if .unit.isEmpty() do
            return 0
        let font = nnFont(.font().regular)
        return Painter.measureString(.unit, font).width + .themeMetrics().editBox_UnitMargin
    }

    // Returns the padding vector for the current visual form.
    mtd formPadding()->Math.Vector4
    {
        switch #complete .form
        {
        case .Rectangle:        return .themeMetrics().editBox_SquarePadding
        case .RoundedRectangle: return .themeMetrics().editBox_RoundPadding
        case .Flat:             return .themeMetrics().editBox_FlatPadding
        case .Transparent:      break
        }

        return {}
    }

    // Width the box needs to fully display the widest value of its numeric input
    // range (U64/S64/F64), measured with the current font and chrome. Returns 0 for
    // non-numeric modes. Adapts automatically to the value range, font and theme.
    mtd numericPreferredWidth()->f32
    {
        let fontR = .font().regular
        if !fontR do
            return 0
        let font = nnFont(fontR)

        var lo, hi: String
        switch .inputMode
        {
        case .UnsignedInteger:
            lo = Format.toString("%", .minMaxU64.min)
            hi = Format.toString("%", .minMaxU64.max)

        case .SignedInteger:
            lo = Format.toString("%", .minMaxS64.min)
            hi = Format.toString("%", .minMaxS64.max)

        case .FloatingPoint:
            lo = Format.toString("%{f2}", .minMaxF64.min)
            hi = Format.toString("%{f2}", .minMaxF64.max)

        default:
            return 0
        }

        let textW = Math.max(Painter.measureString(lo.toString(), font).width, Painter.measureString(hi.toString(), font).width)

        // Derive the box width from the box's *actual* text area (so border, form
        // padding, right margin, unit and clear button are all accounted for),
        // plus one extra digit of breathing room for the caret.
        let chrome = Math.max(.position.width - .editRect().width, 0.0) + .rightTextMargin()
        return Math.ceil(textW) + chrome + Painter.measureString("00", font).width
    }

    // Forces the caret to become visible and restarts its blink timer.
    mtd forceVisibleCaret()
    {
        if .timerCaret
        {
            .visibleCaret = true
            .timerCaret.restart()
        }
    }

    // Computes the caret rectangle in surface coordinates.
    mtd caretRect()->Math.Rectangle
    {
        var result: retval = undefined

        var clientRect = .editRect()
        if .icon.isValid() do
            clientRect.x += .icon.sizeX + 4

        result = clientRect
        let fontR = .font().regular
        let font  = nnFont(fontR)
        if !.textStorage.isEmpty()
        {
            if .flags.has(.RightAligned)
            {
                let sizeX = Painter.measureStringSnapped(.textStorage.toString(), font, deviceScale: .deviceScale())
                result.x = clientRect.right() - sizeX + .posSelEnd - 2
            }
            else do
                result.x += .posSelEnd
        }
        elif .flags.has(.RightAligned)
        {
            result.x = clientRect.right() - .posSelEnd - 2
        }

        result.x      -= .rightTextMargin()
        result.height = font.height
        result.y      = clientRect.vertCenter() - result.height * 0.5

        result.width = 2
        return result
    }

    // Converts an X mouse position into a byte index inside "text".
    mtd byteIndexAt(xmouse: f32)->u64
    {
        if !.textStorage.length do
            return 0

        var x = xmouse
        x += .scrollPosX

        let fontR = .font().regular
        let font  = nnFont(fontR)

        // Naïve incremental search. Could be improved for performance.
        if .flags.has(.RightAligned)
        {
            if .textStorage.length == 1 do
                return 0

            var clientRect = .editRect()
            clientRect.x -= .rightTextMargin()

            // Hit-test against the same snapped advances the glyphs are drawn with.
            let shaped    = Painter.shapeRun(.textStorage.toString(), font)
            let base      = clientRect.right() - Painter.measureStringSnapped(&shaped, deviceScale: .deviceScale())
            var lastWidth = 0'f32
            var diff      = 0'f32
            for [idx] in 1 until .textStorage.length
            {
                let met = Painter.measureStringSnapped(&shaped, idx, .deviceScale())
                diff = (met - lastWidth) * 0.5
                if x <= base + met
                {
                    if x < base + lastWidth + diff do
                        return idx - 1
                    return idx
                }

                lastWidth = met
            }

            if x < base + lastWidth + diff do
                return .textStorage.length - 1
        }
        else
        {
            x -= .leftTextMargin()

            // Hit-test against the same snapped advances the glyphs are drawn with,
            // so a click lands on the glyph the caret will be painted next to.
            let shaped    = Painter.shapeRun(.textStorage.toString(), font)
            var lastWidth = 0'f32
            var diff      = 0'f32
            for [idx] in 1 until .textStorage.length
            {
                let met = Painter.measureStringSnapped(&shaped, idx, .deviceScale())
                diff = (met - lastWidth) * 0.5
                if x <= met
                {
                    if x < lastWidth + diff do
                        return idx - 1
                    return idx
                }

                lastWidth = met
            }

            if x < lastWidth + diff do
                return .textStorage.length - 1
        }

        return .textStorage.length
    }

    // Updates cached caret and selection pixel positions.
    mtd computeCaretPos()
    {
        if .focusedWindow() != me do
            return

        let fontR = .font().regular
        let font  = nnFont(fontR)

        // Carets and selection rectangles must sit on the same pixel-snapped advances
        // the glyph run is drawn with (see measureStringSnapped). Measuring with the
        // raw, unsnapped advances lets a per-glyph rounding error accumulate, so the
        // caret drifts further from the real glyph edge the longer the text is. This
        // holds for both alignments, so both use the snapped measure.
        let text = .textStorage.toString()
        .posSelBeg, .posSelEnd = Painter.measureStringSnapped(text, font, .selEnd, deviceScale: .deviceScale())
        if .selBeg != .selEnd do
            .posSelBeg = Painter.measureStringSnapped(text, font, .selBeg, deviceScale: .deviceScale())
    }

    // Moves caret left to the start of the previous word.
    mtd moveCaretLeftStartWord(sel: u64)->u64
    {
        if !sel do
            return sel

        var s = sel
        s = .moveCaretLeft(s)
        if s == sel do
            return sel

        let test = !Latin1.isSpace((notnull .textStorage.buffer)[s])
        for
        {
            let ns = .moveCaretLeft(s)
            if ns == s do
                break
            if Latin1.isSpace((notnull .textStorage.buffer)[ns]) == test do
                return s
            s = ns
        }

        return 0
    }

    // Moves caret right to the end of the current/next word.
    mtd moveCaretRightEndWord(sel: u64)->u64
    {
        if sel == .textStorage.length do
            return sel

        let test = !Latin1.isSpace((notnull .textStorage.buffer)[sel])
        var s    = sel
        while s != .textStorage.length
        {
            s = .moveCaretRight(s)
            if Latin1.isSpace((notnull .textStorage.buffer)[s]) == test do
                return s
        }

        return .textStorage.length
    }

    // Moves caret left by one rune.
    mtd moveCaretLeft(sel: u64)->u64
    {
        if !sel do
            return sel
        let str      = @mkstring(.textStorage.buffer, sel)
        let {?, eat} = Utf8.decodeLastRune(str)
        return sel - eat
    }

    // Moves caret right by one rune.
    mtd moveCaretRight(sel: u64)->u64
    {
        if sel == .textStorage.length do
            return sel
        let str      = @mkstring(.textStorage.buffer + sel, .textStorage.length - sel)
        let {?, eat} = Utf8.decodeRune(str)
        return sel + eat
    }

    // Clamps selection indices and triggers repaint.
    mtd checkSelection()
    {
        .selBeg = Math.min(.selBeg, .textStorage.length)
        .selEnd = Math.min(.selEnd, .textStorage.length)
        .invalidate()
    }

    // Emits sigTextChanged, recomputes caret, updates the clear button, and repaints.
    mtd notifyChanged()
    {
        .sigTextChanged.call(me)
        .computeCaretPos()
        .syncClearButton()
        .invalidate()
    }
}

internal impl EditBox
{
    // Recomputes the horizontal scroll offset so the caret stays inside the visible
    // edit rectangle. Driven by onPaint (it mirrors the exact clientRect paint
    // uses), and exposed at module scope so the scroll/clip behaviour can be
    // exercised headlessly — painting needs a renderer, this does not.
    mtd updateScroll()
    {
        let fontR   = nnFont(.font().regular)
        let metrics = .themeMetrics()

        var clientRect = .editRect()
        if .icon.isValid()
        {
            clientRect.x     += .icon.sizeX + metrics.iconText_Margin
            clientRect.width -= .icon.sizeX + metrics.iconText_Margin
        }

        let caretPos  = .caretRect()
        let decalX    = Math.min(Painter.measureString("X", fontR).width * 10, clientRect.width * 0.5)
        let sizeX     = Painter.measureStringSnapped(.textStorage.toString(), fontR, deviceScale: .deviceScale())
        let maxDecalX = sizeX - decalX

        if caretPos.x - clientRect.x < .scrollPosX do
            .scrollPosX = caretPos.x - clientRect.x - decalX
        elif caretPos.x - clientRect.x >= .scrollPosX + clientRect.width do
            .scrollPosX = Math.min(caretPos.x - clientRect.x - decalX, maxDecalX)

        // Never stay scrolled past what the current size can show. The caret logic
        // above scrolls the text when the box is too small, but it only reacts to the
        // caret leaving the visible window, not to the box growing back. Clamp the
        // scroll to the content extent so a box that regains room shows its text from
        // a natural position instead of staying half-scrolled with empty space.
        if .flags.has(.RightAligned)
        {
            let maxScroll = Math.max(sizeX - clientRect.width, 0)
            .scrollPosX = Math.max(Math.min(.scrollPosX, 0), -maxScroll)
        }
        else
        {
            var contentWidth = sizeX
            if !.unit.isEmpty() do
                contentWidth += metrics.editBox_UnitMargin + Painter.measureString(.unit, fontR).width

            // Reserve room for the caret that sits *after* the last character. Without
            // it, a box scrolled to the end of its text aligns the text's right edge
            // with the clip, so the trailing caret (whose left edge then lands exactly
            // on clientRect.right()) is fully clipped and appears to vanish.
            contentWidth += caretPos.width

            let maxScroll = Math.max(contentWidth - clientRect.width, 0)
            .scrollPosX = Math.min(Math.max(.scrollPosX, 0), maxScroll)

            // The trigger above mostly reasons about the caret left edge, but the
            // visible object is the full caret rectangle. Keep the final clamped
            // scroll honest so the 2px caret cannot remain half-clipped at the right.
            let caretLeft  = caretPos.x - clientRect.x
            let caretRight = caretPos.right() - clientRect.x
            if caretLeft < .scrollPosX do
                .scrollPosX = caretLeft
            elif caretRight > .scrollPosX + clientRect.width do
                .scrollPosX = caretRight - clientRect.width
        }
    }

    // Caret rectangle and the visible edit rectangle it is clipped against, both in
    // widget space after the current horizontal scroll (i.e. exactly what paint draws
    // and clips). Exposed for tests asserting the caret is not clipped at either edge.
    mtd caretClip()->{ caret: Math.Rectangle, view: Math.Rectangle }
    {
        var caret = .caretRect()
        caret.x -= .scrollPosX
        return {caret, .editRect()}
    }
}

impl EditBox
{
    // Creates a single-line edit box.
    #[Swag.Discardable]
    func create(parent: *Wnd, content: #null string, position: Math.Rectangle = {}, id: #null WndId = null, flags: EditBoxFlags = .ReleaseFocusOnEnterOrEscape)->*EditBox
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().editBox_Height
        if pos.width == 0 do
            pos.width = parent.themeMetrics().editBox_Width

        let result = Wnd.create'EditBox(parent, null, pos, id)
        result.setAllPaddings(result.themeMetrics().editBox_SquarePadding)
        result.flags         = flags
        result.focusStrategy = .OnMousePress
        result.setText(content, false)
        return result
    }

    // Deletes the selected text.
    mtd deleteSelection()
    {
        if .flags.has(.ReadOnly) do
            return
        if .deleteSelectionPrivate() do
            .notifyChanged()
    }

    // Sets the current selection.
    mtd setSelection(start, end: u64)
    {
        .selBeg = start
        .selEnd = end
        .checkSelection()
        .computeCaretPos()
    }

    // Selects the whole content.
    mtd selectAll()
    {
        .setSelection(0, .textStorage.length)
    }

    // Changes the placeholder displayed while content is empty.
    mtd setPlaceholder(placeholder: #null string)
    {
        .name.set(placeholder)
        .invalidate()
    }

    // Replaces the content and optionally emits one `sigTextChanged` notification.
    mtd setText(str: #null string, notify = true)
    {
        if .textStorage == str do
            return
        .sigTextChanged.disable()
        .textStorage.clear()
        .selBeg, .selEnd = 0
        .countRunes      = 0
        .insertString(str)
        .sigTextChanged.enable()
        if notify do
            .notifyChanged()
        else
        {
            .computeCaretPos()
            .syncClearButton()
            .invalidate()
        }
    }

    // Returns the current text.
    mtd const text()->string
    {
        return .textStorage.toString()
    }

    // Restores the text captured when focus was gained.
    mtd restoreOriginalText()
    {
        .setText(.originalText)
    }

    // Selects unrestricted built-in text input; a custom validator still applies.
    mtd setTextInput()
    {
        .inputMode = .Text
        .isInvalid = false
        .invalidate()
    }

    // Accepts signed 64-bit integers in the inclusive range.
    mtd setSignedIntegerRange(min = Swag.S64.Min, max = Swag.S64.Max)
    {
        Debug.assert(min <= max, "minimum cannot exceed maximum")
        .inputMode     = .SignedInteger
        .minMaxS64.min = min
        .minMaxS64.max = max
        discard .checkContent()
        .invalidate()
    }

    // Accepts unsigned 64-bit integers in the inclusive range.
    mtd setUnsignedIntegerRange(min = 0'u64, max = Swag.U64.Max)
    {
        Debug.assert(min <= max, "minimum cannot exceed maximum")
        .inputMode     = .UnsignedInteger
        .minMaxU64.min = min
        .minMaxU64.max = max
        discard .checkContent()
        .invalidate()
    }

    // Accepts unsigned hexadecimal integers in the inclusive range.
    mtd setHexadecimalRange(min = 0'u64, max = Swag.U64.Max)
    {
        Debug.assert(min <= max, "minimum cannot exceed maximum")
        .inputMode     = .Hexadecimal
        .minMaxU64.min = min
        .minMaxU64.max = max
        discard .checkContent()
        .invalidate()
    }

    // Accepts 64-bit floating-point values in the inclusive range.
    mtd setFloatingPointRange(min = -Swag.F64.Max, max = Swag.F64.Max)
    {
        Debug.assert(min <= max, "minimum cannot exceed maximum")
        .inputMode     = .FloatingPoint
        .minMaxF64.min = min
        .minMaxF64.max = max
        discard .checkContent()
        .invalidate()
    }

    // Sets the visual form of the EditBox.
    mtd setForm(form: EditBoxForm)
    {
        if .form == form do
            return
        .form = form

        switch #complete .form
        {
        case .Rectangle:        .setAllPaddings(.themeMetrics().editBox_SquarePadding)
        case .RoundedRectangle: .setAllPaddings(.themeMetrics().editBox_RoundPadding)
        case .Flat:             .setAllPaddings(.themeMetrics().editBox_FlatPadding)
        case .Transparent:      .setAllPaddings(0)
        }

        .invalidate()
    }

    // Adds and removes interaction options.
    mtd updateFlags(add: EditBoxFlags = .None, remove = EditBoxFlags.None)
    {
        var newFlags = .flags
        newFlags.add(add)
        newFlags.remove(remove)
        if .flags == newFlags do
            return
        .flags = newFlags
        .syncClearButton()
        .invalidate()
    }

    // Changes the leading icon.
    mtd setIcon(icon: Icon)
    {
        .icon = icon
        .invalidate()
    }

    // Changes the trailing unit.
    mtd setUnit(unit: #null string)
    {
        .unit = unit orelse ""
        .invalidate()
    }

    // Changes the maximum rune count; zero removes the limit.
    mtd setMaximumLength(length: s32)
    {
        Debug.assert(length >= 0, "maximum length cannot be negative")
        .maximumLength = length
    }

    // Changes the extra trailing inset.
    mtd setTrailingMargin(margin: f32)
    {
        Debug.assert(margin >= 0, "trailing margin cannot be negative")
        if .trailingMargin == margin do
            return
        .trailingMargin = margin
        .invalidate()
    }

    // Changes the custom validator; null restores built-in validation.
    mtd setValidator(validator: #null func||(*EditBox)->EditBoxCheckResult)
    {
        .validator = validator
        discard .checkContent()
        .invalidate()
    }

    // Returns the selected byte range.
    mtd const selection()->{ start: u64, end: u64 } =>
    {
        .selBeg, .selEnd}

    // Returns true when the current content is valid.
    mtd const isValid()->bool => !.isInvalid
}
