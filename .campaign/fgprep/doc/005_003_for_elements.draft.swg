#global private

/**
# Element Iteration with 'for'
Binding a name in a 'for' statement iterates over all elements of a collection (arrays, slices, strings, and even structs),
providing a streamlined and efficient way to process each item.
*/

#test
{
    for value in "ABC"
    {
        let a = @index
        switch a
        {
        case 0: @assert(value == 'A')
        case 1: @assert(value == 'B')
        case 2: @assert(value == 'C')
        }
    }
}

/**
# Naming Only the Index
Use `?` for the discarded element and put the index in the second binding:
`for ?, index in collection`. A counted loop has no element binding, so it simply uses
`for index in 3`.
*/

#test
{
    var sum = 0'u64

    for ?, index in "ABC"
    {
        #assert(#typeof(index) == u64)
        sum += index
    }

    @assert(sum == 3)
}

/**
# Naming the Value and Index
You can explicitly name both the element 'value' and the loop 'index' to improve readability,
especially in nested loops or with complex data structures. Both are ordinary bindings;
their position determines which value they receive.
*/

#test
{
    for value, index in "ABC"
    {
        let a = index
        switch a
        {
        case 0: @assert(value == 'A')
        case 1: @assert(value == 'B')
        case 2: @assert(value == 'C')
        }
    }
}

/**
# Enum-Indexed Arrays
When an array dimension is an enum, its index binding has that enum type. This keeps
iteration and indexing type-safe without converting through an integer.
*/

enum Channel: u8
{
    Blue  = 2
    Red   = 0
    Green = 1
}

#test
{
    let levels: [Channel] s32 = [10, 20, 30]
    var sum = 0

    for value, channel in levels
    {
        #assert(#typeof(channel) == Channel)
        @assert(value == levels[channel])
        sum += value
    }

    @assert(sum == 60)
}

/**
# Reverse Order with '.reversed()'
Iterate from the last element to the first through a borrowed reverse view.
The second visit value is the index within the original collection; '@index'
is the ordinal within the view.
*/
#test
{
    let text = cast(const cstring) @dataof("ABC")
    var cpt  = 0
    for value, index in text.reversed()
    {
        switch cpt
        {
        case 0:
            @assert(value == 'C')
            @assert(index == 2)

        case 1:
            @assert(value == 'B')
            @assert(index == 1)

        case 2:
            @assert(value == 'A')
            @assert(index == 0)
        }

        cpt += 1
    }
}

/**
# Visiting Arrays and Slices
Use 'for' with a binding to traverse arrays or slices and process each element.
A scalar element is copied into its binding.
*/

#test
{
    var array  = [10, 20, 30]
    var result = 0
    for it in array do
        result += it
    @assert(result == 10 + 20 + 30)
}

/**
# Multi-dimensional Arrays
Element iteration works with multi-dimensional arrays and visits each element in row-major order.
*/

#test
{
    var array: [2, 2] s32 = [[10, 20], [30, 40]]
    var result            = 0
    for it in array do
        result += it
    @assert(result == 10 + 20 + 30 + 40)
}

/**
# Struct Elements Bind by Address
A struct element is never copied into its binding: 'for v' binds the element's
address as a read-only pointer ('const *T'), so member accesses reach the
collection's storage directly and no per-element lifecycle (copy or drop) runs.
Use '&' when the loop must write.
*/

#test
{
    struct Point
    {
        x, y: s32
    }

    var points: [2] Point = [{1, 2}, {3, 4}]
    var sum = 0

    for p in points
    {
        #assert(#typeof(p) == #type const *Point)
        sum += p.x + p.y
    }

    @assert(sum == 10)
}

/**
# Modifying Elements with '&'
Prefix the element name with '&' to bind the element's **mutable address**: the
binding is a non-null pointer into the collection ('const *T' when the collection
itself is constant). Members of a struct element are reached directly through the
binding; the whole element is read or written with 'dref'.
*/

#test
{
    var array: [2, 2] s32 = [[1, 2], [3, 4]]
    var result            = 0

    for &it in array
    {
        #assert(#typeof(it) == *s32)
        result  += dref it
        dref it = 555
    }

    @assert(result == 1 + 2 + 3 + 4)
    @assert(array[0, 0] == 555)
    @assert(array[0, 1] == 555)
    @assert(array[1, 0] == 555)
    @assert(array[1, 1] == 555)
}

/**
The same '&' binding replaces a struct element in one write.
*/

#test
{
    struct Point
    {
        x, y: s32
    }

    var points: [2] Point = [{1, 2}, {3, 4}]

    for &p, index in points do
        dref p = Point{cast(s32) index, cast(s32) index}

    @assert(points[0].x == 0 and points[0].y == 0)
    @assert(points[1].x == 1 and points[1].y == 1)
}

/**
# Filtering with 'where'
Add a 'where' clause to process only elements that satisfy a condition.
This avoids explicit branching inside the loop.
*/

#test
{
    var array: [?] s32 = [1, 2, 3, 4]
    var result         = 0

    for value in array where value & 1 == 0 do
        result += value
    @assert(result == 6)

    // Equivalent with an 'if' guard:
    result = 0
    for value in array do
        if value & 1 == 0 do
            result += value
    @assert(result == 6)

    // Equivalent using 'continue' to skip odd values:
    result = 0
    for value in array
    {
        if (value & 1) != 0 do
            continue
        result += value
    }

    @assert(result == 6)
}
