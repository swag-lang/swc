#global public

// Selects a standard system cursor shape.
enum CursorShape
{
    Arrow                        // Default pointing arrow.
    ResizeHorizontal             // Horizontal resize indicator.
    ResizeVertical               // Vertical resize indicator.
    ResizeNorthwestSoutheast     // Diagonal resize from northwest to southeast.
    ResizeNortheastSouthwest     // Diagonal resize from northeast to southwest.
    Move                         // Four-direction move indicator.
    Cross                        // Crosshair selection cursor.
    Help                         // Context-help cursor.
    Hand                         // Link or direct-manipulation hand.
    IBeam                        // Text insertion cursor.
    No                           // Operation-not-allowed cursor.
    Wait                         // Busy or waiting cursor.
}

// Lightweight descriptor for a shared system cursor.
struct Cursor
{
    using
    native: NativeCursor     // Embedded native state.
}

impl Cursor
{
    // Activates the standard wait cursor.
    func activateWait()
    {
        activate(Cursor.from(CursorShape.Wait))
    }

    // Returns true if the cursor is defined
    mtd isValid()->bool
    {
        return .native.cursor != null
    }
}
