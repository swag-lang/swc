#global private

// Struct elements never bind by copy: 'for v in collection' aliases each element
// through a const reference, and 'for &v in collection' through a mutable one.

var g_PostCopy = 0
var g_Drop     = 0

struct Tracked
{
    x: s32
}

impl Tracked
{
    mtd opPostCopy() { g_PostCopy += 1 }
    mtd opDrop()     { g_Drop += 1 }
}

#[Swag.NoCopy]
struct Pinned
{
    x: s32
}

struct Pair
{
    a: s32
    b: s32
}

// No copy, no lifecycle per iteration for the by-value struct binding.
#test
{
    var arr: [3] Tracked
    arr[0].x = 1
    arr[1].x = 2
    arr[2].x = 3

    g_PostCopy = 0
    g_Drop     = 0
    var sum    = 0
    for v in arr do
        sum += v.x

    @assert(sum == 6)
    @assert(g_PostCopy == 0)
    @assert(g_Drop == 0)
}

// The binding is typed as a const reference.
#test
{
    var arr: [2] Pair
    for v in arr
    {
        #assert(#typeof(v) == #type const &Pair)
        break
    }
}

// Alias identity: in-place mutations of the source are visible through the binding.
#test
{
    var arr: [3] Tracked
    for v, [i] in arr
    {
        arr[i].x += 100
        @assert(v.x == arr[i].x)
    }
}

// NoCopy structs are iterable by value now (aliasing, not copying).
#test
{
    var pins: [2] Pinned
    pins[0].x = 7
    pins[1].x = 8
    var sum = 0
    for p in pins do
        sum += p.x
    @assert(sum == 15)
}

// '&' binds a mutable reference; whole-element assignment writes through.
#test
{
    var arr: [2] Pair = [{1, 2}, {3, 4}]
    for &v, [i] in arr do
        v = Pair{cast(s32) i + 10, cast(s32) i + 20}
    @assert(arr[0].a == 10 and arr[0].b == 20)
    @assert(arr[1].a == 11 and arr[1].b == 21)
}

// References are transparent in equality: binding == literal / binding == value.
#test
{
    var arr: [3] Pair = [{1, 1}, {2, 2}, {3, 3}]
    let wanted = Pair{2, 2}
    var hits   = 0
    for v in arr
    {
        if v == Pair{2, 2} do
            hits += 1
        if v == wanted do
            hits += 1
    }
    @assert(hits == 2)
}

// References are transparent in scalar casts through the '&' byte form.
#test
{
    var text: string = "AB"
    var sum = 0
    for &b in text do
        sum += cast(s32) b
    @assert(sum == 65 + 66)
}
