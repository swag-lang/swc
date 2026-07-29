#global public

using Core

// Defines the operations supported by i event.
interface IEvent {}

// Represents event.
struct Event
{
    type:     #null typeinfo // Type associated with this value.
    target:   #null *Wnd // Target associated with this value.
    accepted: bool // Accepted associated with this value.
}

impl Event
{
    // Performs the create operation.
    func(T) create()->*T
    {
        let res = Memory.new'T()
        res.type = #typeof(T)
        return res
    }
}

impl IEvent for Event {}

// Represents command event.
struct CommandEvent
{
    using base: Event // Embedded base state.
    id:         WndId = undefined // Id associated with this value.
    source:     #null *Wnd // Source associated with this value.
}

impl IEvent for CommandEvent {}

// Represents command state event.
struct CommandStateEvent
{
    // Selects which command-state fields carry an updated value.
    #[Swag.EnumFlags]
    enum SetFlags
    {
        Zero = 0 // No flags are enabled.
        Disabled // Enables disabled.
        Icon // Enables icon.
        Shortcut // Enables shortcut.
        Checked // Enables checked.
        Name // Enables name.
        LongName // Enables long name.
        ToolTip // Enables tool tip.
        Hidden // Enables hidden.
        RenderingHint // Enables rendering hint.
    }

    // Provides presentation hints for a command.
    #[Swag.EnumFlags]
    enum RenderingHint
    {
        Zero = 0 // No flags are enabled.
        ExclusiveGroup // Selects exclusive group.
    }

    // Selects whether command state is being computed or applied.
    enum Kind
    {
        ComputeCommandState // Selects the compute command state kind.
        ApplyCommandState // Selects the apply command state kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind // Kind associated with this value.
    id:         WndId = undefined // Id associated with this value.
    source:     #null *Wnd // Source associated with this value.

    icon:          Icon // Icon associated with this value.
    name:          String // Name associated with this value.
    longName:      String // Long name associated with this value.
    shortcut:      String // Shortcut associated with this value.
    toolTip:       String // Tool tip associated with this value.
    setFlags:      SetFlags // Set flags associated with this value.
    renderingHint: RenderingHint // Rendering hint associated with this value.
    disabled:      bool // Disabled associated with this value.
    checked:       bool // Checked associated with this value.
    hidden:        bool // Hidden associated with this value.
}

impl IEvent for CommandStateEvent {}

// Represents timer event.
struct TimerEvent
{
    using base: Event // Embedded base state.
    timer:      *Timer = undefined // Timer associated with this value.
}

impl IEvent for TimerEvent {}

// Represents frame event.
struct FrameEvent
{
    using base: Event // Embedded base state.
    firstFrame: bool // First frame associated with this value.
}

impl IEvent for FrameEvent {}

// Represents create event.
struct CreateEvent
{
    using base: Event // Embedded base state.
}

impl IEvent for CreateEvent {}

// Represents state event.
struct StateEvent
{
    // Identifies the window-state transition.
    enum Kind
    {
        // Sent once, the first time a surface is shown, *before* the window
        // becomes visible. Perform slow first-time initialization here
        // (restoring state, loading content, resizing): the surface is
        // guaranteed not to be displayed until this returns and a first frame
        // has been rendered, so there is no black/empty flash on startup.
        Init // Selects the init kind.
        Show // Selects the show kind.
        Hide // Selects the hide kind.
        Disable // Selects the disable kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind // Kind associated with this value.
}

impl IEvent for StateEvent {}

// Represents destroy event.
struct DestroyEvent
{
    using base: Event // Embedded base state.
}

impl IEvent for DestroyEvent {}

// Represents paint event.
struct PaintEvent
{
    // Identifies the phase of window painting.
    enum Kind
    {
        PrePaint // Selects the pre paint kind.
        Paint // Selects the paint kind.
        PostPaint // Selects the post paint kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind          = .Paint // Kind associated with this value.
    bc:         *PaintContext = undefined // Bc associated with this value.
}

impl IEvent for PaintEvent {}

// Represents resize event.
struct ResizeEvent
{
    using base: Event // Embedded base state.
    oldSize:    Math.Point // Old size associated with this value.
}

impl IEvent for ResizeEvent {}

// Represents move event.
struct MoveEvent
{
    using base: Event // Embedded base state.
    oldPos:     Math.Point // Old pos associated with this value.
}

impl IEvent for MoveEvent {}

// Represents key event.
struct KeyEvent
{
    // Identifies a keyboard transition.
    enum Kind
    {
        KeyPressed // Selects the key pressed kind.
        KeyReleased // Selects the key released kind.
        Rune // Selects the rune kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind // Kind associated with this value.
    modifiers:  Input.KeyModifiers = Zero // Modifiers associated with this value.
    key:        Input.Key          = undefined // Key associated with this value.
    char:       rune // Char associated with this value.
}

impl IEvent for KeyEvent {}

// Represents mouse event.
struct MouseEvent
{
    // Identifies a mouse action or transition.
    enum Kind
    {
        MouseAccept // Selects the mouse accept kind.
        MousePressed // Selects the mouse pressed kind.
        MouseReleased // Selects the mouse released kind.
        MouseDoubleClick // Selects the mouse double click kind.
        MouseMove // Selects the mouse move kind.
        MouseEnter // Selects the mouse enter kind.
        MouseLeave // Selects the mouse leave kind.
        MouseWheel // Selects the mouse wheel kind.
        MouseSetCursor // Selects the mouse set cursor kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind // Kind associated with this value.
    button:     Input.MouseButton  = undefined // Button associated with this value.
    surfacePos: Math.Point // Surface pos associated with this value.
    move:       Math.Point // Move associated with this value.
    modifiers:  Input.KeyModifiers = Zero // Modifiers associated with this value.
}

impl IEvent for MouseEvent {}

// Represents quit event.
struct QuitEvent
{
    using base: Event // Embedded base state.
    quitCode:   s32 // Quit code associated with this value.
}

impl IEvent for QuitEvent {}

// Represents focus event.
struct FocusEvent
{
    // Identifies a keyboard-focus transition.
    enum Kind
    {
        SetFocus // Selects the set focus kind.
        KillFocus // Selects the kill focus kind.
        CanSetFocus // Selects the can set focus kind.
        CanKillFocus // Selects the can kill focus kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind // Kind associated with this value.
    other:      #null *Wnd // Other associated with this value.
    canChangeFocus = true // Can change focus associated with this value.
}

impl IEvent for FocusEvent {}

// Represents sys user event.
struct SysUserEvent
{
    using base: Event // Embedded base state.
    userMsg:    u64 // User msg associated with this value.
    param0:     u64 // Param0 associated with this value.
    param1:     u64 // Param1 associated with this value.
}

impl IEvent for SysUserEvent {}

// Represents sys command event.
struct SysCommandEvent
{
    // Identifies a command requested by the host window system.
    enum Kind
    {
        Minimize // Selects the minimize kind.
        Maximize // Selects the maximize kind.
        Restore // Selects the restore kind.
        Close // Selects the close kind.
        User // Selects the user kind.
    }

    using base: Event // Embedded base state.
    kind:       Kind // Kind associated with this value.
}

impl IEvent for SysCommandEvent {}

// Represents theme event.
struct ThemeEvent
{
    using base: Event // Embedded base state.
    style:      *ThemeStyle = undefined // Style associated with this value.
    parent:     #null *ThemeStyle // Parent associated with this value.
}

impl IEvent for ThemeEvent {}

// Represents serialize state event.
struct SerializeStateEvent
{
    using base: Event // Embedded base state.
    ser:        *Serialization.Serializer = undefined // Ser associated with this value.
}

impl IEvent for SerializeStateEvent {}

// Represents notify event.
struct NotifyEvent
{
    using base: Event // Embedded base state.

    // Identifies the semantic notification sent by a control.
    enum Kind
    {
        ChildFocusChanged // Selects the child focus changed kind.
        ThemeChanged // Selects the theme changed kind.
    }

    ntfyKind: Kind = undefined // Ntfy kind associated with this value.
    from:     #null *Wnd // From associated with this value.
}

impl IEvent for NotifyEvent {}

// Represents invalidate event.
struct InvalidateEvent
{
    using base: Event // Embedded base state.
}

impl IEvent for InvalidateEvent {}
