#global if WINDOWS
#global public
#global namespace Input

using Win32, Math

// Returns the current mouse position
// Returns the cursor position in physical desktop pixels.
func mousePosition()->Point
{
    var pt: POINT = undefined
    GetCursorPos(&pt)
    return Point{cast(f32) pt.x, cast(f32) pt.y}
}

// Set the current mouse position
// Moves the cursor to the given position in physical desktop pixels.
func setMousePosition(x, y: s32)
{
    SetCursorPos(x, y)
}

// Shoud or hide the mouse cursor
// Shows or hides the system cursor.
func showMouseCursor(show: bool)
{
    ShowCursor(cast(BOOL) show)
}
