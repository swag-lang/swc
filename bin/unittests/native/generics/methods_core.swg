#global private

struct(T) Container
{
    value: T
    count: s32
}

impl Container
{
    mtd getValue()->T   => .value
    mtd getCount()->s32 => .count

    mtd setValue(v: T)
    {
        .value = v
    }

    mtd isCountEqual(n: s32)->bool => .count == n
}

struct(T, N: s32) FixedStack
{
    data: [N] T
    top:  s32
}

impl FixedStack
{
    mtd capacity()->s32 => N

    mtd push(value: T)
    {
        .data[.top] = value
        .top        += 1
    }

    mtd peek()->T   => .data[.top - 1]
    mtd size()->s32 => .top
}

struct(T, N: s32) Grid
{
    cells: [N * N] T
}

impl Grid
{
    mtd at(row: s32, col: s32)->T => .cells[row * N + col]
    mtd dimension()->s32          => N
    mtd totalCells()->s32         => N * N
}

#test
{
    var c: Container's32 = {value: 10, count: 1}
    Swag.assert(c.getValue() == 10)
    Swag.assert(c.getCount() == 1)
    Swag.assert(c.isCountEqual(1) == true)
    Swag.assert(c.isCountEqual(2) == false)
    c.setValue(20)
    Swag.assert(c.getValue() == 20)
}

#test
{
    var c: Container'string = {value: "hello", count: 5}
    Swag.assert(c.getValue() == "hello")
    Swag.assert(c.getCount() == 5)

    c.setValue("world")
    Swag.assert(c.getValue() == "world")
}

#test
{
    var c: Container'bool = {value: true, count: 2}
    Swag.assert(c.getValue() == true)
    c.setValue(false)
    Swag.assert(c.getValue() == false)
    Swag.assert(c.isCountEqual(2) == true)
}

#test
{
    var stack: FixedStack'(s32, 4) = {top: 0}
    Swag.assert(stack.capacity() == 4)
    Swag.assert(stack.size() == 0)
    stack.push(10)
    stack.push(20)
    stack.push(30)
    Swag.assert(stack.size() == 3)
    Swag.assert(stack.peek() == 30)
}

#test
{
    var stack: FixedStack'(f64, 2) = {top: 0}
    stack.push(1.5)
    stack.push(2.5)
    Swag.assert(stack.peek() == 2.5)
    Swag.assert(stack.capacity() == 2)
}

#test
{
    var g: Grid'(s32, 3) = {cells: [1, 2, 3, 4, 5, 6, 7, 8, 9]}
    Swag.assert(g.dimension() == 3)
    Swag.assert(g.totalCells() == 9)
    Swag.assert(g.at(0, 0) == 1)
    Swag.assert(g.at(1, 1) == 5)
    Swag.assert(g.at(2, 2) == 9)
    Swag.assert(g.at(0, 2) == 3)
    Swag.assert(g.at(2, 0) == 7)
}

#test
{
    var g: Grid'(u8, 2) = {cells: [10'u8, 20, 30, 40]}
    Swag.assert(g.dimension() == 2)
    Swag.assert(g.totalCells() == 4)
    Swag.assert(g.at(0, 0) == 10'u8)
    Swag.assert(g.at(1, 1) == 40'u8)
}
