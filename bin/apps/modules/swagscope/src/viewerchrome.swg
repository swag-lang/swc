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
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        .centerContent()
    }
}

impl ViewerActionBar
{
    func create(parent: *Wnd)->*ViewerActionBar
    {
        let result = Wnd.create'ViewerActionBar(parent, {0, 0, 0, ViewerActionBarHeight})
        result.dockStyle       = .Top
        result.backgroundStyle = .ToolBar
        result.padding         = {12, 6, 12, 0}
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
        let width          = preferredWidth > 0 ? Math.min(preferredWidth, client.width) : (.fillCenterGroup ? client.width : group.position.width)
        group.setPosition({client.horzCenter() - width * 0.5, client.vertCenter() - group.position.height * 0.5, width, group.position.height}, computeLayout: false)
        group.applyLayout()
    }
}

// Keeps file identity on the left and every reading of that file on the right.
//
// The general details and whatever the viewer adds to them form one run ending at the band's
// right edge, in that order. Anchoring the run there rather than centring the general details
// is what lets a long reading spend the whole band before it has to end in an ellipsis.
struct ViewerInfoLayout
{
    using wnd: Wnd

    late
    {
        filesButton:  *IconButton
        fileGroup:    *StackLayoutCtrl
        generalLabel: *Label
    }

    sideButton: *IconButton?
}

impl IWnd for ViewerInfoLayout
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        if .fileGroup != null and .generalLabel != null do
            .computeLayout()
    }
}

impl ViewerInfoLayout
{
    mtd computeLayout()
    {
        let client = .paddedClientRect()

        let filesWidth = .filesButton.isLocallyVisible() ? .filesButton.position.width : 0
        if filesWidth
        {
            .filesButton.setPosition({client.x, client.y, filesWidth, client.height}, computeLayout: false)
            .filesButton.applyLayout()
        }

        // The button that opens the panel of files and the file it opened read as one group, so
        // they sit closer together than two unrelated groups of the band do.
        let fileLeft     = client.x + (filesWidth ? filesWidth + ViewerInfoFileSpacing : 0)
        let maxFileWidth = Math.max(client.horzCenter() - fileLeft - ViewerInfoGroupSpacing, 0)
        let fileWidth    = Math.min(Math.ceil(.fileGroup.itf.measureContent({maxFileWidth, client.height}).x), maxFileWidth)
        .fileGroup.setPosition({fileLeft, client.y, fileWidth, client.height}, computeLayout: false)
        .fileGroup.computeLayout()

        var right = client.right()
        if .sideButton and .sideButton.isLocallyVisible()
        {
            let button = .sideButton
            right -= button.position.width
            button.setPosition({right, client.y, button.position.width, client.height}, computeLayout: false)
            button.applyLayout()
            right -= ViewerInfoSideButtonSpacing
        }

        // What the viewer contributes is measured first, because it says exactly what it needs;
        // the general details then spend everything that is left before they ellipsize.
        let leftBound = .fileGroup.position.right() + ViewerInfoGroupSpacing
        let available = Math.max(right - leftBound, 0)

        var viewers: Array'(*Wnd)
        for child in .children
        {
            if child == cast(*Wnd) .filesButton or child == cast(*Wnd) .fileGroup or child == cast(*Wnd) .generalLabel or (.sideButton and child == cast(*Wnd) .sideButton) or not child.isLocallyVisible() do
                continue
            viewers.add(child)
        }

        var widths: Array'f32
        var run:    f32
        for one in viewers
        {
            // The room a viewer reserved is its preferred size, never the width the last pass gave
            // it: reading the current width back would let the group only ever shrink.
            let spacing = run ? ViewerInfoGroupSpacing : 0
            let limit   = one.preferredSize.x > 0 ? one.preferredSize.x : one.position.width
            let wanted  = Math.min(Math.ceil(one.itf.measureContent({available, client.height}).x), limit)
            let width   = Math.max(Math.min(wanted, available - run - spacing), 0)
            widths.add(width)
            if width do
                run += spacing + width
        }

        let generalSpacing = run ? ViewerInfoGroupSpacing : 0
        let generalWanted  = .generalLabel.name.isEmpty() ? 0 : Math.ceil(.generalLabel.itf.measureContent({}).x)
        let generalWidth   = Math.max(Math.min(generalWanted, available - run - generalSpacing), 0)

        var x = right - run - generalWidth - (generalWidth ? generalSpacing : 0)
        .generalLabel.setPosition({x, client.y, generalWidth, client.height}, computeLayout: false)
        if generalWidth do
            x += generalWidth + generalSpacing

        for one, i in viewers
        {
            one.setPosition({x, client.y, widths[i], client.height}, computeLayout: false)
            one.applyLayout()
            if widths[i] do
                x += widths[i] + ViewerInfoGroupSpacing
        }
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
        mark.applyPadding({ViewerSearchGlowReach, ViewerSearchGlowReach, ViewerSearchGlowReach, ViewerSearchGlowReach})
        if mark.isEmpty() do
            return

        // The halo is a stack of filled rounded rectangles, drawn from the outermost inward: each
        // one covers those inside it, so their alphas add up toward the band while the outermost
        // ring stays a breath. Filling rather than stroking also keeps the whole marker off the
        // renderer's antialiased no-overlap pass, which clears alpha on a translucent top layer
        // and leaves seams as the pulse changes intensity.
        let glowStrength = (0.35'f32 + pulse * 0.65) / cast(f32) ViewerSearchGlowSteps
        let glow         = colors.searchMatch_Glow.withAlpha(cast(u8) (cast(f32) colors.searchMatch_Glow.a * glowStrength))
        for step in ViewerSearchGlowSteps
        {
            let reach = ViewerSearchGlowReach * cast(f32) (ViewerSearchGlowSteps - step) / cast(f32) ViewerSearchGlowSteps
            var ring  = mark
            ring.inflate(reach)
            painter.fillRoundRect(ring, ViewerSearchMarkRadius + reach, ViewerSearchMarkRadius + reach, glow)
        }

        painter.fillRoundRect(mark, ViewerSearchMarkRadius, ViewerSearchMarkRadius, colors.searchMatch_Bk)

        var pen = Pen.createSolid(colors.searchMatch_Border, ViewerSearchMarkEdge)
        pen.borderPos = .Inside
        painter.drawRoundRect(mark, ViewerSearchMarkRadius, ViewerSearchMarkRadius, pen)
    }
}

impl ViewerSearchOverlay
{
    func create(parent: *Wnd)->*ViewerSearchOverlay
    {
        let result = Wnd.create'ViewerSearchOverlay(parent, "scope.search.highlight")
        result.wndFlags        |= WndFlags.TopMost | WndFlags.Disabled
        result.backgroundStyle = .Transparent
        result.hide()
        return result
    }

    // Follows a surface-coordinate match without entering the viewer's own layout or hit testing.
    //
    // `bounds` is the band the view painted; the air is added here, wider than it is tall because
    // a line's leading is what bounds the marker vertically while nothing bounds it horizontally.
    mtd showMatch(bounds: Math.Rectangle)
    {
        let parent  = .parent!
        let topLeft = parent.surfaceToLocal(Math.Point{bounds.x, bounds.y})
        .setPosition({topLeft.x - ViewerSearchOverlayInsetX, topLeft.y - ViewerSearchOverlayInsetY, bounds.width + ViewerSearchOverlayInsetX * 2, bounds.height + ViewerSearchOverlayInsetY * 2}, computeLayout: false)
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
        let shape   = viewerLoadingSpinnerGeometry(.animationPhase)
        let end     = shape.start + shape.sweep

        painter.setAntialiased(true)
        painter.drawArc(center.x, center.y, shape.radius, Math.Angle.fromDegrees(shape.start), Math.Angle.fromDegrees(end), Ink, 9)
        painter.drawArc(center.x, center.y, shape.radius, Math.Angle.fromDegrees(shape.start), Math.Angle.fromDegrees(end), Voltage, 5)

        .animationPhase = Math.fract(.animationPhase + .timing().deltaSeconds * 0.7)
        .invalidate()
    }
}

impl ViewerLoadingOverlay
{
    func create(parent: *Wnd)->*ViewerLoadingOverlay
    {
        with let result = Wnd.create'ViewerLoadingOverlay(parent, "scope.loading")
        {
            .wndFlags                |= WndFlags.TopMost | WndFlags.Disabled
            .backgroundStyle         = .Transparent
            .spinner                 = Wnd.create'ViewerLoadingSpinner(result, {0, 0, ViewerLoadingSpinnerSize, ViewerLoadingSpinnerSize})
            .spinner.backgroundStyle = .Transparent
            .hide()
        }

        return result
    }

    // Covers `rect`, expressed in the shared parent coordinates; painting centers the activity mark.
    mtd cover(rect: Math.Rectangle)
    {
        .setPosition(rect, computeLayout: false)
        .spinner.setPosition({(rect.width - ViewerLoadingSpinnerSize) * 0.5, (rect.height - ViewerLoadingSpinnerSize) * 0.5, ViewerLoadingSpinnerSize, ViewerLoadingSpinnerSize}, computeLayout: false)
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
        fade.duration = ViewerLoadingFadeIn
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
            .setIconColor(result.themeColors().error)
        }

        with result.summaryLabel = Label.create(stack, appStrings().ui_ViewerError, {0, 0, ViewerErrorTextWidth, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        with result.reasonLabel = Label.create(stack, reason, {0, 0, ViewerErrorTextWidth, 0}, null, .WordWrap | .AutoHeight)
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
        .iconLabel.setIconColor(.themeColors().error)
    }
}

// The document header that names the open file, and answers for it.
//
// The panel is closed by default and the file being read is the one an action is wanted for most,
// so the header carries the same menu a panel row does.
struct ViewerInfoBar
{
    using wnd: Wnd
}

impl IWnd for ViewerInfoBar
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        // The labels the band holds decline the button, so the press arrives here having crossed
        // whichever one the pointer was over.
        if evt.kind != .Released or evt.button != .Right
        {
            evt.accepted = false
            return
        }

        (cast #assume(*ViewerWindow) .parent!.parent!).showCurrentFileActions(evt.surfacePos)
    }
}
