#global public

using Core, Pixel

// Names the hook event type.
alias HookEvent = func||(*Wnd, IEvent)->bool

// Selects automatic placement within the parent's padded client rectangle.
enum DockStyle
{
    None                   // Leaves the explicit position unchanged.
    Top                    // Takes the remaining top strip and keeps its height.
    Left                   // Takes the remaining left strip and keeps its width.
    Right                  // Takes the remaining right strip and keeps its width.
    Bottom                 // Takes the remaining bottom strip and keeps its height.
    Center                 // Fills the remaining rectangle.
    CenterKeepSizeVert     // Fills remaining width while preserving and centering its height.
}

// Selects which edges or dimensions follow a parent's size delta.
#[Swag.EnumFlags]
enum AnchorStyle
{
    None       // Keeps the explicit rectangle unchanged.
    Right      // Preserves the distance from the parent's right edge.
    Bottom     // Preserves the distance from the parent's bottom edge.
    Width      // Adds the parent's horizontal size delta to the width.
    Height     // Adds the parent's vertical size delta to the height.
}

// Selects a semantic theme background for a window.
enum BackgroundStyle
{
    Transparent     // Leaves the background transparent.
    Window          // Uses the standard top-level window background.
    Dialog          // Uses the dialog content background.
    DialogBar       // Uses the dialog command-bar background.
    View            // Uses the document or content-view background.
    Panel           // Uses the raised window ground with the theme's standalone-panel geometry.
}

// Selects how a window takes part in keyboard focus.
//
// One policy answers both questions a window has about the focus: whether a pointer press gives
// it the focus, and what the keyboard traversal of [[Gui.FocusOrder]] does when it reaches it.
//
// A composite stands in the traversal once, as one control, however many windows it is built
// from: it declares `Tab` on itself, points [[Gui.Wnd.focusDelegate]] at the window that reads
// the keys, and declares `Inner` on that window so nothing it builds below shows up as a second
// stop beside it.
enum FocusPolicy
{
    None      // Never takes the keyboard focus; the traversal walks through to the children.
    Click     // Takes the focus when pressed, without being a stop; the traversal walks through.
    Tab       // Takes the focus when pressed, and is one stop of the traversal.
    Inner     // Takes the focus when pressed, and hides itself and its children from the traversal.
}

// Selects how a layout container may size a window along one axis.
enum SizePolicy
{
    Fixed       // Forces minimum and maximum to the preferred size.
    Content     // Keeps the preferred size unless explicit bounds clamp it.
    Expand      // May shrink toward minimum or receive weighted surplus space.
}

// Selects placement within the cross-axis space assigned by a container.
enum LayoutAlign
{
    Start       // Aligns to the leading edge.
    Center      // Centers without changing the measured size.
    End         // Aligns to the trailing edge.
    Stretch     // Stretches to the available cross-axis size within bounds.
}

// Describes the minimum, preferred, and maximum size produced by measurement.
struct SizeHint
{
    public
    {
        min:       Math.Point                                    // Smallest valid width and height.
        preferred: Math.Point                                    // Natural width and height before surplus distribution.
        max:       Math.Point = {Swag.F32.Max, Swag.F32.Max}     // Largest valid width and height.
    }
}

// Configures container-driven sizing and alignment for one child window.
struct LayoutSpec
{
    public
    {
        policyX: SizePolicy  = SizePolicy.Content      // Horizontal size policy.
        policyY: SizePolicy  = SizePolicy.Content      // Vertical size policy.
        weightX: f32         = 1                       // Relative horizontal share of surplus space.
        weightY: f32         = 1                       // Relative vertical share of surplus space.
        alignX:  LayoutAlign = LayoutAlign.Stretch     // Horizontal alignment inside assigned space.
        alignY:  LayoutAlign = LayoutAlign.Stretch     // Vertical alignment inside assigned space.
        margin:  Math.Vector4                          // Additional left, top, right, and bottom layout margins.
    }
}

// Records the most recent measure and arrange decisions for diagnostics.
struct LayoutDebugInfo
{
    public
    {
        measuredMin:       Math.Point         // Minimum size reported by measurement.
        measuredPreferred: Math.Point         // Preferred size reported by measurement.
        measuredMax:       Math.Point         // Maximum size reported by measurement.
        contentSize:       Math.Point         // Size the window's own content reported, or zero when it reported none.
        arrangedRect:      Math.Rectangle     // Rectangle requested by the container after clamping.
        clippedX:          bool               // Whether assigned width was below the measured minimum.
        clippedY:          bool               // Whether assigned height was below the measured minimum.
        clampedByMinX:     bool               // Whether minimum width enlarged the requested rectangle.
        clampedByMinY:     bool               // Whether minimum height enlarged the requested rectangle.
        clampedByMaxX:     bool               // Whether maximum width reduced the requested rectangle.
        clampedByMaxY:     bool               // Whether maximum height reduced the requested rectangle.
    }
}

// Routes a key combination to a command identifier and optional target window.
struct KeyShortcut
{
    public
    {
        modifiers: Input.KeyModifiers = None          // Required modifier-key combination.
        key:       Input.Key          = None          // Required non-modifier key.
        id:        WndId              = undefined     // Command identifier sent on a match.
        target:    #null *Wnd                         // Explicit command target, or `null` to use normal routing.
    }
}

// Receives lifecycle, input, paint, command, and notification events for a [Wnd].
interface IWnd
{
    // Dispatches an arbitrary event to its typed callback.
    mtd onEvent(evt: IEvent)

    // Observes an event registered through the application's global hook list.
    mtd onHookEvent(evt: IEvent)

    // Handles attachment to a surface and completion of construction.
    mtd onCreateEvent(evt: *CreateEvent)

    // Handles destruction before owned resources and storage are released.
    mtd onDestroyEvent(evt: *DestroyEvent)

    // Handles visibility or enabled-state changes.
    mtd onStateEvent(evt: *StateEvent)

    // Handles a change to the window's logical size.
    mtd onResizeEvent(evt: *ResizeEvent)

    // Paints content scheduled before child windows.
    mtd onBeforePaint(evt: *PaintEvent)

    // Paints the window's primary content.
    mtd onPaint(evt: *PaintEvent)

    // Paints overlays scheduled after child windows.
    mtd onAfterPaint(evt: *PaintEvent)

    // Handles keyboard presses, releases, and character input.
    mtd onKeyEvent(evt: *KeyEvent)

    // Handles pointer buttons, movement, wheel input, and cursor queries.
    mtd onMouseEvent(evt: *MouseEvent)

    // Handles a drag and drop gesture passing over, or released on, this window.
    //
    // A window claims the gesture by setting [[Gui.DragDropEvent.effect]]; leaving it at `None`
    // lets the event bubble to the parent the way an unhandled mouse event does.
    mtd onDragDropEvent(evt: *DragDropEvent)

    // Handles a platform window-system command.
    mtd onSysCommandEvent(evt: *SysCommandEvent)

    // Handles an application-defined platform message.
    mtd onSysUserEvent(evt: *SysUserEvent)

    // Handles a resolved-theme change.
    mtd onThemeEvent(evt: *ThemeEvent)

    // Handles expiration of a timer owned by this window.
    mtd onTimerEvent(evt: *TimerEvent)

    // Handles keyboard-focus negotiation and changes.
    mtd onFocusEvent(evt: *FocusEvent)

    // Handles a command not consumed by an attached action.
    mtd onCommandEvent(evt: *CommandEvent)

    // Supplies current enabled, checked, visible, and text state for a command.
    mtd onComputeStateEvent(evt: *CommandStateEvent)

    // Applies command state to a presentation window.
    mtd onApplyStateEvent(evt: *CommandStateEvent)

    // Handles the start of a rendered application frame.
    mtd onFrameEvent(evt: *FrameEvent)

    // Reads or writes persistent UI state through the supplied serializer.
    mtd onSerializeStateEvent(evt: *SerializeStateEvent)

    // Handles framework notifications such as theme changes.
    mtd onNotifyEvent(evt: *NotifyEvent)

    // Returns the size this window's own content needs, or zero on an axis it cannot answer.
    //
    // A window that draws text, an icon, or items answers with what showing them whole
    // costs, so a caption never has to be measured by hand at the call site. `available`
    // is the space the container can offer, which is what a window whose height follows
    // its width — wrapped text — answers against; a zero component means the container
    // has no constraint to give on that axis.
    //
    // This is a query, not a routed event: it is asked of one window and never bubbles.
    // [[Gui.Wnd.measure]] uses the answer only on an axis the author left unsized, so an
    // explicit size always wins.
    mtd measureContent(available: Math.Point)->Math.Point
}

// Configures window state, clipping, paint order, sibling ordering, and keyboard role.
#[Swag.EnumFlags]
enum WndFlags
{
    None = 0                // No flags are enabled.
    NoScroll                // Ignores ancestor scroll offsets when computing surface coordinates.
    ClipChildren            // Clips child painting to this window's client rectangle.
    Disabled                // Rejects user input and uses disabled presentation.
    Hidden                  // Excludes the window from painting, input, and layout visibility.
    BeforeChildrenPaint     // Enables the before-children paint phase.
    AfterChildrenPaint      // Enables the after-children overlay paint phase.
    TopMost                 // Keeps the window after normal siblings in paint order.
    NoFocusRing             // Suppresses the keyboard-focus ring, for a control that shows the focus its own way.

    // Acts on the keyboard activation key rather than merely holding the focus.
    //
    // Every button says so: it presses, it toggles, it selects. A box never opens the keyboard on
    // such a control, because the first key its reader pressed would act instead of answering the
    // question; see [[Gui.Dialog.keyboardEntry]].
    ActivatesOnKey
}

// Forms one node in a retained GUI tree and provides layout, event, and painting services.
struct Wnd
{
    public
    {
        #[Swag.Late]
        itf: IWnd     // Dynamic event receiver implemented by the concrete window type.
        #[Swag.Late]
        type:     typeinfo                   // Runtime type of the concrete window allocation.
        surface:  #null *Surface             // Surface containing this window, or `null` while detached.
        style:    ThemeStyle                 // Local style and inherited theme reference.
        wndFlags = WndFlags.ClipChildren     // Active state, clipping, and paint-order flags.
        userData: #null *void                // Opaque application-owned payload; never dereferenced by GUI.

        position:      Math.Rectangle     // Logical rectangle relative to the parent client origin.
        preferredSize: Math.Point         // Natural layout size; non-positive components fall back to `position`.
        minSize:       Math.Point         // Inclusive minimum layout size.
        maxSize:       Math.Point         // Inclusive maximum layout size; zero components mean unbounded.
        scrollPos:     Math.Point         // Logical content offset applied to descendants.

        invalidatePadding: Math.Vector4     // Extra repaint extent around the logical rectangle.

        // Presentation-only state changes painting without moving layout, hit testing, or focus.
        readonly
        {
            presentationOpacity: f32        = 1              // Opacity of this window and its descendants, from zero through one.
            presentationOffset:  Math.Point                  // Paint-only displacement in logical pixels.
            presentationScale:   Math.Point = {1, 1}         // Paint-only horizontal and vertical scale factors, both positive.
            presentationPivot:   Math.Point = {0.5, 0.5}     // Fixed point of the scale, normalized inside the logical rectangle.
            presentationClip:    Math.Rectangle              // Local reveal rectangle when presentation clipping is enabled.
            hasPresentationClip: bool                        // Whether `presentationClip` limits painting.
        }

        parent: #null *Wnd     // Structural parent responsible for position, layout, and lifetime.
        owner:  #null *Wnd     // Logical owner used by popup and command routing when distinct from `parent`.

        // The child list is maintained by the window itself: attach through [setParent] and
        // detach through [detachChild] so parent, surface, style, and layout state stay consistent.
        readonly
        children: Array'(*Wnd)

        name:    RichString      // Display text with optional rich spans.
        id:      #null WndId     // Optional stable command, lookup, and persistence identifier.
        cursor:  Cursor          // Cursor requested while the pointer is over this window.
        toolTip: String          // Plain tooltip text; empty disables the tooltip.

        keyShortcuts: Array'KeyShortcut     // Key combinations routed from this subtree.
        actions:      Array'IActionUI       // Command actions exposed or consumed by this window.

        margin:      Math.Vector4           // Left, top, right, and bottom spacing outside the window.
        padding:     Math.Vector4           // Left, top, right, and bottom inset of the client area.
        dockStyle:   DockStyle   = None     // Legacy parent-relative docking behavior.
        anchorStyle: AnchorStyle = None     // Legacy response to parent-size deltas.
        layoutSpec:  LayoutSpec             // Container-driven measurement and arrangement policy.

        focusPolicy: FocusPolicy = None     // Pointer and traversal focus policy.

        // Corner of the shape this window paints, which the keyboard-focus ring follows so the two
        // never cross. A widget that draws a themed tile publishes it from that tile while painting —
        // see [[Gui.ThemeImageRect.radius]] — because the tile a palette points a control at is the
        // only thing that knows whether the control is a pill or a square this frame.
        //
        // Left at zero the ring keeps the soft corner of [[Gui.ThemeMetrics.focusRing_Radius]], which
        // is what a control with no shape of its own — a check box and its label, a slider, a tab —
        // should be marked with.
        focusRingRadius: f32

        // Fill the keyboard-focus ring will be drawn over, published the same way and for the same
        // reason: the ring points in the accent, and a control filled with that accent would swallow
        // it. A fully transparent value means the ring is not drawn over any known fill.
        focusRingGround: Color

        // Window the focus lands on when this one is given the focus, or `null` to take it.
        //
        // A composite declares the policy on itself and delegates the focus to the inner window
        // that actually handles the keys, so a caller holding the composite never has to know
        // which part of it edits, scrolls, or draws a caret.
        focusDelegate: #null *Wnd

        backgroundStyle: BackgroundStyle = Transparent     // Semantic theme background painted before content.
    }

    isAllocated:      bool     // Whether destruction must release this allocation.
    paintsWhenHidden: bool     // Whether a transition keeps this logically hidden subtree in the paint order.
    public
    {
        // Layout bookkeeping. The layout pass owns it: reading it tells what the window is doing,
        // writing it from outside would desynchronize the pass from the tree.
        readonly
        {
            isPendingDestroy: bool                // Whether the window is scheduled for destruction.
            managedByLayout:  bool                // Whether a layout container places this window.
            layoutDebug:      LayoutDebugInfo     // Last layout decision, for diagnostics.
        }
    }

    private
    {
        cachedSizeHint:  SizeHint        // Memoized measure result, refreshed by the layout pass.
        createEventDone: bool            // Whether the create event was already delivered.
        layoutDirty:     bool = true     // Whether the next frame must re-run layout.
    }

    public
    {
        hookOnEvent:      #null HookEvent     // Will be called before processing the event of the window
        hookOnChildEvent: #null HookEvent     // Will be called before processing whatever event of a child window
    }
}

impl IWnd for Wnd
{
    // Routes each concrete event to the corresponding typed callback.
    mtd impl onEvent(evt: IEvent)
    {
        switch evt
        {
        case CreateEvent as ptr:
            .itf.onCreateEvent(ptr)

        case DestroyEvent as ptr:
            .itf.onDestroyEvent(ptr)

        case StateEvent as ptr:
            .itf.onStateEvent(ptr)

        case ResizeEvent as ptr:
            .itf.onResizeEvent(ptr)

        case PaintEvent as ptr where ptr.kind == .Before:
            .itf.onBeforePaint(ptr)

        case PaintEvent as ptr where ptr.kind == .Content:
            .itf.onPaint(ptr)

        case PaintEvent as ptr where ptr.kind == .After:
            .itf.onAfterPaint(ptr)

        case SysCommandEvent as ptr:
            .itf.onSysCommandEvent(ptr)

        case SysUserEvent as ptr:
            .itf.onSysUserEvent(ptr)

        case KeyEvent as ptr:
            .itf.onKeyEvent(ptr)

        case MouseEvent as ptr where ptr.kind != .Accept:
            .itf.onMouseEvent(ptr)

        case DragDropEvent as ptr:
            .itf.onDragDropEvent(ptr)

        case ThemeEvent as ptr:
            .itf.onThemeEvent(ptr)

        case TimerEvent as ptr:
            .itf.onTimerEvent(ptr)

        case FocusEvent as ptr:
            .itf.onFocusEvent(ptr)

        case CommandEvent as ptr:
            if !.executeAction(ptr) do
                .itf.onCommandEvent(ptr)

        case CommandStateEvent as ptr where ptr.kind == .Compute:
            if !.updateAction(ptr) do
                .itf.onComputeStateEvent(ptr)

        case CommandStateEvent as ptr where ptr.kind == .Apply:
            .itf.onApplyStateEvent(cast(*CommandStateEvent) evt)

        case FrameEvent as ptr:
            .itf.onFrameEvent(ptr)

        case SerializeStateEvent as ptr:
            .itf.onSerializeStateEvent(ptr)

        case NotifyEvent as ptr:
            .itf.onNotifyEvent(ptr)
        }
    }

    // Ignores global hook events by default.
    mtd impl onHookEvent(evt: IEvent) {}

    // Reports no content size by default, which keeps the authored size on both axes.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available
        return {}
    }

    // Performs no additional creation work by default.
    mtd impl onCreateEvent(evt: *CreateEvent) {}

    // Releases no additional resources by default.
    mtd impl onDestroyEvent(evt: *DestroyEvent) {}

    // Ignores state changes by default.
    mtd impl onStateEvent(evt: *StateEvent) {}

    // Ignores size changes by default.
    mtd impl onResizeEvent(evt: *ResizeEvent) {}

    // Paints no before-children content by default.
    mtd impl onBeforePaint(evt: *PaintEvent) {}

    // Paints no primary content by default.
    mtd impl onPaint(evt: *PaintEvent) {}

    // Paints no after-children overlay by default.
    mtd impl onAfterPaint(evt: *PaintEvent) {}

    // Invalidates painting and requests layout after a theme change.
    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        .invalidate()
        .sendResizeEvent()
    }

    // Ignores timers by default.
    mtd impl onTimerEvent(evt: *TimerEvent) {}

    // Declines state serialization by default.
    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent) {}

    // Ignores frame callbacks by default.
    mtd impl onFrameEvent(evt: *FrameEvent) {}

    // Declines platform commands by default.
    mtd impl onSysCommandEvent(evt: *SysCommandEvent)
    {
        evt.accepted = false
    }

    // Declines application-defined platform messages by default.
    mtd impl onSysUserEvent(evt: *SysUserEvent)
    {
        evt.accepted = false
    }

    // Declines keyboard input by default.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
    }

    // Declines pointer input by default.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        evt.accepted = false
    }

    // Declines dropped payloads by default.
    mtd impl onDragDropEvent(evt: *DragDropEvent)
    {
        evt.accepted = false
    }

    // Declines focus events by default.
    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        evt.accepted = false
    }

    // Declines unhandled commands by default.
    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        evt.accepted = false
    }

    // Declines command-state computation by default.
    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        evt.accepted = false
    }

    // Declines command-state application by default.
    mtd impl onApplyStateEvent(evt: *CommandStateEvent)
    {
        evt.accepted = false
    }

    // Declines framework notifications by default.
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        evt.accepted = false
    }
}

impl Wnd
{
    // How far outside its logical rectangle a window is allowed to paint, in logical units.
    // Borders, focus rings and shadows all sit in this margin.
    private const PaintExtentMargin = 32'f32

    //////////////////////////////////////////////
    // Setup
    //////////////////////////////////////////////

    #[Swag.Inline]
    {
        // Returns the application that owns this window.
        mtd app() => .surface!.app

        // Returns the root content view of this window's surface.
        mtd topView() => .surface!.wnd.view

        // Returns the root surface window.
        mtd topWindow() => .surface!.wnd

        // Returns the resolved theme.
        mtd theme() => .style.refr!.theme

        // Returns the resolved theme metrics.
        mtd themeMetrics() => &.style.refr!.theme.metrics

        // Returns the resolved theme colors.
        mtd themeColors() => &.style.refr!.theme.colors

        // Returns the resolved theme image rectangles.
        mtd themeRects() => &.style.refr!.theme.rects

        // Returns the current frame timing.
        mtd timing() => &.surface!.app.timing

        // Returns the resolved font family.
        mtd font() => .style.resolvedFont()
    }

    // Allocates a concrete window with an empty name and rectangle.
    #[Swag.Inline]
    func(T) create(parent: #null *Wnd = null, id: #null WndId = null, hook: #null HookEvent = null)->*T
    {
        return create'T(parent, "", {}, id, hook)
    }

    #[Swag.Inline]
    // Allocates a concrete window with an empty name at `position`.
    func(T) create(parent: #null *Wnd, position: Math.Rectangle, id: #null WndId = null, hook: #null HookEvent = null)->*T
    {
        return create'T(parent, "", position, id, hook)
    }

    func(T) create(parent: #null *Wnd, name: #null string, position: Math.Rectangle, id: #null WndId = null, hook: #null HookEvent = null)->*T
    {
        let res = Memory.new'T()
        res.isAllocated = true
        res.itf         = res[]
        res.type        = T
        res.name.set(name)
        res.id            = id
        res.position      = position
        res.preferredSize = {position.width, position.height}
        res.isAllocated   = true
        res.hookOnEvent   = hook

        if parent
        {
            res.setParent(parent)
            res.sendCreateEvent()
            res.sendResizeEvent()
        }

        return res
    }

    // Destroy the window
    mtd destroyNow()
    {
        let srfn = .surface!
        Debug.assert(!.isPendingDestroy)

        // Each child's destroyWnd removes it from '.children': iterating the array while it
        // shrinks would skip every other child, so always consume the back one.
        while .children.count do
            .children.back().destroyNow()

        srfn.app.destroyWnd(me)
    }

    // Destroy the window
    mtd destroy()
    {
        let srfn = .surface!
        if .isPendingDestroy
        {
            .wndFlags.add(.Hidden)
            return
        }

        // The keyboard does not go down with the window: it continues to the stop that follows,
        // exactly as when the window is hidden. Done while the window is still in the traversal,
        // so where it stood is still known — otherwise the focus is simply dropped when the window
        // is finally unregistered, and the next Tab restarts at the top of the surface.
        .releaseFocus()
        .wndFlags.add(.Hidden)
        .isPendingDestroy = true

        // A streaming view can still own a short-period timer while it is replaced; retire those
        // timers now, while leaving posted commands and routing registration alive until the end
        // of the frame. A popup, for example, posts its selected command and then destroys itself.
        srfn.app.animator.cancelTarget(me)
        srfn.app.unregisterWndTimers(me)
        for c in .children do
            c.destroy()
        srfn.app.postDestroy.add(me)
        .invalidate()

        if .parent and !.parent.isPendingDestroy do
            .parent.applyLayout()
    }

    private mtd firstTopMostIndex()->u64
    {
        for c, i in .children
        {
            if c.wndFlags.has(.TopMost) do
                return i
        }

        return Swag.U64.Max
    }

    private mtd assignSurface(surface: #null *Surface)
    {
        .surface = surface
        for child in .children do
            child.assignSurface(surface)
    }

    // Reparents this window, or detaches it when `who` is `null`.
    //
    // The complete subtree follows the new surface. Cycles are rejected.
    mtd setParent(who: #null *Wnd)
    {
        if who == .parent do
            return

        if who
        {
            Debug.assert(who != me)
            Debug.assert(!.isAncestorOf(who), "cannot parent a window to its descendant")
        }

        if .parent
        {
            let oldParent = .parent!
            let detached  = oldParent.detachChild(me)
            Debug.assert(detached)
        }

        if who
        {
            .parent = who
            .assignSurface(who.surface)

            // Add the window at the back, or before the first topmost window
            if !who.children.count do
                who.children.add(me)
            else
            {
                var idxToInsert = who.children.count
                if !(.wndFlags & .TopMost)
                {
                    idxToInsert = who.firstTopMostIndex()
                    if idxToInsert == Swag.U64.Max do
                        idxToInsert = who.children.count
                }

                who.children.insertAt(idxToInsert, me)
            }

            who.invalidate()
        }
        else
        {
            .parent = null
            .assignSurface(null)
        }

        .computeStyle()
        .sendCreateEvent()
    }

    // Returns the explicit owner when present, otherwise the structural parent.
    mtd ownerOrParent()->#null *Wnd
    {
        return .owner orelse .parent
    }

    //////////////////////////////////////////////
    // State
    //////////////////////////////////////////////

    // Show the window
    mtd show(b = true)
    {
        if !b
        {
            .hide()
            return
        }

        if !.wndFlags.has(.Hidden) do
            return
        .wndFlags.remove(.Hidden)
        let parent = .parent!
        parent.invalidate()
    }

    // Hide the window
    mtd hide()
    {
        if .wndFlags.has(.Hidden) do
            return
        .releaseFocus()
        .sendHideStateEvent()
        .wndFlags.add(.Hidden)
        .app().unregisterWnd(me)
        let parent = .parent!
        parent.invalidate()
    }

    // Enable/Disable the window
    mtd enable(state = true)
    {
        if state
        {
            if !.wndFlags.has(.Disabled) do
                return
            .wndFlags.remove(.Disabled)
        }
        else
        {
            if .wndFlags.has(.Disabled) do
                return
            .releaseFocus()
            .sendDisableStateEvent()
            .wndFlags.add(.Disabled)
            .app().clearWndInputState(me)
        }

        .invalidate()
    }

    // Disable the window
    mtd disable()
    {
        .enable(false)
    }

    // Reports whether this window and every structural ancestor are visible.
    mtd isVisible()->bool
    {
        var toCheck: #null *Wnd = me
        while toCheck
        {
            if toCheck.wndFlags.has(.Hidden) do
                return false
            toCheck = toCheck.parent
        }

        return true
    }

    // Reports whether this window or a structural ancestor is hidden.
    mtd isHidden()->bool => !.isVisible()

    // Reports this window's own visibility flag, independently of its ancestors.
    mtd isLocallyVisible()->bool => !.wndFlags.has(.Hidden)

    // Reports whether this window and every structural ancestor are enabled.
    mtd isEnabled()->bool
    {
        var toCheck: #null *Wnd = me
        while toCheck
        {
            if toCheck.wndFlags.has(.Disabled) do
                return false
            toCheck = toCheck.parent
        }

        return true
    }

    // Reports whether this window or a structural ancestor is disabled.
    mtd isDisabled()->bool => !.isEnabled()

    // Reports this window's own enabled flag, independently of its ancestors.
    mtd isLocallyEnabled()->bool => !.wndFlags.has(.Disabled)

    //////////////////////////////////////////////
    // Paint
    //////////////////////////////////////////////

    // Computes style.
    mtd computeStyle()
    {
        let srf = .surface
        if srf do
            .style.compute(me, &srf.app.style)
    }

    // Paints this window and its visible descendants into `bc` in z-order.
    mtd paint(bc: *PaintContext)
    {
        let opacity = Math.saturate(.presentationOpacity)
        if opacity <= 0 do
            return

        let scaled = .presentationScale != Math.Point{1, 1}
        if opacity >= 1 and .presentationOffset == {} and !.hasPresentationClip and !scaled
        {
            .paintContent(bc)
            return
        }

        // A scale composites through a layer like a fading subtree does: descendants push their
        // clipping rectangles in unscaled parent space, so the transform has to apply once, to
        // the finished image, rather than to every recorded command.
        let painter = bc.painter
        if (opacity < 1 or scaled) and .position.width > 0 and .position.height > 0
        {
            var layer: Layer
            layer.begin(painter, {
                width: cast(s32) Math.ceil(.position.width),
                height: cast(s32) Math.ceil(.position.height)})

            // `paintContent` is authored in parent coordinates. Move that parent origin so the
            // target's logical rectangle records at the layer origin.
            painter.translateTransform(-.position.x, -.position.y)
            .paintContent(bc)
            layer.end()

            let destination = .presentationRect()

            painter.pushState()
            if .hasPresentationClip
            {
                var clip = .presentationClip
                clip.x, clip.width  *= .presentationScale.x
                clip.y, clip.height *= .presentationScale.y
                clip.offset(destination.x, destination.y)
                painter.pushClippingRect(clip)
            }

            layer.draw({
                dstRect: destination,
                color: Color.fromArgb(Argb.White).withAlphaF32(opacity),
                writeAlpha: false})

            if .hasPresentationClip do
                painter.popClippingRect()
            painter.popState()
            return
        }

        painter.pushState()
        painter.translateTransform(.presentationOffset.x, .presentationOffset.y)
        if .hasPresentationClip
        {
            var clip = .presentationClip
            clip.offset(.position.x, .position.y)
            painter.pushClippingRect(clip)
        }

        .paintContent(bc)

        if .hasPresentationClip do
            painter.popClippingRect()
        painter.popState()
    }

    private mtd paintContent(bc: *PaintContext)
    {
        let painter = bc.painter
        if painter.isEmptyClippingRect() do
            return

        // Recompute style if necessary
        .computeStyle()

        // Transmit disabled state to children
        let lastDisabled = bc.isDisabled
        if .wndFlags.has(.Disabled) do
            bc.isDisabled = true

        // Background
        let theme = .theme()
        switch .backgroundStyle
        {
        case .Window:    painter.fillRect(.position, theme.colors.wnd_Bk)
        case .Panel:     theme.drawSubRect(painter, .position, &theme.rects.panel_Bk, theme.colors.wnd_Bk)
        case .Dialog:    painter.fillRect(.position, theme.colors.dlg_Bk)
        case .View:      painter.fillRect(.position, theme.colors.view_Bk)
        case .DialogBar: theme.drawSubRect(bc.painter, .position, &theme.rects.dlg_BtnBar, theme.colors.dlg_BtnBarBk)
        }

        painter.translateTransform(.position.x, .position.y)
        let curTrs = painter.transform()
        var evt    = PaintEvent{}
        evt.paintContext = bc

        // Pre paint. Clipping is parent. No scroll
        if .wndFlags.has(.BeforeChildrenPaint)
        {
            evt.kind = .Before
            painter.pushState()
            .sendEvent(&evt)
            painter.popState()
        }

        // Clipping
        if .wndFlags.has(.ClipChildren) do
            painter.pushClippingRect(.clientRect())

        if !painter.isEmptyClippingRect()
        {
            // Me
            if !.wndFlags.has(.NoScroll) do
                painter.translateTransform(-.scrollPos.x, -.scrollPos.y)
            evt.kind = .Content
            painter.pushState()
            .sendEvent(&evt)
            painter.popState()
            painter.setTransform(curTrs)

            // A logically hidden transition page is a backdrop, so it is painted before every
            // visible sibling independently of their structural order.
            for c in .children where c.wndFlags.has(.Hidden) and c.paintsWhenHidden and !c.isPendingDestroy do
                .paintChild(bc, c)

            for c in .children where !c.wndFlags.has(.Hidden) do
                .paintChild(bc, c)

            if .managedByLayout and .surface and (.surface).app.options.showLayoutRects
            {
                painter.drawRect(.clientRect(), Color.fromArgb(0x66FFCC00), 1)
            }
        }

        // Restore clipping
        if .wndFlags.has(.ClipChildren) do
            painter.popClippingRect()

        // Post paint. Clipping is parent. No scroll
        if .wndFlags.has(.AfterChildrenPaint)
        {
            painter.setTransform(curTrs)
            evt.kind = .After
            painter.pushState()
            .sendEvent(&evt)
            painter.popState()
        }

        // Where the keyboard is, drawn once for every control instead of once per widget: the
        // ring belongs to the traversal stop, which is the whole control the user is standing on,
        // and it goes over the content so a filled button still shows it. A control that already
        // says it another way — a caret, a selected row, a highlighted cell — carries
        // [[Gui.WndFlags.NoFocusRing]] and paints nothing here.
        if .focusPolicy == .Tab and !.wndFlags.has(.NoFocusRing) and !bc.isDisabled and .showsFocusRing()
        {
            painter.setTransform(curTrs)
            theme.drawFocusRing(painter, .clientRect(), .focusRingRadius, .focusRingGround)
        }

        bc.isDisabled = lastDisabled
        .style.dirty  = false
    }

    private mtd paintChild(bc: *PaintContext, child: *Wnd)
    {
        let painter = bc.painter
        painter.pushState()
        if !child.wndFlags.has(.NoScroll) do
            painter.translateTransform(-.scrollPos.x, -.scrollPos.y)

        // A window that cannot reach the region being repainted is skipped whole, rather than
        // recording commands for the painter to clip away. A repaint is usually one control
        // wide -- a caret, a hovered row, the picture of a playing video -- while the tree it
        // sits in is the whole window, so this is most of the frame.
        //
        // Only a window whose subtree stays inside its own rectangle can be rejected on that
        // rectangle: one with no children, and one that clips the children it has. Any other
        // may have a descendant reaching outside it, and nothing here records how far.
        if child.children.isEmpty() or child.wndFlags.has(.ClipChildren)
        {
            var bounds = child.presentationRect()
            bounds.offset(painter.transform().tx, painter.transform().ty)
            if !child.paintExtent(bounds).intersects(painter.clippingRect())
            {
                let srf = .surface
                if srf do
                    srf.skippedWnds += 1
                painter.popState()
                return
            }
        }

        let srf = .surface
        if srf do
            srf.paintedWnds += 1
        child.paint(bc)
        painter.popState()
    }

    // Grows a rectangle of this window to everything the window may paint into.
    //
    // A window draws a border, a focus ring or a shadow outside its logical rectangle, so the
    // region [invalidate] marks dirty is wider than [position]. A paint pass rejects a window on
    // the same rectangle, and that is why the two share this: rejecting on a tighter bound than
    // the one that was dirtied would leave the difference stale on screen.
    mtd const paintExtent(rect: Math.Rectangle)->Math.Rectangle
    {
        var result: retval = rect
        result.applyPadding(.invalidatePadding)
        result.applyPadding({-PaintExtentMargin, -PaintExtentMargin, -PaintExtentMargin, -PaintExtentMargin})
        return result
    }

    // Force the window to be repainted
    mtd invalidate()
    {
        let srf = .surface
        if srf do
            srf.invalidateRect(.paintExtent(.surfaceRect()))
    }

    // Invalidates one local rectangle after converting it to surface coordinates.
    mtd invalidateRect(rect: Math.Rectangle)
    {
        let srf = .surface
        if srf do
            srf.invalidateRect(.localToSurface(rect))
    }

    // Returns the rectangle this window paints into, in parent coordinates.
    //
    // Presentation state moves and scales the painted image without moving [position], so this is
    // where the window is seen while [presentationOffset] or [presentationScale] is not at rest.
    // Layout, hit testing, and focus keep using [position].
    mtd const presentationRect()->Math.Rectangle
    {
        var result: retval = .position
        let pivotX         = result.x + result.width * .presentationPivot.x
        let pivotY         = result.y + result.height * .presentationPivot.y
        result.x      = pivotX + (result.x - pivotX) * .presentationScale.x
        result.y      = pivotY + (result.y - pivotY) * .presentationScale.y
        result.width  *= .presentationScale.x
        result.height *= .presentationScale.y
        result.offset(.presentationOffset)
        return result
    }

    private mtd invalidatePresentation()
    {
        let anchor = .surfaceRect()
        var rect   = .presentationRect()
        rect.offset(anchor.x - .position.x, anchor.y - .position.y)
        let srf = .surface
        if srf do
            srf.invalidateRect(.paintExtent(rect))
    }

    // Keeps a logically hidden window in its parent's paint order during a visual handoff.
    internal mtd setPaintWhenHidden(enabled: bool)
    {
        if .paintsWhenHidden == enabled do
            return
        .paintsWhenHidden = enabled
        if .parent do
            .parent.invalidate()
    }

    // Changes paint-only opacity without changing layout, hit testing, or focus.
    mtd setPresentationOpacity(opacity: f32)
    {
        let value = Math.saturate(opacity)
        if .presentationOpacity == value do
            return
        .invalidatePresentation()
        .presentationOpacity = value
        .invalidatePresentation()
    }

    // Changes paint-only displacement without changing the logical window rectangle.
    mtd setPresentationOffset(offset: Math.Point)
    {
        if .presentationOffset == offset do
            return
        .invalidatePresentation()
        .presentationOffset = offset
        .invalidatePresentation()
    }

    // Changes the paint-only scale applied around [presentationPivot].
    //
    // Both factors must be positive. The subtree is composited once and then resampled, so a
    // factor far above one softens text; scale is meant for arrival, emphasis, and press
    // feedback rather than for zooming a view.
    mtd setPresentationScale(scale: Math.Point)
    {
        Debug.assert(scale.x > 0 and scale.y > 0)
        if .presentationScale == scale do
            return
        .invalidatePresentation()
        .presentationScale = scale
        .invalidatePresentation()
    }

    // Changes the fixed point of [presentationScale], normalized inside the logical rectangle.
    //
    // `{0.5, 0.5}` scales about the center, `{0, 0}` about the top-left corner. Values outside
    // the unit square are accepted and place the fixed point beyond the window.
    mtd setPresentationPivot(pivot: Math.Point)
    {
        if .presentationPivot == pivot do
            return
        .invalidatePresentation()
        .presentationPivot = pivot
        .invalidatePresentation()
    }

    // Limits painting to `clip`, expressed in local logical coordinates.
    mtd setPresentationClip(clip: Math.Rectangle)
    {
        if .hasPresentationClip and .presentationClip == clip do
            return
        .invalidatePresentation()
        .presentationClip    = clip
        .hasPresentationClip = true
        .invalidatePresentation()
    }

    // Removes the paint-only reveal rectangle.
    mtd clearPresentationClip()
    {
        if !.hasPresentationClip do
            return
        .invalidatePresentation()
        .hasPresentationClip = false
        .invalidatePresentation()
    }

    // Restores opaque, undisplaced, unscaled, unclipped presentation.
    mtd resetPresentation()
    {
        if .presentationOpacity == 1 and .presentationOffset == {} and .presentationScale == Math.Point{1, 1} and !.hasPresentationClip do
            return
        .invalidatePresentation()
        .presentationOpacity = 1
        .presentationOffset  = {}
        .presentationScale   = {1, 1}
        .presentationPivot   = {0.5, 0.5}
        .hasPresentationClip = false
        .invalidatePresentation()
    }

    //////////////////////////////////////////////
    // Layout sizing contract
    //////////////////////////////////////////////

    // Marks cached measurement dirty and propagates the invalidation to the root.
    mtd invalidateLayout()
    {
        .layoutDirty = true
        if .parent do
            .parent.invalidateLayout()
    }

    // Returns the component-wise sum of legacy and container layout margins.
    mtd layoutMargin()->Math.Vector4
    {
        return .margin + .layoutSpec.margin
    }

    // Resolves minimum, preferred, and maximum size for the available space.
    //
    // An axis the author left unsized is answered by [[Gui.IWnd.measureContent]], so a
    // button widens with its caption and a wrapped paragraph grows taller in a language
    // that says the same thing in more words. An axis carrying an explicit size keeps it.
    mtd measure(available: Math.Point)->SizeHint
    {
        var result: retval

        result.min   = .minSize
        result.max.x = .maxSize.x > 0 ? .maxSize.x : Swag.F32.Max
        result.max.y = .maxSize.y > 0 ? .maxSize.y : Swag.F32.Max

        result.preferred = .preferredSize

        // The content only answers where nothing was authored, which is what keeps every
        // hand-sized surface of the repository arranged exactly as before.
        var content: Math.Point
        if result.preferred.x <= 0 or result.preferred.y <= 0
        {
            content = .itf.measureContent(available)
            if result.preferred.x <= 0 do
                result.preferred.x = content.x
            if result.preferred.y <= 0 do
                result.preferred.y = content.y
        }

        if result.preferred.x <= 0 do
            result.preferred.x = .position.width
        if result.preferred.y <= 0 do
            result.preferred.y = .position.height
        if result.preferred.x <= 0 do
            result.preferred.x = result.min.x
        if result.preferred.y <= 0 do
            result.preferred.y = result.min.y

        result.min.x = Math.max(result.min.x, 0)
        result.min.y = Math.max(result.min.y, 0)

        if .layoutSpec.policyX == SizePolicy.Fixed do
            result.min.x = Math.max(result.min.x, result.preferred.x)
        if .layoutSpec.policyY == SizePolicy.Fixed do
            result.min.y = Math.max(result.min.y, result.preferred.y)

        result.max.x       = Math.max(result.max.x, result.min.x)
        result.max.y       = Math.max(result.max.y, result.min.y)
        result.preferred.x = Math.clamp(result.preferred.x, result.min.x, result.max.x)
        result.preferred.y = Math.clamp(result.preferred.y, result.min.y, result.max.y)

        if .layoutSpec.policyX == SizePolicy.Fixed do
            result.max.x = result.preferred.x
        if .layoutSpec.policyY == SizePolicy.Fixed do
            result.max.y = result.preferred.y

        .cachedSizeHint                = result
        .layoutDirty                   = false
        .layoutDebug.measuredMin       = result.min
        .layoutDebug.measuredPreferred = result.preferred
        .layoutDebug.measuredMax       = result.max
        .layoutDebug.contentSize       = content
        return result
    }

    // Clamps and applies a container-assigned rectangle, recording diagnostics.
    mtd arrange(rect: Math.Rectangle)
    {
        var pos    = rect
        let before = pos
        .clampSize(&pos)

        .managedByLayout = true
        .setPosition(pos, false)

        .layoutDebug.arrangedRect  = pos
        .layoutDebug.clippedX      = pos.width < .cachedSizeHint.min.x
        .layoutDebug.clippedY      = pos.height < .cachedSizeHint.min.y
        .layoutDebug.clampedByMinX = before.width < pos.width
        .layoutDebug.clampedByMinY = before.height < pos.height
        .layoutDebug.clampedByMaxX = before.width > pos.width
        .layoutDebug.clampedByMaxY = before.height > pos.height
    }

    // Prints this subtree's last measure and arrange decisions when diagnostics are enabled.
    mtd dumpLayoutTree()
    {
        let srf = .surface
        if srf and !srf.app.options.dumpLayoutTree do
            return
        .dumpLayoutTreeNode(0)
    }

    private mtd dumpLayoutTreeNode(depth: u32)
    {
        for depth do
            Console.print("  ")

        Console.println(.type.name,
                        " name=",
                        .name.raw,
                        " rect=",
                        .position.x,
                        ",",
                        .position.y,
                        ",",
                        .position.width,
                        ",",
                        .position.height,
                        " min=",
                        .layoutDebug.measuredMin.x,
                        "x",
                        .layoutDebug.measuredMin.y,
                        " pref=",
                        .layoutDebug.measuredPreferred.x,
                        "x",
                        .layoutDebug.measuredPreferred.y,
                        " max=",
                        .layoutDebug.measuredMax.x,
                        "x",
                        .layoutDebug.measuredMax.y,
                        " arranged=",
                        .layoutDebug.arrangedRect.x,
                        ",",
                        .layoutDebug.arrangedRect.y,
                        ",",
                        .layoutDebug.arrangedRect.width,
                        ",",
                        .layoutDebug.arrangedRect.height,
                        " clip=",
                        .layoutDebug.clippedX,
                        "/",
                        .layoutDebug.clippedY,
                        " clampMin=",
                        .layoutDebug.clampedByMinX,
                        "/",
                        .layoutDebug.clampedByMinY,
                        " clampMax=",
                        .layoutDebug.clampedByMaxX,
                        "/",
                        .layoutDebug.clampedByMaxY)

        for c in .children do
            c.dumpLayoutTreeNode(depth + 1)
    }

    //////////////////////////////////////////////
    // Coordinates
    //////////////////////////////////////////////

    // Be sure rect is fully inside the parent rectangle (if possible)
    mtd fitPosInParent(marginW, marginH: f32 = 0, simX, simY = false)
    {
        let parent = .parent!
        var pos    = .position
        if pos.x + pos.width > parent.position.width - marginW
        {
            if simX do
                pos.x -= (pos.width + marginH)
            else do
                pos.x = parent.position.width - pos.width - marginW
        }

        if pos.y + pos.height > parent.position.height - marginH
        {
            if simY do
                pos.y -= (pos.height + marginH)
            else do
                pos.y = parent.position.height - pos.height - marginH
        }

        if pos != .position do
            .setPosition(pos)
    }

    // Convert a physical screen coordinate to a logical surface coordinate (relative to my surface)
    mtd const screenToSurface(pos: Math.Point)->Math.Point
    {
        let srfn = .surface!
        return {(pos.x - srfn.position.x) / srfn.dpiScale, (pos.y - srfn.position.y) / srfn.dpiScale}
    }

    // Number of physical device pixels covered by one logical unit of this window.
    //
    // Pass it to [[Pixel.Painter.measureStringSnapped]] and
    // [[Pixel.Painter.computeTextDrawInfo]] so measured positions land on the same
    // device grid the text is drawn with.
    mtd const deviceScale()->f32
    {
        if !.surface do
            return 1
        return .surface!.dpiScale
    }

    // Convert a surface coordinate to a local coordinate (relative to me)
    mtd const surfaceToLocal(pos: Math.Point)->Math.Point
    {
        let r = .surfaceRect()
        return {pos.x - r.x, pos.y - r.y}
    }

    // Convert a local coordinate to a surface coordinate
    mtd const localToSurface(pos: Math.Point)->Math.Point
    {
        let r = .surfaceRect()
        return {pos.x + r.x, pos.y + r.y}
    }

    // Convert a local coordinate to a surface coordinate
    mtd const localToSurface(pos: Math.Rectangle)->Math.Rectangle
    {
        let r = .surfaceRect()
        return {pos.x + r.x, pos.y + r.y, pos.width, pos.height}
    }

    // Returns the unpadded local client rectangle.
    mtd const clientRect()->Math.Rectangle
    {
        return {0, 0, .position.width, .position.height}
    }

    // Returns the local client rectangle inset by [padding].
    mtd const paddedClientRect()->Math.Rectangle
    {
        var result: retval = .clientRect()
        result.applyPadding(.padding)
        return result
    }

    // Returns this window's rectangle in surface coordinates.
    mtd const surfaceRect()->Math.Rectangle
    {
        var result: retval  = .position
        var p               = .parent
        var ignoresAncestor = .wndFlags.has(.NoScroll)
        while p
        {
            result.x += p.position.x
            result.y += p.position.y
            if !ignoresAncestor
            {
                result.x -= p.scrollPos.x
                result.y -= p.scrollPos.y
            }

            ignoresAncestor = ignoresAncestor or p.wndFlags.has(.NoScroll)
            p               = p.parent
        }

        return result
    }

    // Returns this window's rectangle relative to `wnd`, or to the root when `null`.
    mtd const rectRelativeTo(wnd: #null *Wnd)->Math.Rectangle
    {
        var result: retval = .position
        var p              = .parent
        while p and p != wnd
        {
            result.x += p.position.x
            result.y += p.position.y
            p        = p.parent
        }

        return result
    }

    // Updates selected outer margins; `Swag.F32.Inf` leaves an edge unchanged.
    mtd setMargin(left, top, right, bottom: f32 = Swag.F32.Inf)
    {
        with me.margin
        {
            if left != Swag.F32.Inf do
                .x = left
            if top != Swag.F32.Inf do
                .y = top
            if right != Swag.F32.Inf do
                .z = right
            if bottom != Swag.F32.Inf do
                .w = bottom
        }

        if .parent do
            .parent.sendResizeEvent()
    }

    // Replaces all four margins with `value`.
    mtd setAllMargins(value: f32) => .setMargin(value, value, value, value)

    // Replaces the left, top, right, and bottom margins from `value`.
    mtd setAllMargins(value: Math.Vector4) => .setMargin(value.x, value.y, value.z, value.w)

    // Updates selected inner paddings; `Swag.F32.Inf` leaves an edge unchanged.
    mtd setPadding(left, top, right, bottom: f32 = Swag.F32.Inf)
    {
        with me.padding
        {
            if left != Swag.F32.Inf do
                .x = left
            if top != Swag.F32.Inf do
                .y = top
            if right != Swag.F32.Inf do
                .z = right
            if bottom != Swag.F32.Inf do
                .w = bottom
        }

        .sendResizeEvent()
    }

    // Replaces all four paddings with `value`.
    mtd setAllPaddings(value: f32) => .setPadding(value, value, value, value)

    // Replaces the left, top, right, and bottom paddings from `value`.
    mtd setAllPaddings(value: Math.Vector4) => .setPadding(value.x, value.y, value.z, value.w)

    // Removes a child from this window's child list without destroying it.
    //
    // The caller keeps ownership of `child`. Returns whether the child was in the list.
    mtd detachChild(child: *Wnd)->bool
    {
        let idx = Slice.findLinear(.children.toSlice(), child)
        if idx == Swag.U64.Max do
            return false
        .children.removeAtOrdered(idx)
        child.parent = null
        child.assignSurface(null)
        .invalidateLayout()
        .invalidate()
        return true
    }

    // Moves the last `count` children to `index`, keeping their relative order.
    //
    // Children built by appending can be placed at their final position in one step.
    mtd moveLastChildrenTo(index: u64, count: u64)
    {
        Debug.assert(count <= .children.count)
        Debug.assert(index + count <= .children.count)

        for i in count do
            .children.insertAt(index + i, .children[.children.count - count + i])
        .children.count -= count
    }

    // Moves this window before all siblings so it is painted behind them.
    mtd sendToBack()
    {
        let parent = .parent!
        if parent.children.front() == me do
            return

        let idx = Slice.findLinear(parent.children.toSlice(), me)
        Debug.assert(idx != Swag.U64.Max)

        parent.children.removeAtOrdered(idx)
        parent.children.insertAt(0, me)
    }

    // Moves this window after normal siblings so it is painted in front of them.
    mtd bringToFront()
    {
        let parent = .parent!
        if parent.children.back() == me do
            return

        let idx = Slice.findLinear(parent.children.toSlice(), me)
        Debug.assert(idx != Swag.U64.Max)

        // Put the window at the back, or just before the first topmost window
        var idxToReplace = parent.children.count - 1
        if !.wndFlags.has(.TopMost)
        {
            let firstTopMost = parent.firstTopMostIndex()
            if firstTopMost != Swag.U64.Max do
                idxToReplace = firstTopMost - 1
        }

        if idx == idxToReplace do
            return

        @assert(parent.children.buffer != null)
        swap(parent.children.buffer + idx, parent.children.buffer + idxToReplace)
    }

    // Move and size the wnd
    mtd setPosition(rect: Math.Rectangle, computeLayout = true)
    {
        .move(rect.x, rect.y)
        .resize(rect.width, rect.height, computeLayout)
    }

    // Move and size the wnd
    mtd setPosition(x, y, w, h: f32, computeLayout = true)
    {
        .move(x, y)
        .resize(w, h, computeLayout)
    }

    // Move the wnd
    mtd move(x, y: f32)
    {
        if .position.x == x and .position.y == y do
            return
        var evt = MoveEvent{}
        evt.oldPos  = {.position.x, .position.y}
        .position.x = Math.round(x)
        .position.y = Math.round(y)
        .sendEvent(&evt)
    }

    // Returns the width of a band docked left or right, measured when none was authored.
    //
    // `preferredSize` holds what the author asked for when the window was created and no
    // layout pass ever rewrites it, so it stays the authority across resizes and language
    // switches. Reading `position` instead would freeze the band on its first measured
    // width, and a longer caption would never widen it again.
    private mtd dockedWidth(pos: Math.Rectangle, client: Math.Rectangle)->f32
    {
        if .preferredSize.x > 0 do
            return pos.width
        return Math.max(.measure({client.width, pos.height}).preferred.x, 0)
    }

    // Returns the height of a band docked top or bottom, measured when none was authored.
    //
    // The band already carries its final width here, so wrapped text answers for the
    // width it will really be drawn at. The authored size is read from `preferredSize`
    // for the same reason as the horizontal case above.
    private mtd dockedHeight(pos: Math.Rectangle, client: Math.Rectangle)->f32
    {
        if .preferredSize.y > 0 do
            return pos.height
        return Math.max(.measure({pos.width, client.height}).preferred.y, 0)
    }

    private mtd clampSize(pos: *Math.Rectangle)
    {
        if .minSize.x > 0 do
            pos.width = Math.max(pos.width, .minSize.x)
        if .minSize.y > 0 do
            pos.height = Math.max(pos.height, .minSize.y)
        if .maxSize.x > 0 do
            pos.width = Math.min(pos.width, .maxSize.x)
        if .maxSize.y > 0 do
            pos.height = Math.min(pos.height, .maxSize.y)
    }

    // Resize the wnd
    mtd resize(width, height: f32, computeLayout = true)
    {
        var pos = Math.Rectangle{0, 0, Math.round(width), Math.round(height)}
        .clampSize(&pos)

        if computeLayout
        {
            .preferredSize = {pos.width, pos.height}
            .invalidateLayout()
        }

        if .position.width == pos.width and .position.height == pos.height do
            return

        var evt = ResizeEvent{}
        evt.oldSize      = {.position.width, .position.height}
        .position.width  = pos.width
        .position.height = pos.height

        .sendEvent(&evt)

        if computeLayout do
            .applyLayout(evt.oldSize)
    }

    // Apply the current layout (children constraints)
    mtd applyLayout()
    {
        .applyLayout({.position.width, .position.height})
    }

    mtd applyLayout(oldSize: Math.Point)
    {
        var clientRect = .paddedClientRect()

        var centerLayout: Array'(*Wnd)
        var oldSizes:     Array'Math.Point

        for c in .children
        {
            if c.anchorStyle == .None do
                continue

            var pos = c.position
            if c.anchorStyle & .Right and oldSize.x > 0
            {
                let oldM = oldSize.x - c.position.x
                pos.x = .position.width - oldM
            }

            if c.anchorStyle & .Bottom and oldSize.y > 0
            {
                let oldM = oldSize.y - c.position.y
                pos.y = .position.height - oldM
            }

            if c.anchorStyle & .Width and oldSize.x > 0
            {
                if .position.width - oldSize.x do
                    pos.width += .position.width - oldSize.x
            }

            if c.anchorStyle & .Height and oldSize.y > 0
            {
                pos.height += .position.height - oldSize.y
            }

            c.setPosition(pos, false)
        }

        for c in .children
        {
            oldSizes.add({c.position.width, c.position.height})
            if !c.isLocallyVisible() do
                continue
            switch c.dockStyle
            {
            case .Left:
                var pos = c.position
                pos.x = clientRect.x + c.margin.x
                pos.y = clientRect.y + c.margin.y
                pos.setBottom(clientRect.bottom() - c.margin.w)
                if c.maxSize.y > 0 and c.maxSize.y < pos.height and !(c.anchorStyle & .Bottom) do
                    pos.y = clientRect.vertCenter() - c.maxSize.y * 0.5
                pos.width = c.dockedWidth(pos, clientRect)
                c.setPosition(pos, false)
                let diff = c.margin.x + pos.width + c.margin.z
                clientRect.width -= diff
                clientRect.x     += diff

            case .Right:
                var pos = c.position
                pos.y = clientRect.y + c.margin.y
                pos.setBottom(clientRect.bottom() - c.margin.w)
                if c.maxSize.y > 0 and c.maxSize.y < pos.height and !(c.anchorStyle & .Bottom) do
                    pos.y = clientRect.vertCenter() - c.maxSize.y * 0.5
                pos.width = c.dockedWidth(pos, clientRect)
                pos.x     = clientRect.right() - pos.width - c.margin.z
                c.setPosition(pos, false)
                let diff = c.margin.x + pos.width + c.margin.z
                clientRect.width -= diff

            case .Top:
                var pos = c.position
                pos.x = clientRect.x + c.margin.x
                pos.y = clientRect.y + c.margin.y
                pos.setRight(clientRect.right() - c.margin.z)
                if c.maxSize.x > 0 and c.maxSize.x < pos.width and !(c.anchorStyle & .Right) do
                    pos.x = clientRect.horzCenter() - c.maxSize.x * 0.5
                pos.height = c.dockedHeight(pos, clientRect)
                c.setPosition(pos, false)
                let diff = c.margin.y + pos.height + c.margin.w
                clientRect.y      += diff
                clientRect.height -= diff

            case .Bottom:
                var pos = c.position
                pos.x = clientRect.x + c.margin.x
                pos.setRight(clientRect.right() - c.margin.z)
                if c.maxSize.x > 0 and c.maxSize.x < pos.width and !(c.anchorStyle & .Right) do
                    pos.x = clientRect.horzCenter() - c.maxSize.x * 0.5
                pos.height = c.dockedHeight(pos, clientRect)
                pos.y      = clientRect.bottom() - c.margin.w - pos.height
                c.setPosition(pos, false)
                let diff = c.margin.w + pos.height + c.margin.y
                clientRect.height -= diff

            case .Center, .CenterKeepSizeVert:
                centerLayout.add(c)
            }
        }

        for c in centerLayout
        {
            var pos = clientRect

            // Fill the remaining room horizontally, but keep vertical size and center
            if c.dockStyle == .CenterKeepSizeVert
            {
                pos.y      = pos.vertCenter() - c.position.height * 0.5
                pos.height = c.position.height
            }

            // Fill the remaining room
            else
            {
                pos.applyPadding(c.margin)
            }

            c.setPosition(pos, false)
        }

        for c, i in .children
        {
            if !c.isVisible() do
                continue
            c.applyLayout(oldSizes[i])
        }
    }

    // Returns the topmost descendant at parent-space coordinates.
    mtd windowAt(x, y: f32, includeDisabled, includeHidden = false)->#null *Wnd
    {
        if !.position.contains(x, y) do
            return null

        // Top level window is the last one painted, so it's the last
        // in the array.
        // So we must visit in reverse order
        for var i = cast(s32) .children.count - 1; i >= 0; i -= 1
        {
            let c = .children[i]
            if c.wndFlags.has(.Hidden) and !includeHidden do
                continue
            if c.wndFlags.has(.Disabled) and !includeDisabled do
                continue

            var pt = Math.Point{x - .position.x, y - .position.y}
            if !c.wndFlags.has(.NoScroll) do
                pt += .scrollPos
            let res = c.windowAt(pt.x, pt.y, includeDisabled, includeHidden)
            if res do
                return res
        }

        return me
    }

    // Reports whether `child` is a structural descendant of this window.
    mtd isAncestorOf(child: #null *Wnd)->bool
    {
        if !child do
            return false
        var p = child.parent
        while p
        {
            if p == me do
                return true
            p = p.parent
        }

        return false
    }

    // Reports whether `child` reaches this window through owner-or-parent routing.
    mtd isOwnerOf(child: #null *Wnd)->bool
    {
        if !child do
            return false
        var p = child.ownerOrParent()
        while p
        {
            if p == me do
                return true
            p = p.ownerOrParent()
        }

        return false
    }

    // Retrieve the child with the given id
    mtd childById(childId: string)->#null *Wnd
    {
        for c in .children
        {
            if c.id == childId do
                return c
            let res = c.childById(childId)
            if res do
                return res
        }

        return null
    }

    // Retrieve the parent with the given id
    mtd ancestorById(parentId: string)->#null *Wnd
    {
        var p = .parent
        while p
        {
            if p.id == parentId do
                return p
            p = p.parent
        }

        return null
    }

    //////////////////////////////////////////////
    // Mouse
    //////////////////////////////////////////////

    // Captures platform pointer input for this window.
    mtd captureMouse()
    {
        let srfn = .surface!
        srfn.app.captureMouse(me)
    }

    // Releases the application's current pointer capture.
    mtd releaseMouse()
    {
        let srfn = .surface!
        srfn.app.releaseMouse()
    }

    // Returns the window that currently owns pointer capture.
    mtd mouseCapture()->#null *Wnd
    {
        let srfn = .surface!
        return srfn.app.mouseCapture()
    }

    //////////////////////////////////////////////
    // Keyboard
    //////////////////////////////////////////////

    // Returns the window the focus lands on for this one, following the delegate chain.
    //
    // A window without a delegate answers itself, so this is the window that really holds the
    // focus, rather than the one a caller happens to be holding.
    mtd focusTarget()->*Wnd
    {
        var result = me
        while result.focusDelegate do
            result = result.focusDelegate!
        return result
    }

    // Reports whether keyboard traversal stops on this window.
    mtd isFocusStop()->bool => .focusPolicy == .Tab

    // Requests keyboard focus after both the old and new windows approve the transition.
    //
    // The focus goes to [[Gui.Wnd.focusTarget]], so asking a composite for the focus reaches
    // the part of it that reads the keys.
    mtd setFocus()
    {
        let target = .focusTarget()
        if target != me
        {
            target.setFocus()
            return
        }

        let srfn = .surface!
        if srfn.app.keyboardFocusWnd == me do
            return
        if !.isEnabled() do
            return

        let last = srfn.app.keyboardFocusWnd

        // Ask the window with the current focus if we can steal it
        if last
        {
            var evt = FocusEvent{kind: FocusEvent.Kind.CanLose, other: me}
            last.sendEvent(&evt)
            if !evt.canChangeFocus do
                return
        }

        // Ask the new window if it wants the focus
        {
            var evt = FocusEvent{kind: FocusEvent.Kind.CanGain, other: last}
            .sendEvent(&evt)
            if !evt.canChangeFocus do
                return
        }

        // Publish the new owner before Lost callbacks run. A callback can destroy the old
        // focused subtree; its releaseFocus must then see that the keyboard has already left it,
        // instead of recursively starting a second transition through a tree being dismantled.
        let lastSurface = last ? last.surface : null
        srfn.app.nativeFocusTransition = true
        srfn.setFocus()
        srfn.app.nativeFocusTransition = false
        srfn.app.keyboardFocusWnd      = me
        srfn.noteFocus(me)

        if last
        {
            last.invalidate()
            last.ownerNotifyEvent(.ChildFocusChanged)

            var evt = FocusEvent{kind: FocusEvent.Kind.Lost, other: me}
            last.sendEvent(&evt)
        }

        // The Lost callback is allowed to destroy the incoming control or deliberately move the
        // focus elsewhere. In either case that nested operation owns the resulting state.
        if .isPendingDestroy or srfn.app.keyboardFocusWnd != me do
            return

        var evt = FocusEvent{kind: FocusEvent.Kind.Gained, other: last}
        .sendEvent(&evt)
        .invalidate()

        // The dominant action of a surface is drawn on whichever action the keyboard would run,
        // so the button that carries it when the keyboard is elsewhere repaints on every move.
        // Both surfaces are told: the focus can cross from one to the other.
        if lastSurface do
            lastSurface.defaultButton?.invalidate()
        srfn.defaultButton?.invalidate()

        .ownerNotifyEvent(.ChildFocusChanged)
    }

    // Returns the keyboard-focused window on this surface, if any.
    mtd focusedWindow()->#null *Wnd
    {
        let surface = .surface
        if !surface do
            return null
        return surface.app.keyboardFocusWnd
    }

    // Reports whether this window currently owns keyboard focus.
    //
    // A composite that delegates its focus answers for its delegate, so a widget asks this
    // about itself and paints its focused state without knowing where the focus really sits.
    mtd hasFocus()->bool
    {
        let surface = .surface
        if !surface do
            return false
        return surface.app.keyboardFocusWnd == .focusTarget()
    }

    // Reports whether this window must show the keyboard focus.
    //
    // True only while the focus arrived from the keyboard: a control pressed with the pointer
    // keeps the focus without drawing a ring around it, the way the pointer already said which
    // control was acted on. See [[Gui.Application.focusVisible]].
    mtd hasVisibleFocus()->bool
    {
        let surface = .surface
        if !surface do
            return false
        return surface.app.focusVisible and .hasFocus()
    }

    // Reports whether the paint must draw the keyboard-focus ring on this window.
    //
    // It is [[Gui.Wnd.hasVisibleFocus]] plus the diagnostic that shows every ring of a surface at
    // once: only one control can hold the keyboard, so judging the mark against every shape a
    // palette answers for is otherwise a walk through the whole tab order, one screen at a time.
    // See [[Gui.ApplicationOptions.showFocusRings]].
    mtd showsFocusRing()->bool
    {
        let surface = .surface
        if !surface do
            return false
        return surface.app.options.showFocusRings or .hasVisibleFocus()
    }

    // Returns the topmost structural ancestor of this window, or itself when it has no parent.
    mtd rootWnd()->*Wnd
    {
        var result = me
        while result.parent do
            result = result.parent!
        return result
    }

    // Moves the keyboard focus to the next traversal stop, and reports whether one was found.
    //
    // The order is the reading order of the tree this window belongs to, and it wraps around,
    // so the focus never leaves the surface it started on.
    mtd focusNext(forward = true)->bool
    {
        let order = FocusOrder.around(me)
        let next  = order.next(me, forward)
        if !next do
            return false
        next.setFocus()
        return true
    }

    // Moves the keyboard focus inside its own group, and reports whether another stop was found.
    //
    // This is what the arrow keys walk; see [[Gui.FocusOrder.nextInGroup]] for what a group is.
    mtd focusNextInGroup(forward = true)->bool
    {
        let order = FocusOrder.around(me)
        let next  = order.nextInGroup(me, forward)
        if !next do
            return false
        next.setFocus()
        return true
    }

    // Gives the keyboard focus to the first traversal stop of this window's tree.
    //
    // Call it once a surface is fully built, so it opens ready for the keyboard: a form the user
    // can start typing into, a dialog that answers Tab from its first field. A focus that already
    // stands somewhere inside this tree is left where it is — the caller placed it on purpose —
    // and a tree with no stop at all keeps none.
    //
    // `preferred` is the stop to open on when the reading order is not what the surface means by
    // "start here": a box whose answer is a default action opens on that action, so the first
    // Enter presses what the box says it will and not what happens to read first. It is ignored
    // when it is not a stop of this tree.
    mtd setInitialFocus(preferred: #null *Wnd = null)
    {
        let order = FocusOrder.collect(me)
        let focus = .focusedWindow()
        if focus and order.indexOf(focus) >= 0 do
            return

        if preferred and order.indexOf(preferred) >= 0
        {
            preferred.setFocus()
            return
        }

        order.first()?.setFocus()
    }

    // Moves the keyboard focus out of this subtree before it stops accepting input.
    //
    // Hiding or disabling the window that owns the focus must not leave the keyboard pointed at
    // something the user can no longer act on. The focus continues to the first stop that
    // follows this subtree, wrapping around, and is simply dropped when nothing else can take
    // it. Called before the state actually changes, so the stop it leaves from is still known.
    internal mtd releaseFocus()
    {
        let focus = .focusedWindow()
        if !focus do
            return
        if focus != me and !.isAncestorOf(focus) do
            return

        let order = FocusOrder.around(me)
        let count = cast(s64) order.stops.count

        // Resume after the last stop this subtree owns, so a whole form going down hands the
        // keyboard to what follows the form rather than to the top of the surface.
        var from = order.indexOf(me)
        for stop, index in order.stops where stop == me or .isAncestorOf(stop) do
            from = cast(s64) index

        for var step = 1's64; step < count; step += 1
        {
            let candidate = order.stops[cast(u64) ((from + step) % count)]
            if candidate == me or .isAncestorOf(candidate) do
                continue
            candidate.setFocus()
            return
        }

        .app().keyboardFocusWnd = null
    }

    // Sends one synthetic key press to this window, and reports whether it was consumed.
    //
    // This is how a control is pressed without the focus being on it, the way Enter presses the
    // default button of a surface while the keyboard is still in a field.
    internal mtd sendKeyPress(key: Input.Key, modifiers = Input.KeyModifiers.None)->bool
    {
        var evt = KeyEvent{kind: .Pressed}
        evt.key       = key
        evt.modifiers = modifiers
        .sendEvent(&evt)
        return evt.accepted
    }

    // Registers or replaces a keyboard shortcut on this routing node.
    mtd registerKeyShortcut(modifiers: Input.KeyModifiers, key: Input.Key, wndId: WndId)
    {
        for &c in .keyShortcuts
        {
            if c.modifiers == modifiers and c.key == key
            {
                c.id = wndId
                return
            }
        }

        .keyShortcuts.add({modifiers, key, wndId})
    }

    // Resolves a shortcut locally, then through the owner or parent chain.
    mtd keyShortcut(modifiers: Input.KeyModifiers, key: Input.Key)->#null WndId
    {
        for c in .keyShortcuts
        {
            if c.modifiers == modifiers and c.key == key do
                return c.id
        }

        let p = .ownerOrParent()
        if p do
            return p.keyShortcut(modifiers, key)
        return null
    }

    // Formats the first shortcut associated with `wndId` in the routing chain.
    mtd keyShortcutName(wndId: WndId)->String
    {
        var result: retval
        for c in .keyShortcuts
        {
            if c.id == wndId
            {
                result = Input.formatKeyShortcut(c.modifiers, c.key)
                return result
            }
        }

        let p = .ownerOrParent()
        if p do
            return p.keyShortcutName(wndId)
        return result
    }

    //////////////////////////////////////////////
    // Events
    //////////////////////////////////////////////

    // Register a new timer for the given 'target'
    mtd addTimer(time: Time.Duration)->*Timer
    {
        return .app().addTimer(time, me)
    }

    // Removes a timer previously created for this window.
    mtd removeTimer(timer: *Timer)
    {
        .app().removeTimer(timer)
    }

    // Posts quit event.
    mtd postQuitEvent()
    {
        let srfn = .surface!
        srfn.app.postQuitEvent()
    }

    // Posts event.
    mtd postEvent(evt: IEvent)
    {
        let srfn = .surface!
        let ptr  = (evt as Event)!
        ptr.target = me
        srfn.app.postEvent(evt)
    }

    // Posts invalidate event.
    mtd postInvalidateEvent()
    {
        let evt = Event.create'InvalidateEvent()
        .postEvent(evt)
    }

    // Sends event.
    mtd sendEvent(evt: IEvent)
    {
        let srfn = .surface!
        let ptr  = (evt as Event)!
        ptr.target = me
        srfn.app.sendEvent(evt)
    }

    // Sends state event.
    mtd sendStateEvent(kind: StateEvent.Kind)
    {
        var evt = StateEvent{kind: kind}
        .sendEvent(&evt)
    }

    // Sends hide state event.
    mtd sendHideStateEvent()
    {
        .sendStateEvent(.Hide)
        for c in .children
        {
            if c.isLocallyVisible() do
                c.sendHideStateEvent()
        }
    }

    // Sends disable state event.
    mtd sendDisableStateEvent()
    {
        .sendStateEvent(.Disable)
        for c in .children
        {
            if c.isLocallyVisible() do
                c.sendDisableStateEvent()
        }
    }

    // Sends resize event.
    mtd sendResizeEvent()
    {
        var evt = ResizeEvent{}
        evt.oldSize.x = .position.width
        evt.oldSize.y = .position.height
        .sendEvent(&evt)
    }

    // Posts resize event.
    mtd postResizeEvent()
    {
        let evt = Event.create'ResizeEvent()
        evt.oldSize.x = .position.width
        evt.oldSize.y = .position.height
        .postEvent(evt)
    }

    // Sends create event.
    mtd sendCreateEvent()
    {
        if .createEventDone do
            return
        .createEventDone = true
        var evt = CreateEvent{}
        .sendEvent(&evt)
    }

    // Posts command event.
    mtd postCommandEvent(cmdId: #null WndId)
    {
        if cmdId == null do
            return
        let safeCmdId = cmdId orelse ""
        let evt       = Event.create'CommandEvent()
        evt.id     = safeCmdId
        evt.source = me
        .postEvent(evt)
    }

    // Invokes the local hook, then dispatches the event unless the hook consumes it.
    mtd processEvent(evt: IEvent)
    {
        var eat = false
        if .hookOnEvent do
            eat = .hookOnEvent(me, evt)
        if !eat do
            .itf.onEvent(evt)
    }

    // Send a notification event
    mtd notifyEvent(kind: NotifyEvent.Kind)
    {
        var ntfy = NotifyEvent{}
        ntfy.kind = kind
        .sendEvent(&ntfy)
    }

    // Send a notification event
    mtd ownerNotifyEvent(kind: NotifyEvent.Kind)
    {
        let p = .ownerOrParent()
        if !p do
            return
        p.notifyEvent(kind)
    }

    //////////////////////////////////////////////
    // Commands
    //////////////////////////////////////////////

    // Main function to update command state of various windows/widgets.
    // This will update the state of this window, and all of its children
    mtd updateCommandState()
    {
        var evtState = .sendComputeCommandStateEvent(.id)
        if evtState.accepted
        {
            evtState.kind = .Apply
            .sendEvent(&evtState)
            return
        }

        for c in .children do
            c.updateCommandState()
    }

    // Send the command state event with the given id to the window.
    // Computes and returns presentation state for `cmdId`, including resolved shortcuts.
    mtd sendComputeCommandStateEvent(cmdId: #null WndId)->CommandStateEvent
    {
        if cmdId == null do
            return {}
        let safeCmdId = cmdId orelse ""

        var evtState: retval
        @init(&evtState.name, 1)
        @init(&evtState.longName, 1)
        @init(&evtState.shortcut, 1)
        @init(&evtState.toolTip, 1)

        // User will fill the state
        evtState.kind   = .Compute
        evtState.id     = safeCmdId
        evtState.source = me
        .sendEvent(&evtState)

        // Is there a keyboard shortcut or a global hot key ?
        var sk = .keyShortcutName(safeCmdId)
        if !sk.length do
            sk = .app().hotKeyShortcutName(safeCmdId)
        if sk.length
        {
            evtState.updatedFields.add(.Shortcut)
            evtState.shortcut = sk
        }

        return evtState
    }

    // Send the command event with the given id to the window.
    // The command will be updated first, and if it is not disabled, it will be sent.
    mtd sendCommandEvent(cmdId: #null WndId)
    {
        if cmdId == null do
            return
        let safeCmdId = cmdId orelse ""

        // We first need to be sure that the target can deal with the event
        var evtState: CommandStateEvent
        @init(&evtState.name, 1)
        @init(&evtState.longName, 1)
        @init(&evtState.shortcut, 1)
        @init(&evtState.toolTip, 1)
        evtState.kind = .Compute
        evtState.id   = safeCmdId
        .sendEvent(&evtState)

        // If it's not disabled, then we can send
        if !evtState.updatedFields.has(.Disabled) or !evtState.disabled
        {
            var evtc = CommandEvent{}
            evtc.id = safeCmdId
            .sendEvent(&evtc)
        }
    }

    //////////////////////////////////////////////
    // Actions
    //////////////////////////////////////////////

    // Register one new action
    mtd(T) registerAction()
    {
        var itfAct = @mkinterface(null, #typeof(T), IActionUI)
        .actions.add(itfAct)
    }

    private mtd updateAction(evt: *CommandStateEvent)->bool
    {
        var cxt = ActionContext{me, evt.id orelse ""}

        for act in .actions
        {
            if act.accept(cxt)
            {
                evt.accepted = true
                if act.update(cxt, evt) do
                    return true
            }
        }

        return false
    }

    private mtd executeAction(evt: *CommandEvent)->bool
    {
        var cxt = ActionContext{me, evt.id orelse ""}

        for act in .actions
        {
            if act.accept(cxt)
            {
                evt.accepted = true
                if act.execute(cxt) do
                    return true
            }
        }

        return false
    }

    //////////////////////////////////////////////
    // Serialization
    //////////////////////////////////////////////

    // Offers persistent-state serialization to this window, then recursively to children if declined.
    mtd serializeState(ser: *Serialization.Serializer) fail
    {
        var evt: SerializeStateEvent
        evt.accepted   = false
        evt.serializer = ser
        evt.target     = me
        .processEvent(&evt)

        if !evt.accepted
        {
            for c in .children do
                c.serializeState(ser)
        }
    }
}
