using Core, Pixel, Gui

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
//
// A failure reads as the charter's failures do: a critical dot before what happened, the exact
// reason of the decoder in faint mono under it, then the ways on: the other viewers the file can
// be seen in, and its own application. It is never a dead end.
struct ViewerErrorView
{
    using wnd: Wnd

    late
    {
        summaryLabel: *Label
        reasonLabel:  *Label
        actions:      *StackLayoutCtrl
    }
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

    late spinner: *Spinner
    fadeAni:      AnimationHandle
}

// One application-owned marker for every current occurrence. Viewers report the band they painted
// over what they revealed and nothing else; this layer supplies the air around it, the corner, the
// themed wash and its own edge, so PDF text and a byte in the hexadecimal
// view speak exactly the same visual language.
//
// The band takes the corner a selected row already takes, and its edge is drawn inside its
// outline rather than across it: a rule sitting half outside a translucent wash reads as a frame
// with something faint behind it instead of as one marked word.
struct ViewerSearchOverlay
{
    using wnd: Wnd
}

impl IWnd for ViewerSearchOverlay
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()

        let mark = .clientRect()
        if mark.isEmpty() do
            return

        painter.fillRoundRect(mark, MarkRadius, MarkRadius, colors.searchMatch_Bk)

        var pen = Pen.createSolid(colors.searchMatch_Border, MarkEdge)
        pen.borderPos = .Inside
        painter.drawRoundRect(mark, MarkRadius, MarkRadius, pen)
    }
}

impl ViewerSearchOverlay
{
    // The current occurrence stays still while its geometry follows the document.
    const MarkPadX       = 5.0
    const MarkTopInset   = 2.0
    const MarkMinHeight  = 18.0
    const MarkHeightPart = 0.64
    const MarkRadius     = 4.0
    const MarkEdge       = 1.0
    const InsetX         = MarkPadX

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
    // `bounds` is the line or cell band the view painted. Its lower leading often extends well
    // beyond the letters, so use a shorter mark near the top of the band while retaining the
    // reported horizontal extent. This keeps the air around the wording even on a tall line.
    mtd showMatch(bounds: Math.Rectangle)
    {
        let parent     = unwrap .parent
        let topLeft    = parent.surfaceToLocal(Math.Point{bounds.x, bounds.y})
        let markHeight = Math.max(MarkMinHeight, bounds.height * MarkHeightPart)
        .setPosition(Math.Rectangle{topLeft.x - InsetX, topLeft.y + MarkTopInset, bounds.width + InsetX * 2, markHeight}, computeLayout: false)
        .show()
        .bringToFront()
    }
}

impl ViewerLoadingOverlay
{
    // How long the overlay takes to fade in once the wait has lasted long enough to show it.
    const FadeIn: Time.Duration = 120'ms

    // Side of the activity mark: the toolkit's spinner, a size up from a row's, since it waits for a whole document.
    const SpinnerSize = 32.0

    func create(parent: *Wnd)->*ViewerLoadingOverlay
    {
        with let result = Wnd.create'ViewerLoadingOverlay(parent, "scope.loading")
        {
            .wndFlags                |= WndFlags.TopMost | WndFlags.Disabled
            .backgroundStyle         = .Transparent
            .spinner                 = Spinner.create(result, {0, 0, SpinnerSize, SpinnerSize})
            .spinner.backgroundStyle = .Transparent
            .hide()
        }

        return result
    }

    // Covers `rect`, expressed in the shared parent coordinates; painting centers the activity mark.
    mtd cover(rect: Math.Rectangle)
    {
        let size = SpinnerSize
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
    // Width the failure text wraps at, the diameter of the dot before it and the air between them.
    const TextWidth  = 512.0
    const DotSize    = 8.0
    const DotGap     = 10.0
    const MaxViewers = 2'u64     // Other viewers offered at most, beside the file's own application.

    // Creates the error surface that states `reason` under the standard decoder-failure heading.
    func create(parent: *Wnd, reason: string)->*ViewerErrorView
    {
        let result  = Wnd.create'ViewerErrorView(parent, "scope.error")
        let metrics = result.themeMetrics()
        result.backgroundStyle = .View

        with let stack = StackLayoutCtrl.create(result, .VerticalCenter)
        {
            .dockStyle = .Center
            .padding   = {48, 48, 48, 48}
            .spacing   = 8
        }

        with result.summaryLabel = Label.create(stack, appStrings().ui_ViewerError, {0, 0, TextWidth, 0}, null, .WordWrap | .AutoHeight)
        {
            .layoutSpec.alignX = .Center
            .style.setFont(result.theme().createDefaultFont(metrics.defaultFontSize + 2, .SemiBold), .Regular)
            .setTextAlignment(.Center, .Center)
        }

        with result.reasonLabel = Label.create(stack, reason, {0, 0, TextWidth, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .layoutSpec.alignX = .Center
            .style.setFont(result.theme().createDefaultFontFs(metrics.defaultFontSize - 1), .Regular)
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
            .setTextAlignment(.Center, .Center)
        }

        with result.actions = StackLayoutCtrl.create(stack, .HorizontalCenter, {0, 0, TextWidth, metrics.btnPush_Height})
        {
            .layoutSpec.alignX = .Center
            .margin.y          = 16
            .spacing           = 8
            .backgroundStyle   = .Transparent
            .hide()
        }

        result.applyLayout()
        return result
    }

    // Offers the viewers of `window` other than `failing` that have not failed on the file, and
    // the file's own application, as direct actions under the reason.
    mtd offer(window: *ViewerWindow, failing: u32)
    {
        while not .actions.children.isEmpty() do
            .actions.children.back().destroyNow()

        var offered = 0'u64
        for choice, index in window.choices where index != failing and offered < MaxViewers
        {
            if index < window.instances.count and not window.instances[index].failureReason.isEmpty() do
                continue
            let name   = window.index.plugins[choice.pluginIndex].displayName()
            let button = PushButton.create(.actions, Format.toString(appStrings().ui_ViewAsChoice, name), {}, null)
            let target = cast(u32, index)
            button.sigPressed += func|window, target|(_) { window.selectViewer(target) }
            button.fitWidthToLabel()
            offered += 1
        }

        let external = PushButton.create(.actions, appStrings().ui_MenuOpenDefault, {}, ViewerCommands.OpenDefault, .Flat)
        external.fitWidthToLabel()

        // The row is as wide as its buttons, which a language with longer words widens.
        var width = 0.0
        for child, i in .actions.children do
            width += child.position.width + (i ? .actions.spacing : 0)
        .actions.position.width  = Math.max(width, TextWidth)
        .actions.preferredSize.x = .actions.position.width
        .actions.show()
        .applyLayout()
        .invalidate()
    }

    mtd retranslate()
    {
        .summaryLabel.setText(appStrings().ui_ViewerError)
    }

    mtd refreshTheme()
    {
        .invalidate()
    }
}

impl IWnd for ViewerErrorView
{
    // The critical dot stands before the first word of what happened.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let label   = .summaryLabel
        let font    = .theme().createDefaultFont(.themeMetrics().defaultFontSize + 2, .SemiBold)
        let width   = Math.min(Painter.measureString(label.text(), font).width, label.position.width)
        let rect    = label.surfaceRect()
        let origin  = .surfaceToLocal(Math.Point{rect.horzCenter() - width * 0.5, rect.y})
        let lineY   = origin.y + Math.min(font.height, rect.height) * 0.5
        painter.setAntialiased(true)
        painter.fillCircle(origin.x - DotGap - DotSize * 0.5, lineY, DotSize * 0.5, .themeColors().critical)
    }
}
