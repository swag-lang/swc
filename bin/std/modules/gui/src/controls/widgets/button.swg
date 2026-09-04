#global public

using Core

// Provides shared pointer state, command-state integration, icons, and activation signals for buttons.
struct Button
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            icon:       Icon     // Optional icon displayed by the concrete button.
            iconWidth:  f32      // Explicit icon width, or zero to preserve the icon width.
            iconHeight: f32      // Explicit icon height, or zero to preserve the icon height.
        }

        sigPressed:      SigArray'func||(*Button)     // Emitted after a completed primary activation.
        sigRightPressed: SigArray'func||(*Button)     // Emitted when the secondary button is pressed inside the control.
    }

    // Hover and press state, moved by the mouse events the button receives. Connect to
    // 'sigPressed' to react to a press instead of polling it.
    isPressed:  bool     // Whether the button is held down.
    isPressing: bool     // Whether the press gesture started on this button.
    isHot:      bool     // Whether the mouse is over the button.
    isIn:       bool     // Whether the mouse is inside the button rectangle.
}

impl IWnd for Button
{
    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind == .Hide or evt.kind == .Disable do
            .clearPointerState()
    }

    mtd impl onApplyStateEvent(evt: *CommandStateEvent)
    {
        if evt.id != .id do
            return

        if evt.updatedFields & .Icon and (.icon.imageList != evt.icon.imageList or .icon.index != evt.icon.index)
        {
            evt.accepted = true
            .icon        = evt.icon
            .invalidate()
        }

        if evt.updatedFields & .Name and .name != evt.name
        {
            evt.accepted = true
            .name        = evt.name
            .invalidate()
        }

        if evt.updatedFields & .Disabled
        {
            evt.accepted = true
            .enable(!evt.disabled)
        }
    }
}

impl Button
{
    // Replaces the displayed label, repaints, and lets the next layout pass re-measure it.
    //
    // Pass `null` for a button that shows only its icon. The label is plain text; rich spans
    // are set through `name` directly. A button carrying no explicit width follows its
    // label, so re-labelling one after a language switch is enough to size it again.
    mtd setText(text: string?)
    {
        .name.set(text)
        .invalidate()
        .invalidateLayout()
    }

    // Returns the displayed label as plain text.
    mtd text()->string => .name.raw

    // Replaces the displayed icon and repaints the button.
    mtd setIcon(icon: Icon)
    {
        if .icon == icon do
            return
        .icon = icon
        .invalidate()
    }

    // Removes the displayed icon and repaints the button.
    mtd clearIcon()
    {
        if !.icon.isValid() do
            return
        .icon.clear()
        .invalidate()
    }

    // Overrides the icon draw size; zero on either axis preserves that axis from the icon descriptor.
    mtd setIconSize(width, height: f32)
    {
        Debug.assert(width >= 0 and height >= 0, "icon size cannot be negative")
        if .iconWidth == width and .iconHeight == height do
            return
        .iconWidth  = width
        .iconHeight = height
        .invalidate()
    }

    // Returns the width the caption and the optional icon need side by side.
    //
    // The layout matches [[Gui.Theme.drawIconText]], which every button paints its
    // content with; the padding a concrete button adds around that content is its own.
    // `bold` measures against the bold face a strong emphasis paints the caption with.
    internal mtd captionWidth(bold = false)->f32
    {
        var format: RichStringFormat
        format.font = .font()
        if bold do
            format.fontStyle = .Bold

        var result = 0'f32
        if (.name).count != 0
        {
            // Measured at the density the glyphs are really drawn at: laid out at a scale of
            // one and drawn at another, the run comes out wider than the width a caller sized
            // the button to, and the caption loses its last letter to the clip.
            .name.compute()
            Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &.name, format, .deviceScale())
            result = .name.boundRect.width
        }

        if .icon.isValid()
        {
            result += .icon.sizeX
            if result != .icon.sizeX do
                result += .themeMetrics().iconText_Margin
        }

        return result
    }

    // Returns the rectangle the keyboard-focus ring belongs on, for a button that draws a marker
    // beside a caption rather than a ground of its own.
    //
    // The traversal stop is the whole cell, but a check box or a radio button is almost never as
    // wide as what it shows: laid out in a column of a form it takes the column's width, and a
    // ring around that encloses as much empty ground as content. The mark closes on the marker and
    // its wording instead, keeping the air the ring would have kept inside a control that has a
    // shape — and never leaving the cell, so it cannot reach the option on the next line.
    //
    // Call it after the caption is drawn: the ink of the wording is what it measures.
    internal mtd markerFocusRect(box: Math.Rectangle)->Math.Rectangle
    {
        let inset = .themeMetrics().focusRing_Inset

        var result: retval = box
        if (.name).count != 0 do
            result.combine(.name.boundRect)

        // The same distance the ring keeps inside a control that has a shape, kept here outside
        // the content instead, and then given back because [[Gui.Theme.drawFocusRing]] insets the
        // rectangle it is handed. The cell is the ceiling: a mark reaching past it would collide
        // with the option on the next line.
        result.inflate(inset)
        result.intersect(.clientRect())
        result.inflate(inset)
        return result
    }

    internal mtd clearPointerState()
    {
        if !.isHot and !.isIn and !.isPressed and !.isPressing do
            return
        .isHot, .isIn           = false
        .isPressed, .isPressing = false
        .invalidate()
    }

    // Updates shared pointer state and reports a completed primary activation.
    internal mtd processMouseEvent(evt: *MouseEvent)->bool
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false

        case .Enter:
            .isHot, .isIn = true
            .invalidate()

        case .Leave:
            .isHot, .isIn = false
            .invalidate()

        case .Move:
            if !.isPressing do
                break
            let rect = .clientRect()
            if !rect.contains(pos)
            {
                .isPressed, .isIn = false
                .invalidate()
            }
            else
            {
                .isIn = true
                if !.isPressed
                {
                    .isPressed = true
                    .invalidate()
                }
            }

        case .Pressed:
            if evt.button == .Left
            {
                .isPressed, .isPressing = true
                .captureMouse()
                .invalidate()
            }
            elif evt.button == .Right
            {
                if .isIn do
                    .sigRightPressed.call(me)
            }

        case .Released:
            if evt.button == .Left
            {
                let notifyPressed = .isPressed and .isIn

                if .isPressing or .isPressed
                {
                    .isPressing = false
                    .releaseMouse()
                }

                if .isPressed
                {
                    .isPressed, .isPressing = false
                    if notifyPressed do
                        .sigPressed.call(me)
                    .invalidate()
                }

                return notifyPressed
            }
        }

        return false
    }
}
