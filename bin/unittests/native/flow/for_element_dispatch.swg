#global private

// 'for' dispatches on the type of the iterated expression:
// integer or range -> index loop, anything else -> element iteration.

enum Color
{
    Red
    Green
    Blue
}

struct CountedBag
{
    filled: u64 = 4
}

impl CountedBag
{
    mtd const opCount()->u64 => me.filled
}

// Single name over an array binds the element values.
#test
{
    var arr: [3] s32 = [10, 20, 30]
    var sum = 0
    for v in arr
    {
        sum += v
    }
    Swag.require(sum == 60)
}

// Single name over a slice binds the element values.
#test
{
    var arr:   [3] s32        = [10, 20, 30]
    let slice: const [..] s32 = arr
    var sum = 0
    for v in slice
    {
        sum += v
    }
    Swag.require(sum == 60)
}

// Single name over a string binds the bytes.
#test
{
    let text = "abc"
    var sum  = 0
    for b in text
    {
        sum += cast(s32, b)
    }
    Swag.require(sum == 97 + 98 + 99)
}

// Two names bind value and index.
#test
{
    var arr: [3] s32 = [10, 20, 30]
    var sum = 0
    for v, i in arr
    {
        sum += v + cast(s32, i)
    }
    Swag.require(sum == 60 + 3)
}

// '&' binds a mutable reference to the element; mutation writes through.
#test
{
    var arr: [3] s32 = [10, 20, 30]
    for &v in arr
    {
        v[] += 1
    }
    Swag.require(arr[0] == 11 and arr[1] == 21 and arr[2] == 31)
}

// Single name over an enum type binds the enum values.
#test
{
    var count = 0
    for c in Color
    {
        if c == Color.Green
        {
            count += 1
        }
    }
    Swag.require(count == 1)
}

// Integer expressions and ranges keep index-loop semantics.
#test
{
    var arr: [3] s32 = [10, 20, 30]
    var total        = 0_u64

    for i in arr.count
    {
        total += i
    }

    for i in 0 until arr.count
    {
        total += i
    }

    Swag.require(total == 6)
}

// The unnamed form stays a count loop, including through 'opCount'.
#test
{
    var bag   = CountedBag{}
    var count = 0
    for bag
    {
        count += 1
    }
    Swag.require(count == 4)
}

// '.reversed()' element iteration.
#test
{
    var arr:   [3] s32 = [1, 2, 3]
    var order: [3] s32
    var slot = 0
    for v in (arr).reversed()
    {
        order[slot] = v
        slot        += 1
    }
    Swag.require(order[0] == 3 and order[1] == 2 and order[2] == 1)
}

// 'where' filters element iteration.
#test
{
    var arr: [4] s32 = [1, 2, 3, 4]
    var sum = 0
    for v in arr where v % 2 == 0
    {
        sum += v
    }
    Swag.require(sum == 6)
}
