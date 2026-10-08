#global private

// A field default may name a constant of its own struct through the type, as code outside the
// struct does. The constant lives in the struct's scope and needs no layout, so reaching it
// through the type must not wait for the struct it is being used to build.

struct OwnConstantWindow
{
    width:  s32 = OwnConstantWindow.DefaultWidth
    height: s32 = DefaultHeight
    margin: f32 = OwnConstantWindow.Margin * 2
}

impl OwnConstantWindow
{
    const DefaultWidth  = 640's32
    const DefaultHeight = 400's32
    const Margin        = 8.0'f32

    func area(window: OwnConstantWindow)->s32 => window.width * window.height
}

#test
{
    var window: OwnConstantWindow
    Swag.assert(window.width == 640)
    Swag.assert(window.height == 400)
    Swag.assert(window.margin == 16.0)
    Swag.assert(OwnConstantWindow.area(window) == 640 * 400)
}

// Functions reached through the type still see their whole overload set, even when the overloads
// live in different 'impl' blocks: only a constant is taken before the struct completes.
struct OwnConstantKeys
{
    pressed: u32
}

impl OwnConstantKeys
{
    func isDown(key: u32)->bool => key == 1
}

impl OwnConstantKeys
{
    mtd isDown(key: u32, _: bool)->bool => .pressed == key
}

func ownConstantKeyDown()->bool => OwnConstantKeys.isDown(1)

#test
{
    Swag.assert(ownConstantKeyDown())
    var keys = OwnConstantKeys{pressed: 3}
    Swag.assert(keys.isDown(3, true))
}
