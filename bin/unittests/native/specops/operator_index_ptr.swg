#global private

// Only the 'FullContainer' priority test reads these, and it resets them first: '#test'
// blocks of one module may run in any order, so no other type touches them.
var g_ValueReads:  u32
var g_PtrAccesses: u32
var g_SetCalls:    u32
var g_AssignCalls: u32

struct PtrElem
{
    x: s32
    y: s32
}

impl PtrElem
{
    mtd bump()
    {
        .x += 1
    }
}

struct PtrContainer
{
    values: [4] PtrElem
}

impl PtrContainer
{
    mtd opIndexPtr(index: u64)->*PtrElem
    {
        return &.values[index]
    }

    mtd const opIndexPtr(index: u64)->const *PtrElem
    {
        return &.values[index]
    }

    // A const receiver must select the const overload for both the member read and the
    // escaping element address.
    mtd const constProbe()->s32
    {
        let p = &me[0]
        #assert(#typeof(p) == #type const *PtrElem)
        return me[0].x + p.y
    }
}

// A container with every index operator: the dedicated write operators must keep priority
// over mutating through the 'opIndexPtr' element address.
struct FullContainer
{
    values: [4] s32
}

impl FullContainer
{
    mtd const opIndex(index: u64)->s32
    {
        g_ValueReads += 1
        return .values[index]
    }

    mtd opIndexPtr(index: u64)->*s32
    {
        g_PtrAccesses += 1
        return &.values[index]
    }

    mtd opIndexSet(index: u64, value: s32)
    {
        g_SetCalls     += 1
        .values[index] = value
    }

    mtd(op: Swag.Operator) opIndexAssign(index: u64, value: s32)
    {
        g_AssignCalls += 1
        #ast ".values[index] " ++ op.symbol() ++ " value"
    }
}

struct(T) GenBox
{
    values: [4] T
}

impl GenBox
{
    mtd opIndexPtr(index: u64)->*T
    {
        return &.values[index]
    }
}

struct Grid
{
    cells: [2, 3] s32
}

impl Grid
{
    mtd opIndexPtr(x, y: u64)->*s32
    {
        return &.cells[x, y]
    }
}

struct NestedElem
{
    inner: PtrElem
}

struct NestedContainer
{
    values: [2] NestedElem
}

impl NestedContainer
{
    mtd opIndexPtr(index: u64)->*NestedElem
    {
        return &.values[index]
    }
}

// Member access through the element address must write the container's storage in place.
#test
{
    var c: PtrContainer
    c[0].x = 5
    c[0].y = 6
    Swag.assert(c.values[0].x == 5)
    Swag.assert(c.values[0].y == 6)

    c[0].x += 10
    Swag.assert(c.values[0].x == 15)
}

// Whole-element assignment without 'opIndexSet' writes through the element address.
#test
{
    var c: PtrContainer
    c[1] = {7, 8}
    Swag.assert(c.values[1].x == 7)
    Swag.assert(c.values[1].y == 8)
}

// The element address escapes as a plain pointer and stays writable.
#test
{
    var c: PtrContainer
    let p = &c[2]
    #assert(#typeof(p) == #type *PtrElem)
    p.x = 42
    Swag.assert(c.values[2].x == 42)
}

// A mutating method call binds the element address as its receiver.
#test
{
    var c: PtrContainer
    c[3].bump()
    c[3].bump()
    Swag.assert(c.values[3].x == 2)
}

// Reading an element loads the value out: the copy does not alias the storage.
#test
{
    var c: PtrContainer
    c[0] = {1, 2}
    var v = c[0]
    v.x = 99
    Swag.assert(c.values[0].x == 1)
}

// A const receiver selects the const overload and keeps reads working.
#test
{
    var c: PtrContainer
    c[0] = {3, 4}
    Swag.assert(c.constProbe() == 7)
}

// 'opIndexSet' and 'opIndexAssign' keep priority over the element address; plain reads
// prefer the value-returning 'opIndex'.
#test
{
    g_ValueReads, g_PtrAccesses, g_SetCalls, g_AssignCalls = 0

    var c: FullContainer
    c[0] = 10
    Swag.assert(g_SetCalls == 1)

    c[0] += 5
    Swag.assert(g_AssignCalls == 1)

    let v = c[0]
    Swag.assert(v == 15)
    Swag.assert(g_ValueReads == 1)

    let p = &c[0]
    Swag.assert(p[] == 15)
    Swag.assert(g_PtrAccesses == 1)
}

// A generic container hands back a typed element address.
#test
{
    var box: GenBox's32
    box[0] = 4
    box[0] += 3
    Swag.assert(box.values[0] == 7)

    var pts: GenBox'PtrElem
    pts[1].x = 11
    Swag.assert(pts.values[1].x == 11)
}

// Multi-dimensional indexing routes every place context through 'opIndexPtr'.
#test
{
    var g: Grid
    g[1, 2] = 9
    g[1, 2] += 1
    Swag.assert(g.cells[1, 2] == 10)

    let p = &g[0, 1]
    p[] = 33
    Swag.assert(g.cells[0, 1] == 33)
}

// A chained member path stays one in-place write.
#test
{
    var c: NestedContainer
    c[1].inner.x = 21
    c[1].inner.bump()
    Swag.assert(c.values[1].inner.x == 22)
}
