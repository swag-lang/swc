#global public

using Core, Pixel

// Common label, icon, command, and caller-data payload used by item controls.
struct Item
{
    public
    {
        name:      RichString      // Display label, optionally containing styled spans.
        icon:      Icon            // Optional display icon.
        id:        #null WndId     // Optional command identifier.
        userData0: #null *void     // First caller-owned payload pointer.
        userData1: #null *void     // Second caller-owned payload pointer.
    }
}

// Describes the interaction state in which an item is painted.
#[Swag.EnumFlags]
enum PaintItemFlags
{
    None = 0     // The item has no special interaction state.
    Checked      // The item represents an active checked state.
    Pressed      // A pointer button is pressing the item.
    Hot          // The pointer is hovering the item.
    Focus        // The item owns keyboard focus.
    Disabled     // The item cannot be activated.
}
