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
    Hidden                       // No visible pointer until another cursor is activated.
}

// Lightweight descriptor for a shared system cursor.
struct Cursor
{
    using native: NativeCursor     // Platform cursor handle.
    hidden: bool                   // Whether this descriptor hides the pointer.
}

impl Cursor
{
    // Activates the standard wait cursor.
    func activateWait() { activate(Cursor.from(CursorShape.Wait)) }

    // Reports whether this descriptor can be activated.
    mtd const isValid()->bool => .hidden or .native.cursor != null

    // Reports whether this descriptor hides the pointer.
    mtd const isHidden()->bool => .hidden
}
