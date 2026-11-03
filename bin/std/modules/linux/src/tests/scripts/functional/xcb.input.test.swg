#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

// Independently checked against xcb/xproto.h with sizeof and offsetof in C.
#test
{
    Swag.assert(#sizeof(xcb_key_press_event_t) == 32)
    Swag.assert(#sizeof(xcb_button_press_event_t) == 32)
    Swag.assert(#sizeof(xcb_motion_notify_event_t) == 32)
    Swag.assert(#sizeof(xcb_enter_notify_event_t) == 32)
    Swag.assert(#sizeof(xcb_focus_in_event_t) == 12)
    Swag.assert(#offsetof(xcb_key_press_event_t.time) == 4)
    Swag.assert(#offsetof(xcb_key_press_event_t.event) == 12)
    Swag.assert(#offsetof(xcb_key_press_event_t.root_x) == 20)
    Swag.assert(#offsetof(xcb_key_press_event_t.event_x) == 24)
    Swag.assert(#offsetof(xcb_key_press_event_t.state) == 28)
    Swag.assert(#offsetof(xcb_key_press_event_t.same_screen) == 30)
    Swag.assert(#offsetof(xcb_button_press_event_t.event) == 12)
    Swag.assert(#offsetof(xcb_motion_notify_event_t.event) == 12)
    Swag.assert(#offsetof(xcb_enter_notify_event_t.event) == 12)
    Swag.assert(#offsetof(xcb_enter_notify_event_t.mode) == 30)
    Swag.assert(#offsetof(xcb_enter_notify_event_t.same_screen_focus) == 31)
    Swag.assert(#offsetof(xcb_focus_in_event_t.event) == 4)
    Swag.assert(#offsetof(xcb_focus_in_event_t.mode) == 8)
    Swag.assert(XCB_EVENT_MASK_FOCUS_CHANGE == 2097152)
    Swag.assert(XCB_EVENT_MASK_POINTER_MOTION == 64 and XCB_EVENT_MASK_BUTTON_RELEASE == 8)
}
