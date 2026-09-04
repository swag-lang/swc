#global public

using Core

// Marker interface implemented by every GUI event.
interface IEvent {}

// Common routing state embedded by every GUI event.
struct Event
{
    type: #null typeinfo     // Concrete allocation type used for owned posted events.

    public
    {
        target:   #null *Wnd     // Current routing target; changes while an event bubbles.
        accepted: bool           // Whether propagation has been handled and must stop.
    }
}

impl Event
{
    // Allocates an owned event for `Wnd.postEvent`; the event queue releases it after dispatch.
    func(T) create()->*T
    {
        let res = Memory.new'T()
        res.type = #typeof(T)
        return res
    }
}

impl IEvent for Event {}

// Requests execution of a command identified by `id`.
struct CommandEvent
{
    public
    {
        using base: Event          // Embedded base state.
        id:         WndId = ""     // Command identifier.
        source:     #null *Wnd     // Window that originated the command, when known.
    }
}

impl IEvent for CommandEvent {}

// Carries computed presentation state for a command between handlers and presenters.
struct CommandStateEvent
{
    public
    {
        // Selects which command-state fields carry an updated value.
        #[Swag.EnumFlags]
        enum UpdatedFields
        {
            None = 0          // No flags are enabled.
            Disabled          // `disabled` contains an updated value.
            Icon              // `icon` contains an updated value.
            Shortcut          // `shortcut` contains an updated value.
            Checked           // `checked` contains an updated value.
            Name              // `name` contains an updated value.
            LongName          // `longName` contains an updated value.
            ToolTip           // `toolTip` contains an updated value.
            Hidden            // `hidden` contains an updated value.
            RenderingHint     // `renderingHint` contains an updated value.
        }

        // Provides presentation hints for a command.
        #[Swag.EnumFlags]
        enum RenderingHint
        {
            None = 0           // No flags are enabled.
            ExclusiveGroup     // The command belongs to a mutually exclusive group.
        }

        // Selects whether command state is being computed or applied.
        enum Kind
        {
            Compute     // A handler must provide the command's current presentation state.
            Apply       // Computed state is being applied to command presenters.
        }

        using base: Event          // Embedded base state.
        kind:       Kind           // Whether state is being computed or applied.
        id:         WndId = ""     // Command identifier.
        source:     #null *Wnd     // Window that requested the state, when known.

        icon:          Icon              // Command icon when [UpdatedFields.Icon] is present.
        name:          String            // Compact command label when [UpdatedFields.Name] is present.
        longName:      String            // Expanded command label when [UpdatedFields.LongName] is present.
        shortcut:      String            // Display-form shortcut when [UpdatedFields.Shortcut] is present.
        toolTip:       String            // Explanatory tooltip when [UpdatedFields.ToolTip] is present.
        updatedFields: UpdatedFields     // Identifies which presentation fields contain authoritative values.
        renderingHint: RenderingHint     // Presenter hints when [UpdatedFields.RenderingHint] is present.
        disabled:      bool              // Disabled state when [UpdatedFields.Disabled] is present.
        checked:       bool              // Checked state when [UpdatedFields.Checked] is present.
        hidden:        bool              // Hidden state when [UpdatedFields.Hidden] is present.
    }
}

impl IEvent for CommandStateEvent {}

// Signals that a registered timer has elapsed.
struct TimerEvent
{
    public
    {
        using base: Event     // Embedded base state.
        #[Swag.Late]
        timer: *Timer     // Timer that elapsed.
    }
}

impl IEvent for TimerEvent {}

// Signals one application frame.
struct FrameEvent
{
    public
    {
        using base: Event     // Embedded base state.
        firstFrame: bool      // Whether this is the first frame after startup.
    }
}

impl IEvent for FrameEvent {}

// Signals creation of a window.
struct CreateEvent
{
    public using base: Event     // Embedded base state.
}

impl IEvent for CreateEvent {}

// Signals a window-state transition.
struct StateEvent
{
    public
    {
        // Identifies the window-state transition.
        enum Kind
        {
            // Sent once, the first time a surface is shown, *before* the window
            // becomes visible. Perform slow first-time initialization here
            // (restoring state, loading content, resizing): the surface is
            // guaranteed not to be displayed until this returns and a first frame
            // has been rendered, so there is no black/empty flash on startup.
            Init        // Performs first-show initialization before the surface becomes visible.
            Show        // Signals transition to locally visible state.
            Hide        // Signals transition to locally hidden state.
            Disable     // Signals transition to locally disabled state.
        }

        using base: Event     // Embedded base state.
        kind:       Kind      // State transition being reported.
    }
}

impl IEvent for StateEvent {}

// Signals destruction of a window.
struct DestroyEvent
{
    public using base: Event     // Embedded base state.
}

impl IEvent for DestroyEvent {}

// Carries the context for one phase of window painting.
struct PaintEvent
{
    public
    {
        // Identifies the phase of window painting.
        enum Kind
        {
            Before      // Paint before the window's children.
            Content     // Paint the window's own content.
            After       // Paint after the window's children.
        }

        using base: Event               // Embedded base state.
        kind:       Kind = .Content     // Painting phase.
        #[Swag.Late]
        paintContext: *PaintContext     // Active painting context.
    }
}

impl IEvent for PaintEvent {}

// Signals a window resize.
struct ResizeEvent
{
    public
    {
        using base: Event          // Embedded base state.
        oldSize:    Math.Point     // Size before the resize.
    }
}

impl IEvent for ResizeEvent {}

// Signals a window move.
struct MoveEvent
{
    public
    {
        using base: Event          // Embedded base state.
        oldPos:     Math.Point     // Position before the move.
    }
}

impl IEvent for MoveEvent {}

// Carries a key transition or character input.
struct KeyEvent
{
    public
    {
        // Identifies a keyboard transition.
        enum Kind
        {
            Pressed       // A key transitioned to the pressed state.
            Released      // A key transitioned to the released state.
            Character     // Text input produced one Unicode character.
        }

        using base: Event                         // Embedded base state.
        kind:       Kind                          // Keyboard event kind.
        modifiers:  Input.KeyModifiers = None     // Modifiers held during the event.
        key:        Input.Key                     // Physical or logical key, when applicable.
        character:  rune                          // Input character for `Kind.Character`.
    }
}

impl IEvent for KeyEvent {}

// Carries a mouse transition, motion, wheel delta, or cursor query.
struct MouseEvent
{
    public
    {
        // Identifies a mouse action or transition.
        enum Kind
        {
            Accept          // Queries whether this target accepts pointer routing.
            Pressed         // A mouse button transitioned to the pressed state.
            Released        // A mouse button transitioned to the released state.
            DoubleClick     // A mouse button completed a double-click gesture.
            Move            // The pointer moved.
            Enter           // The pointer entered the window.
            Leave           // The pointer left the window.
            Wheel           // The mouse wheel moved.
            SetCursor       // The target must choose the active cursor.
        }

        using base: Event                         // Embedded base state.
        kind:       Kind                          // Mouse event kind.
        button:     Input.MouseButton             // Button involved in the transition.
        surfacePos: Math.Point                    // Pointer position in surface coordinates.
        delta:      Math.Point                    // Motion or wheel delta for this event.
        modifiers:  Input.KeyModifiers = None     // Modifiers held during the event.
    }
}

impl IEvent for MouseEvent {}

// Requests application termination.
struct QuitEvent
{
    public
    {
        using base: Event     // Embedded base state.
        quitCode:   s32       // Process exit code requested by the application.
    }
}

impl IEvent for QuitEvent {}

// Carries a keyboard-focus transition or validation request.
struct FocusEvent
{
    public
    {
        // Identifies a keyboard-focus transition.
        enum Kind
        {
            Gained      // The window gained keyboard focus.
            Lost        // The window lost keyboard focus.
            CanGain     // Queries whether the window may gain keyboard focus.
            CanLose     // Queries whether the window may lose keyboard focus.
        }

        using base: Event          // Embedded base state.
        kind:       Kind           // Focus event kind.
        other:      #null *Wnd     // Window at the other end of the focus transition.
        canChangeFocus = true      // Whether the queried focus transition is allowed.
    }
}

impl IEvent for FocusEvent {}

// Carries a portable application or notification-area event received from the host window system.
struct SysUserEvent
{
    public
    {
        // Identifies the portable source of a system user event.
        enum Kind
        {
            CustomMessage     // An application-defined message sent through [[Gui.Surface.sendCustomMessage]].
            TrayIcon          // An interaction with the surface's notification-area icon.
        }

        // Identifies an interaction with a notification-area icon.
        enum TrayAction
        {
            None            // The host interaction has no portable mapping.
            Activate        // The user activated the icon.
            ContextMenu     // The user requested the icon's context menu.
        }

        using base: Event          // Embedded base state.
        kind:       Kind           // Portable event source.
        messageId:  u32            // Application-defined identifier when `kind` is `CustomMessage`.
        param:      u64            // Application-defined parameter when `kind` is `CustomMessage`.
        trayAction: TrayAction     // Notification-area interaction when `kind` is `TrayIcon`.
    }
}

impl IEvent for SysUserEvent {}

// Carries a command requested by the host window system.
struct SysCommandEvent
{
    public
    {
        // Identifies a command requested by the host window system.
        enum Kind
        {
            Minimize     // Requests minimizing the host surface.
            Maximize     // Requests maximizing the host surface.
            Restore      // Requests restoring the host surface.
            Close        // Requests closing the host surface.
            User         // Carries a host-specific command not covered above.
        }

        using base: Event     // Embedded base state.
        kind:       Kind      // Host command being requested.
    }
}

impl IEvent for SysCommandEvent {}

// Signals a theme-style change.
struct ThemeEvent
{
    public
    {
        using base: Event     // Embedded base state.
        #[Swag.Late]
        style:  *ThemeStyle           // Style being updated.
        parent: #null *ThemeStyle     // Parent style inherited by `style`, when any.
    }
}

impl IEvent for ThemeEvent {}

// Requests serialization or restoration of window state.
struct SerializeStateEvent
{
    public
    {
        using base: Event                         // Embedded base state.
        serializer: *Serialization.Serializer     // Serializer that defines the current read/write mode.
    }
}

impl IEvent for SerializeStateEvent {}

// Carries a semantic notification emitted by a control.
struct NotifyEvent
{
    public
    {
        using base: Event     // Embedded base state.

        // Identifies the semantic notification sent by a control.
        enum Kind
        {
            ChildFocusChanged     // A descendant gained or lost keyboard focus.
            ThemeChanged          // The resolved theme or inherited style changed.
            LanguageChanged       // The active language of [[Gui.strings]] changed; text set at construction must be refreshed.
        }

        kind: Kind           // Notification kind.
        from: #null *Wnd     // Control that originated the notification.
    }
}

impl IEvent for NotifyEvent {}

// Requests repainting of a window.
struct InvalidateEvent
{
    public using base: Event     // Embedded base state.
}

impl IEvent for InvalidateEvent {}
