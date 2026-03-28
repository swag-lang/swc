#global fileprivate

// Regression coverage for generic struct methods.
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

// --- Generic struct with const param and methods ---

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

// // --- Method returning generic struct ---
//
// struct(T) Box
// {
//     value: T
// }
//
// impl Container
// {
//     mtd toBox()->Box'T
//     {
//         return {value: .value}
//     }
// }
//
// #test
// {
//     let c: Container's32 = {value: 42, count: 1}
//     let b = c.toBox()
//     @assert(b.value == 42)
//
//     let c2: Container'string = {value: "boxed", count: 1}
//     let b2 = c2.toBox()
//     @assert(b2.value == "boxed")
// }
//
// // --- Multiple impl blocks on same generic struct ---
//
// struct(T) Accumulator
// {
//     value: T
// }
//
// impl Accumulator
// {
//     mtd get()->T => .value
// }
//
// impl Accumulator
// {
//     mtd set(v: T)
//     {
//         .value = v
//     }
// }
//
// #test
// {
//     var acc: Accumulator's32 = {value: 0}
//     @assert(acc.get() == 0)
//     acc.set(100)
//     @assert(acc.get() == 100)
// }
//
// // --- Generic struct with method that takes another generic struct ---
//
// struct(A, B) Pair
// {
//     first: A
//     second: B
// }
//
// impl Container
// {
//     mtd pairWith(other: T)->Pair'(T, T)
//     {
//         return {first: .value, second: other}
//     }
// }
//
// #test
// {
//     let c: Container's32 = {value: 5, count: 1}
//     let p = c.pairWith(10)
//     @assert(p.first == 5)
//     @assert(p.second == 10)
// }

// --- Non-generic struct with generic method ---

struct Counter
{
    count: s32
}

impl Counter
{
    func(T) staticIdentity(value: T)->T => value
}

#test
{
    @assert(Counter.staticIdentity(42) == 42)
    @assert(Counter.staticIdentity(true) == true)
    @assert(Counter.staticIdentity("hi") == "hi")
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
