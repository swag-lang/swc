using Core, Pixel, Gui

// A toolbar band that keeps one group centered on the complete bar, independently of the action
// cluster and the viewer selector docked at its opposite edges.
struct ViewerActionBar
{
    using wnd:       Wnd
    centerGroup:     *Wnd?
    fillCenterGroup: bool
}

impl IWnd for ViewerActionBar
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .centerContent()
    }
}

impl ViewerActionBar
{
    func create(parent: *Wnd)->*ViewerActionBar
    {
        with let result = Wnd.create'ViewerActionBar(parent, {0, 0, 0, ViewerWindow.ActionBarHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .ToolBar
            .padding         = {12, 6, 12, 0}
        }

        return result
    }

    // Centers `centerGroup` on the bar at its preferred width, clamped to the padded client area.
    mtd centerContent()
    {
        if not .centerGroup do
            return
        let client         = .paddedClientRect()
        let group          = .centerGroup
        let preferredWidth = group.preferredSize.x
        var width: f32
        if preferredWidth > 0 do
            width = Math.min(preferredWidth, client.width)
        elif .fillCenterGroup do
            width = client.width
        else do
            width = group.position.width
        group.setPosition(Math.Rectangle{client.horzCenter() - width * 0.5, client.vertCenter() - group.position.height * 0.5, width, group.position.height}, computeLayout: false)
        group.applyLayout()
    }
}

// The faint line of readings at the foot of the document.
//
// What the window knows about the open file — its encoding, its lines, the selection a viewer
// reports — reads from the left; what the viewer adds of its own, a zoom or a reading time, packs
// against the right. It is text on the ground, not a bar: no fill and no rule, every word in the
// faint ink. The viewer contributions are measured first, because they say exactly what they
// need, and the details take what remains before they end in an ellipsis.
struct ViewerReadingLine
{
    using wnd: Wnd

    late details: *Label
}

impl IWnd for ViewerReadingLine
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .details != null do
            .computeLayout()
    }

    // The readings answer for the open file, so pointing at them offers what the file offers.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Released or evt.button != .Right
        {
            evt.accepted = false
            return
        }

        viewerWindowFor(me).showCurrentFileActions(evt.surfacePos)
    }
}

impl ViewerReadingLine
{
    // Height of the line, and the air between two of its groups.
    const Height       = 36.0
    const GroupSpacing = 16.0

    func create(parent: *Wnd)->*ViewerReadingLine
    {
        with let result = Wnd.create'ViewerReadingLine(parent, {0, 0, 0, Height}, "scope.reading")
        {
            .backgroundStyle = .Transparent
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
        }

        with result.details = Label.create(result, "", {0, 0, 0, Height}, null, .SecondaryText | .Ellipsis)
        {
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        return result
    }

    // Returns the viewer contributions the line shows, in creation order.
    mtd contributions()->Array'(*Wnd)
    {
        var result: #returntype
        for child in .children where child != cast(*Wnd, .details) and child.isLocallyVisible() do
            result.add(child)
        return result
    }

    // Reports whether the line has anything to show.
    mtd hasContent()->bool => not .details.name.isEmpty() or not .contributions().isEmpty()

    // Packs the viewer contributions against the right edge and gives the details the rest.
    mtd computeLayout()
    {
        let client  = .clientRect()
        let viewers = .contributions()

        var right = client.right()
        for i in reversed(viewers.count)
        {
            // The room a viewer reserved is its preferred size, never the width the last pass gave
            // it: reading the current width back would let the group only ever shrink.
            let one    = viewers[i]
            let limit  = one.preferredSize.x > 0 ? one.preferredSize.x : one.position.width
            let wanted = Math.min(Math.ceil(one.itf.measureContent(Math.Point{limit, client.height}).x), limit)
            let width  = Math.max(Math.min(wanted, right - client.x), 0)
            right -= width
            one.setPosition(Math.Rectangle{right, client.y + Math.round((client.height - one.position.height) * 0.5), width, one.position.height}, computeLayout: false)
            one.applyLayout()
            if width do
                right -= GroupSpacing
        }

        .details.setPosition(Math.Rectangle{client.x, client.y, Math.max(right - client.x, 0), client.height}, computeLayout: false)
    }
}

// Application-owned presentation for every viewer failure.
struct ViewerErrorView
{
    using wnd: Wnd

    late
    {
        summaryLabel: *Label
        reasonLabel:  *Label
        iconLabel:    *Label
    }
}

// Keeps the animated repaint local to the activity mark. The host covers the whole document, so
// animating the host itself would repaint every visible viewer subtree on every frame.
struct ViewerLoadingSpinner
{
    using wnd: Wnd

    animationPhase: f32
}

// Application-owned wait surface shared by every progressive viewer.
//
// A renderer only reports whether it is waiting; it neither chooses nor paints the feedback.
// The transparent host leaves the document exactly as it was and adds only the activity mark,
// so loading HTML or a picture cannot appear to change the document background. When the mark
// is decided on is the window's business, see [[ViewerWindow.updateLoadingIndicator]]; this
// surface only makes its arrival a fade rather than a pop.
struct ViewerLoadingOverlay
{
    using wnd: Wnd

    late spinner: *ViewerLoadingSpinner
    fadeAni:      AnimationHandle
}

// One application-owned marker for every current occurrence. Viewers report the band they painted
// over what they revealed and nothing else; this layer supplies the air around it, the corner, the
// themed wash, its own edge and a quiet electric pulse, so PDF text and a byte in the hexadecimal
// view speak exactly the same visual language.
//
// The band takes the corner a selected row already takes, and its edge is drawn inside its
// outline rather than across it: a rule sitting half outside a translucent wash reads as a frame
// with something faint behind it instead of as one marked word.
struct ViewerSearchOverlay
{
    using wnd: Wnd
    phase:     f32
}

impl IWnd for ViewerSearchOverlay
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let pulse   = 0.5'f32 + 0.5'f32 * Math.sin(.phase * Math.ConstF32.TwoPi)

        // The band, and around it the room the halo falls off in.
        var mark = .clientRect()
        mark.applyPadding(Math.Vector4{GlowReach, GlowReach, GlowReach, GlowReach})
        if mark.isEmpty() do
            return

        // The halo is a stack of filled rounded rectangles, drawn from the outermost inward: each
        // one covers those inside it, so their alphas add up toward the band while the outermost
        // ring stays a breath. Filling rather than stroking also keeps the whole marker off the
        // renderer's antialiased no-overlap pass, which clears alpha on a translucent top layer
        // and leaves seams as the pulse changes intensity.
        let glowStrength = (0.35'f32 + pulse * 0.65) / cast(f32, GlowSteps)
        let glow         = colors.searchMatch_Glow.withAlpha(cast(u8, (cast(f32, colors.searchMatch_Glow.a) * glowStrength)))
        for step in GlowSteps
        {
            let reach = GlowReach * cast(f32, GlowSteps - step) / cast(f32, GlowSteps)
            var ring  = mark
            ring.inflate(reach)
            painter.fillRoundRect(ring, MarkRadius + reach, MarkRadius + reach, glow)
        }

        painter.fillRoundRect(mark, MarkRadius, MarkRadius, colors.searchMatch_Bk)

        var pen = Pen.createSolid(colors.searchMatch_Border, MarkEdge)
        pen.borderPos = .Inside
        painter.drawRoundRect(mark, MarkRadius, MarkRadius, pen)
    }
}

impl ViewerSearchOverlay
{
    // The rounded mark around a match and the glow that pulses around it. The overlay extends past
    // the match by the padding plus the glow reach, so the glow is never clipped.
    const MarkPadX   = 5.0
    const MarkPadY   = 2.0
    const MarkRadius = 4.0
    const MarkEdge   = 1.0
    const GlowReach  = 5.0
    const GlowSteps  = 4'u32
    const InsetX     = MarkPadX + GlowReach
    const InsetY     = MarkPadY + GlowReach

    func create(parent: *Wnd)->*ViewerSearchOverlay
    {
        with let result = Wnd.create'ViewerSearchOverlay(parent, "scope.search.highlight")
        {
            .wndFlags        |= WndFlags.TopMost | WndFlags.Disabled
            .backgroundStyle = .Transparent
            .hide()
        }

        return result
    }

    // Follows a surface-coordinate match without entering the viewer's own layout or hit testing.
    //
    // `bounds` is the band the view painted; the air is added here, wider than it is tall because
    // a line's leading is what bounds the marker vertically while nothing bounds it horizontally.
    mtd showMatch(bounds: Math.Rectangle)
    {
        let parent  = unwrap .parent
        let topLeft = parent.surfaceToLocal(Math.Point{bounds.x, bounds.y})
        .setPosition(Math.Rectangle{topLeft.x - InsetX, topLeft.y - InsetY, bounds.width + InsetX * 2, bounds.height + InsetY * 2}, computeLayout: false)
        .show()
        .bringToFront()
    }
}

impl IWnd for ViewerLoadingSpinner
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let center  = .clientRect().center()
        let shape   = geometry(.animationPhase)
        let end     = shape.start + shape.sweep

        painter.setAntialiased(true)
        painter.drawArc(center.x, center.y, shape.radius, Math.Angle.fromDegrees(shape.start), Math.Angle.fromDegrees(end), Ink, 9)
        painter.drawArc(center.x, center.y, shape.radius, Math.Angle.fromDegrees(shape.start), Math.Angle.fromDegrees(end), Voltage, 5)

        .animationPhase = Math.fract(.animationPhase + .paintDeltaSeconds() * 0.7)
        .invalidate()
    }
}

impl ViewerLoadingSpinner
{
    // The spinner's box, and the radius and sweep its arc breathes between.
    const Size      = 56.0
    const MinRadius = 15.0
    const MaxRadius = 21.0
    const MinSweep  = 58.0
    const MaxSweep  = 232.0

    // Returns the arc drawn at `phase`, a fraction of one cycle: it breathes in radius and sweep
    // while it turns.
    func geometry(phase: f32)->{radius, start, sweep: f32}
    {
        let pulse = 0.5'f32 - 0.5'f32 * Math.cos(phase * Math.ConstF32.TwoPi)

        var result: #returntype
        result.radius = Math.lerp(MinRadius, MaxRadius, pulse)
        result.sweep  = Math.lerp(MinSweep, MaxSweep, pulse)
        result.start  = phase * 540 - 90 - result.sweep * 0.5
        return result
    }
}

impl ViewerLoadingOverlay
{
    // How long the overlay takes to fade in once the wait has lasted long enough to show it.
    const FadeIn: Time.Duration = 120'ms

    func create(parent: *Wnd)->*ViewerLoadingOverlay
    {
        with let result = Wnd.create'ViewerLoadingOverlay(parent, "scope.loading")
        {
            .wndFlags                |= WndFlags.TopMost | WndFlags.Disabled
            .backgroundStyle         = .Transparent
            .spinner                 = Wnd.create'ViewerLoadingSpinner(result, {0, 0, ViewerLoadingSpinner.Size, ViewerLoadingSpinner.Size})
            .spinner.backgroundStyle = .Transparent
            .hide()
        }

        return result
    }

    // Covers `rect`, expressed in the shared parent coordinates; painting centers the activity mark.
    mtd cover(rect: Math.Rectangle)
    {
        let size = ViewerLoadingSpinner.Size
        .setPosition(rect, computeLayout: false)
        .spinner.setPosition(Math.Rectangle{(rect.width - size) * 0.5, (rect.height - size) * 0.5, size, size}, computeLayout: false)
    }

    // Shows the mark, fading it in unless motion is reduced.
    mtd reveal()
    {
        if .isLocallyVisible() do
            return
        .show()

        let animator = &.app().animator
        if animator.isActive(.fadeAni) do
            animator.cancel(.fadeAni)
        if .app().isReducedMotion()
        {
            .setPresentationOpacity(1)
            return
        }

        .setPresentationOpacity(0)
        var fade: AnimationOptions
        fade.duration = FadeIn
        fade.easing   = .EaseOut
        .fadeAni      = animator.animateF32(me, AnimationChannel.from("scope.Loading.Opacity"), 0, 1, func(wnd, value) { wnd.setPresentationOpacity(value) }, fade)
    }

    // Hides the mark at once; a wait that ends is not announced.
    mtd conceal()
    {
        let animator = &.app().animator
        if animator.isActive(.fadeAni) do
            animator.cancel(.fadeAni)
        .hide()
    }
}

impl ViewerErrorView
{
    // Width the failure text wraps at.
    const TextWidth = 512.0

    // Creates the error surface that states `reason` under the standard decoder-failure heading.
    func create(parent: *Wnd, reason: string)->*ViewerErrorView
    {
        let result = Wnd.create'ViewerErrorView(parent, "scope.error")
        result.backgroundStyle = .View

        with let stack = StackLayoutCtrl.create(result, .VerticalCenter)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .spacing   = 8
        }

        with result.iconLabel = Label.create(stack, "", {0, 0, 48, 48})
        {
            .layoutSpec.alignX = .Center
            .setIcon(result.theme().icon(.Critical, 48))
            .setIconColor(result.themeColors().critical)
        }

        with result.summaryLabel = Label.create(stack, appStrings().ui_ViewerError, {0, 0, TextWidth, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        with result.reasonLabel = Label.create(stack, reason, {0, 0, TextWidth, 0}, null, .WordWrap | .AutoHeight)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        result.applyLayout()
        return result
    }

    mtd retranslate()
    {
        .summaryLabel.setText(appStrings().ui_ViewerError)
    }

    mtd refreshTheme()
    {
        .iconLabel.setIcon(.theme().icon(.Critical, 48))
        .iconLabel.setIconColor(.themeColors().critical)
    }
}
