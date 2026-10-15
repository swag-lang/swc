#global private

struct Rect { x, y, width, height: f32 }
struct Window { position: Rect }

#[Swag.Inline]
func(T) create(out: *T, position: Rect, id: string? = null, hook: func||()? = null)->*T => create'T(out, "", position, id, hook)

#[Swag.NoInline]
func(T) create(out: *T, name: string?, position: Rect, id: string? = null, hook: func||()? = null)->*T
{
    out.position = position
    return out
}

// The inline borrow must point to the converted float fields, not the source integers.
// This is the forwarding shape used by Gui.Wnd.create.
#test
{
    var window: Window
    let target = create'Window(&window, {40, 20, 100, 50})
    Swag.assert(target.position.x == 40 and target.position.y == 20)
    Swag.assert(target.position.width == 100 and target.position.height == 50)
}

// Runtime elements and reordered named fields use the same conversion boundary.
#test
{
    var window: Window
    var width  = 100
    let target = create'Window(&window, {height: 50, width: width, y: 20, x: 40})
    Swag.assert(target.position.x == 40 and target.position.y == 20)
    Swag.assert(target.position.width == 100 and target.position.height == 50)
}

struct Options
{
    width:  f32 = 100
    height: f32 = 50
    marker: u64 = 73
}

#[Swag.Inline]
func readOptions(value: Options)->u64
{
    Swag.assert(value.width == 100 and value.height == 50)
    return value.marker
}

// An empty literal still needs the target's defaults and full storage size.
#test
{
    Swag.assert(readOptions({}) == 73)
    Swag.assert(readOptions({marker: 79}) == 79)
}

struct Nested { rect: Rect; options: Options }
#[Swag.Inline]
func readNested(value: Nested)->f32 => value.rect.width + value.options.height

#test
{
    Swag.assert(readNested({{40, 20, 100, 50}, {}}) == 150)
}
