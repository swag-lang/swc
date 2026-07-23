#global public
using Core, Pixel

struct Item
{
    name:      RichString
    icon:      Icon
    id:        #null WndId
    userData0: #null *void
    userData1: #null *void
}

#[Swag.EnumFlags]
enum PaintItemFlags
{
    Zero     = 0
    Checked
    Pressed
    Hot
    Focus
    Disabled
}
