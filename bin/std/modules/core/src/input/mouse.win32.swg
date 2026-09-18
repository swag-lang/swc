#global if WINDOWS
#global public
#global namespace Input

using Win32, Math

// Returns the cursor position in physical desktop pixels.
func mousePosition()->Point
{
    var pt: POINT
    GetCursorPos(&pt)
    return Point{cast(f32) pt.x, cast(f32) pt.y}
}

// Moves the cursor to (`x`, `y`) in physical desktop pixels.
func setMousePosition(x, y: s32)
{
    SetCursorPos(x, y)
}

// Shows or hides the system cursor.
//
// Calls nest: the cursor shows again only after as many shows as hides.
func showMouseCursor(show: bool)
{
    ShowCursor(cast(BOOL) show)
}
