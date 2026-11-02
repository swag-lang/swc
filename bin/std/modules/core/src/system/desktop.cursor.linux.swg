#global if #os == Swag.TargetOs.Linux
#global namespace LinuxDesktop

private var g_CursorMutex: Swag.Mutex

private func prepareCursor(state: *Context) fail
{
    if state.cursorReady do
        return
    if not state.libraryXfixes do
        state.libraryXfixes = Linux.dlopen("libxcb-xfixes.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not state.libraryXfixes do
        fail Swag.SystemError{"cannot load libxcb-xfixes.so.0"}

    // Extension descriptors must outlive XCB's per-connection cache, including failed requests.
    let library = state.libraryXfixes
    if not hasExtension(state, library, "xcb_xfixes_id") do
        fail Swag.SystemError{"XFixes extension is unavailable"}
    let query   = try symbol'Linux.xcb_xfixes_query_version_fn(library, "xcb_xfixes_query_version")
    let receive = try symbol'Linux.xcb_xfixes_query_version_reply_fn(library, "xcb_xfixes_query_version_reply")
    var error: *Linux.xcb_generic_error_t?
    let reply   = receive(unwrap state.connection, query(state.connection, 4, 0), &error)
    defer if error do
        Linux.free(error)
    defer if reply do
        Linux.free(reply)
    if error or not reply do
        fail Swag.SystemError{"cannot negotiate XFixes cursor support"}
    if reply.major_version < 4 do
        fail Swag.SystemError{"cursor visibility requires XFixes version 4"}

    state.xcb_xfixes_hide_cursor_checked = try symbol'Linux.xcb_xfixes_hide_cursor_checked_fn(library, "xcb_xfixes_hide_cursor_checked")
    state.xcb_xfixes_show_cursor_checked = try symbol'Linux.xcb_xfixes_show_cursor_checked_fn(library, "xcb_xfixes_show_cursor_checked")
    state.cursorReady = true
}

internal func setCursorVisibility(show: bool) fail
{
    let state = try ensure()
    g_CursorMutex.lock()
    defer g_CursorMutex.unlock()
    try prepareCursor(state)
    if (show and state.cursorBalance == Swag.S64.Max) or
       (not show and state.cursorBalance == Swag.S64.Min) do
        fail Errors.BadParameterError{"cursor visibility counter is exhausted"}

    let next = state.cursorBalance + (show ? 1's64 : -1's64)

    // Keep one native hide ownership regardless of the number of nested callers.
    // A rejected request must leave the local balance unchanged so it can be retried.
    if state.cursorBalance >= 0 and next < 0 do
        try check(state, state.xcb_xfixes_hide_cursor_checked(unwrap state.connection, state.screen.root))
    elif state.cursorBalance < 0 and next >= 0 do
        try check(state, state.xcb_xfixes_show_cursor_checked(unwrap state.connection, state.screen.root))
    state.cursorBalance = next
}
