#global public

using Core, Pixel

// Represents item.
struct Item
{
    name:      RichString      // Name associated with this value.
    icon:      Icon            // Icon associated with this value.
    id:        #null WndId     // Id associated with this value.
    userData0: #null *void     // User data0 associated with this value.
    userData1: #null *void     // User data1 associated with this value.
}

// Selects paint item flags.
#[Swag.EnumFlags]
enum PaintItemFlags
{
    Zero = 0     // No flags are enabled.
    Checked      // Enables checked.
    Pressed      // Enables pressed.
    Hot          // Enables hot.
    Focus        // Enables focus.
    Disabled     // Enables disabled.
}
