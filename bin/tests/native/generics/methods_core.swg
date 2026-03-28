#global fileprivate

struct(T) Container
{
    value: T
    count: s32
}

impl Container
{
    mtd getValue()->T => .value
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
    top: s32
}

impl FixedStack
{
    mtd capacity()->s32 => N

    mtd push(value: T)
    {
        .data[.top] = value
        .top += 1
    }

    mtd peek()->T => .data[.top - 1]
    mtd size()->s32 => .top
}

struct(T, N: s32) Grid
{
    cells: [N * N] T
}

impl Grid
{
    mtd at(row: s32, col: s32)->T => .cells[row * N + col]
    mtd dimension()->s32 => N
    mtd totalCells()->s32 => N * N
}

#test
{
    var c: Container's32 = {value: 10, count: 1}
    @assert(c.getValue() == 10)
    @assert(c.getCount() == 1)
    @assert(c.isCountEqual(1) == true)
    @assert(c.isCountEqual(2) == false)
    c.setValue(20)
    @assert(c.getValue() == 20)
}

#test
{
    var c: Container'string = {value: "hello", count: 5}
    @assert(c.getValue() == "hello")
    @assert(c.getCount() == 5)

    c.setValue("world")
    @assert(c.getValue() == "world")
}

#test
{
    var c: Container'bool = {value: true, count: 2}
    @assert(c.getValue() == true)
    c.setValue(false)
    @assert(c.getValue() == false)
    @assert(c.isCountEqual(2) == true)
}

#test
{
    var stack: FixedStack'(s32, 4) = {top: 0}
    @assert(stack.capacity() == 4)
    @assert(stack.size() == 0)
    stack.push(10)
    stack.push(20)
    stack.push(30)
    @assert(stack.size() == 3)
    @assert(stack.peek() == 30)
}

#test
{
    var stack: FixedStack'(f64, 2) = {top: 0}
    stack.push(1.5)
    stack.push(2.5)
    @assert(stack.peek() == 2.5)
    @assert(stack.capacity() == 2)
}

#test
{
    var g: Grid'(s32, 3) = {cells: [1, 2, 3, 4, 5, 6, 7, 8, 9]}
    @assert(g.dimension() == 3)
    @assert(g.totalCells() == 9)
    @assert(g.at(0, 0) == 1)
    @assert(g.at(1, 1) == 5)
    @assert(g.at(2, 2) == 9)
    @assert(g.at(0, 2) == 3)
    @assert(g.at(2, 0) == 7)
}

#test
{
    var g: Grid'(u8, 2) = {cells: [10'u8, 20, 30, 40]}
    @assert(g.dimension() == 2)
    @assert(g.totalCells() == 4)
    @assert(g.at(0, 0) == 10'u8)
    @assert(g.at(1, 1) == 40'u8)
}
