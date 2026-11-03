#global private

// A brace literal whose destination is a struct takes its fields from that struct:
// positional values by position, 'field: value' by name, and a bare identifier that
// names a field lands in that field.

struct Point { x, y: s32 }
struct Box { origin: Point; width, height: s32 }
struct Depth { x, y, z: s32 = 9 }

#[Swag.NoInline]
func runtimeValue(value: s32)->s32 => value

func encode(point: Point)->s32 => point.x * 100 + point.y
func encodeBox(box: Box)->s32  => encode(box.origin) * 10_000 + box.width * 100 + box.height
func makePoint(value: s32)->Point { return {value, value + 1} }
func makeShort(value: s32)->Point => {value, 2}

#test
{
    var point: Point = {1, 2}
    Swag.require(point.x == 1 and point.y == 2)
    point = {runtimeValue(4), runtimeValue(8)}
    Swag.require(point.x == 4 and point.y == 8)
    Swag.require(point == {4, 8})
    Swag.require(encode({4, 5}) == 405)
    Swag.require(encode({runtimeValue(4), runtimeValue(5)}) == 405)
    Swag.require(encode(point: {6, 7}) == 607)
}

#test
{
    let point = makePoint(runtimeValue(5))
    Swag.require(point.x == 5 and point.y == 6)
    Swag.require(makeShort(runtimeValue(7)).x == 7)
}

#test
{
    var box: Box = {{1, 2}, 3, 4}
    Swag.require(box.origin.y == 2 and box.height == 4)
    Swag.require(encodeBox({{1, 2}, 3, 4}) == 1020304)
    Swag.require(encodeBox({origin: {runtimeValue(1), 2}, width: 3, height: 4}) == 1020304)
    var points: [2] Point = [{1, 2}, {runtimeValue(3), 4}]
    Swag.require(points[1].x == 3)
}

#test
{
    var depth: Depth = {1, 2}
    Swag.require(depth.z == 9)
    depth = {1, z: runtimeValue(5)}
    Swag.require(depth.y == 9 and depth.z == 5)
    let empty: Depth = {}
    Swag.require(empty.x == 9)
}

// A bare identifier naming a field lands in it, whatever its position, with or
// without the type prefix. Any other bare identifier is a positional value.
#test
{
    let y = runtimeValue(1)
    let x = runtimeValue(2)
    let braces: Point = {y, x}
    Swag.require(braces.x == 2 and braces.y == 1)
    let typed = Point{y, x}
    Swag.require(typed.x == 2 and typed.y == 1)
    Swag.require(encode({y, x}) == 201)

    let width        = runtimeValue(3)
    let height       = runtimeValue(4)
    let sized: Point = {width, height}
    Swag.require(sized.x == 3 and sized.y == 4)
    Swag.require(encode({height, width}) == 403)
    let mixed: Point = {x, height}
    Swag.require(mixed.x == 2 and mixed.y == 4)
}
