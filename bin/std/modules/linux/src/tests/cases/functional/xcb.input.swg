#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

// Independently checked against xcb/xproto.h with sizeof and offsetof in C.
#test
{
    Swag.require(#sizeof(xcb_key_press_event_t) == 32)
    Swag.require(#sizeof(xcb_button_press_event_t) == 32)
    Swag.require(#sizeof(xcb_motion_notify_event_t) == 32)
    Swag.require(#sizeof(xcb_enter_notify_event_t) == 32)
    Swag.require(#sizeof(xcb_focus_in_event_t) == 12)
    Swag.require(#offsetof(xcb_key_press_event_t.time) == 4)
    Swag.require(#offsetof(xcb_key_press_event_t.event) == 12)
    Swag.require(#offsetof(xcb_key_press_event_t.root_x) == 20)
    Swag.require(#offsetof(xcb_key_press_event_t.event_x) == 24)
    Swag.require(#offsetof(xcb_key_press_event_t.state) == 28)
    Swag.require(#offsetof(xcb_key_press_event_t.same_screen) == 30)
    Swag.require(#offsetof(xcb_button_press_event_t.event) == 12)
    Swag.require(#offsetof(xcb_motion_notify_event_t.event) == 12)
    Swag.require(#offsetof(xcb_enter_notify_event_t.event) == 12)
    Swag.require(#offsetof(xcb_enter_notify_event_t.mode) == 30)
    Swag.require(#offsetof(xcb_enter_notify_event_t.same_screen_focus) == 31)
    Swag.require(#offsetof(xcb_focus_in_event_t.event) == 4)
    Swag.require(#offsetof(xcb_focus_in_event_t.mode) == 8)
    Swag.require(XCB_EVENT_MASK_FOCUS_CHANGE == 2097152)
    Swag.require(XCB_EVENT_MASK_POINTER_MOTION == 64 and XCB_EVENT_MASK_BUTTON_RELEASE == 8)
}
