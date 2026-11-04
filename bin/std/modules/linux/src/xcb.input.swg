#global if #os == Swag.TargetOs.Linux
#global export

// Core X11 input-event layouts from xcb/xproto.h. Coordinates are signed client or root
// pixels; timestamps and state masks retain their native protocol meanings. Events returned
// by xcb_poll_for_event borrow their allocation until libc free; the high response bit marks
// SendEvent delivery. These declarations do not load an X11 library or connect to a display.

const XCB_KEY_PRESS = 2'u8     // Key press event opcode.
const XCB_KEY_RELEASE = 3'u8     // Key release event opcode.
const XCB_BUTTON_PRESS = 4'u8     // Pointer button press event opcode.
const XCB_BUTTON_RELEASE = 5'u8     // Pointer button release event opcode.
const XCB_MOTION_NOTIFY = 6'u8     // Pointer motion event opcode.
const XCB_ENTER_NOTIFY = 7'u8     // Pointer crossing into a window event opcode.
const XCB_LEAVE_NOTIFY = 8'u8     // Pointer crossing out of a window event opcode.
const XCB_FOCUS_IN = 9'u8     // Input focus gained event opcode.
const XCB_FOCUS_OUT = 10'u8     // Input focus lost event opcode.

const XCB_EVENT_MASK_KEY_PRESS = 1'u32     // Native event-selection bit.
const XCB_EVENT_MASK_KEY_RELEASE = 2'u32     // Native event-selection bit.
const XCB_EVENT_MASK_BUTTON_PRESS = 4'u32     // Native event-selection bit.
const XCB_EVENT_MASK_BUTTON_RELEASE = 8'u32     // Native event-selection bit.
const XCB_EVENT_MASK_ENTER_WINDOW = 16'u32     // Native event-selection bit.
const XCB_EVENT_MASK_LEAVE_WINDOW = 32'u32     // Native event-selection bit.
const XCB_EVENT_MASK_POINTER_MOTION = 64'u32     // Native event-selection bit.
const XCB_EVENT_MASK_FOCUS_CHANGE = 2097152'u32     // Native event-selection bit.

// Native key press event packet.
struct xcb_key_press_event_t
{
    public
    {
        response_type:     u8      // Event opcode, with the SendEvent bit when synthetic.
        detail:            u8      // Native keycode, button number, or notification detail.
        sequence:          u16     // Low 16 bits of the last processed request sequence.
        time:              u32     // Native X11 timestamp in milliseconds.
        root:              u32     // Root window identifier.
        event:             u32     // Destination window identifier.
        child:             u32     // Child containing the pointer, or zero.
        root_x:            s16     // Pointer X coordinate relative to the root.
        root_y:            s16     // Pointer Y coordinate relative to the root.
        event_x:           s16     // Pointer X coordinate relative to the destination.
        event_y:           s16     // Pointer Y coordinate relative to the destination.
        state:             u16     // Native modifier and button mask before this event.
        same_screen:       u8      // Nonzero when the source and destination share a screen.
        pad0:              u8      // Protocol padding.
    }
}

// Native button press event packet.
struct xcb_button_press_event_t
{
    public
    {
        response_type:     u8      // Event opcode, with the SendEvent bit when synthetic.
        detail:            u8      // Native keycode, button number, or notification detail.
        sequence:          u16     // Low 16 bits of the last processed request sequence.
        time:              u32     // Native X11 timestamp in milliseconds.
        root:              u32     // Root window identifier.
        event:             u32     // Destination window identifier.
        child:             u32     // Child containing the pointer, or zero.
        root_x:            s16     // Pointer X coordinate relative to the root.
        root_y:            s16     // Pointer Y coordinate relative to the root.
        event_x:           s16     // Pointer X coordinate relative to the destination.
        event_y:           s16     // Pointer Y coordinate relative to the destination.
        state:             u16     // Native modifier and button mask before this event.
        same_screen:       u8      // Nonzero when the source and destination share a screen.
        pad0:              u8      // Protocol padding.
    }
}

// Native motion notify event packet.
struct xcb_motion_notify_event_t
{
    public
    {
        response_type:     u8      // Event opcode, with the SendEvent bit when synthetic.
        detail:            u8      // Native keycode, button number, or notification detail.
        sequence:          u16     // Low 16 bits of the last processed request sequence.
        time:              u32     // Native X11 timestamp in milliseconds.
        root:              u32     // Root window identifier.
        event:             u32     // Destination window identifier.
        child:             u32     // Child containing the pointer, or zero.
        root_x:            s16     // Pointer X coordinate relative to the root.
        root_y:            s16     // Pointer Y coordinate relative to the root.
        event_x:           s16     // Pointer X coordinate relative to the destination.
        event_y:           s16     // Pointer Y coordinate relative to the destination.
        state:             u16     // Native modifier and button mask before this event.
        same_screen:       u8      // Nonzero when the source and destination share a screen.
        pad0:              u8      // Protocol padding.
    }
}

// Native enter notify event packet.
struct xcb_enter_notify_event_t
{
    public
    {
        response_type:     u8      // Event opcode, with the SendEvent bit when synthetic.
        detail:            u8      // Native keycode, button number, or notification detail.
        sequence:          u16     // Low 16 bits of the last processed request sequence.
        time:              u32     // Native X11 timestamp in milliseconds.
        root:              u32     // Root window identifier.
        event:             u32     // Destination window identifier.
        child:             u32     // Child containing the pointer, or zero.
        root_x:            s16     // Pointer X coordinate relative to the root.
        root_y:            s16     // Pointer Y coordinate relative to the root.
        event_x:           s16     // Pointer X coordinate relative to the destination.
        event_y:           s16     // Pointer Y coordinate relative to the destination.
        state:             u16     // Native modifier and button mask before this event.
        mode:              u8      // Native crossing notification mode.
        same_screen_focus: u8      // Native same-screen and focus flag bits.
    }
}

// Native focus in event packet.
struct xcb_focus_in_event_t
{
    public
    {
        response_type:     u8      // Event opcode, with the SendEvent bit when synthetic.
        detail:            u8      // Native keycode, button number, or notification detail.
        sequence:          u16     // Low 16 bits of the last processed request sequence.
        event:             u32     // Destination window identifier.
        mode:              u8      // Native focus notification mode.
        pad0:              [3]u8   // Protocol padding.
    }
}

// Shares the native key press packet layout.
alias xcb_key_release_event_t = xcb_key_press_event_t

// Shares the native button press packet layout.
alias xcb_button_release_event_t = xcb_button_press_event_t

// Shares the native enter notify packet layout.
alias xcb_leave_notify_event_t = xcb_enter_notify_event_t

// Shares the native focus in packet layout.
alias xcb_focus_out_event_t = xcb_focus_in_event_t

// Sets native input focus; the target must be viewable unless it is None or PointerRoot.
//
// The returned cookie is checked with xcb_request_check; this call owns no connection.
#[Swag.CallingConvention(.C)]
alias xcb_set_input_focus_checked_fn = func(*void, u8, u32, u32)->xcb_void_cookie_t
