#global private

/**
# Slices in Swag

A slice provides a dynamic view over a contiguous block of memory. Unlike static arrays,
slices can point to different memory regions or subsets of existing data at runtime.

A slice consists of a data pointer and a 'u64' count representing the number of elements.
This allows efficient access to large datasets without copying memory.
*/
#test
{
    var a: #null [..] bool
    #assert(#sizeof(a) == #sizeof(#null *void) + #sizeof(u64))
}

/**
# Initializing Slices

Slices can be initialized directly with array literals. The slice will reference
the array’s elements.
*/
#test
{
    var a: const [..] u32 = [10, 20, 30, 40, 50]
    Swag.assert(a.count == 5)
    Swag.assert(a[0] == 10)
    Swag.assert(a[4] == 50)

    a = [1, 2]
    Swag.assert(a.count == 2)
    Swag.assert(a[0] == 1)
    Swag.assert(a[1] == 2)
}

/**
# Accessing Slice Data

The '.buffer' intrinsic retrieves the slice’s data address, and '.count' returns
the number of elements.
*/
#test
{
    var a: const [..] u32 = [10, 20, 30, 40, 50]
    let count             = a.count
    let addr              = a.buffer

    Swag.assert(count == 5)
    Swag.assert(addr[0] == 10)
    Swag.assert(addr[4] == 50)

    a = [1, 2]
    Swag.assert(a.count == 2)
}

/**
# Creating Slices with 'Swag.makeSlice'

The 'Swag.makeSlice' intrinsic creates a slice from a pointer and an element count.
*/
#test
{
    var array: [4] u32 = [10, 20, 30, 40]

    let slice: [..] u32 = Swag.makeSlice(cast([*] u32) &array[0] + 2, 2)
    Swag.assert(slice.count == 2)
    Swag.assert(slice[0] == 30)
    Swag.assert(slice[1] == 40)

    slice[0] = 314
    Swag.assert(array[2] == 314)
}

/**
# Slicing Strings

Strings can be sliced, but the result must be declared as 'const' since strings are immutable.
*/
#test
{
    let str = "string"
    let strSlice: const [..] u8 = Swag.makeSlice(str.buffer, 2)
    Swag.assert(strSlice[0] == 's')
    Swag.assert(strSlice[1] == 't')
}

/**
# Slicing with a Range

Indexing with a range creates a slice directly. The range uses the same 'to' and 'until'
keywords as a 'for' loop; '[..]' is the slice **type**, not the range operator.
*/
#test
{
    let str   = "string"
    let slice = str[1 to 3]
    Swag.assert(slice == "tri")
}

/**
# Inclusive and Exclusive Slicing

By default, the upper bound in a slice is inclusive. To exclude it, use 'until' instead of 'to'.
*/
#test
{
    let str   = "string"
    let slice = str[1 until 3]
    Swag.assert(slice == "tr")
}

/**
# Empty Slices

An 'until' range whose bounds are equal selects nothing and produces an empty slice.

Slicing differs from looping here. A loop asks whether an index is still within a range, so
an inverted range simply runs zero times. A slice asks for a **length**, and an inverted range
has none, so it is reported: constant bounds at compile time, computed ones by the
'Swag.Safety(.BoundCheck)' guard, which also checks that the upper bound stays inside the
source. Where that guard is off, the count is clamped to zero rather than wrapping, so a slice
never describes more memory than its source holds.
*/
#test
{
    let str   = "string"
    let empty = str[3 until 3]
    Swag.assert(empty.count == 0)
    Swag.assert(empty == "")

    let values = [10, 20, 30]
    Swag.assert(values[0 until 0].count == 0)
    Swag.assert(values[3 until 3].count == 0)
}

/**
# Slicing to the End

Omitting the upper bound creates a slice extending to the end of the sequence.
*/
#test
{
    let str   = "string"
    let slice = str[2 to]
    Swag.assert(slice == "ring")
}

/**
# Slicing from the Start

Omitting the lower bound starts the slice from index 0.
*/
#test
{
    let str = "string"

    let slice = str[to 2]
    Swag.assert(slice == "str")

    let slice1 = str[until 2]
    Swag.assert(slice1 == "st")
}

/**
# Slicing Arrays

Arrays can be sliced the same way as strings.
*/

#test
{
    let arr   = [10, 20, 30, 40]
    let slice = arr[2 to 3]
    Swag.assert(slice[0] == 30)
    Swag.assert(slice[1] == 40)
    Swag.assert(slice.count == 2)
    let slice1 = arr[to]
    Swag.assert(slice1.count == arr.count)
}

/**
# Slicing a Slice

A slice can be further sliced to produce another slice.
*/

#test
{
    let arr    = [10, 20, 30, 40]
    let slice1 = arr[1 to 3]
    Swag.assert(slice1[0] == 20)
    Swag.assert(slice1[1] == 30)
    Swag.assert(slice1[2] == 40)
    let slice2 = slice1[1 to 2]
    Swag.assert(slice2[0] == 30)
    Swag.assert(slice2[1] == 40)
}

/**
# Transforming a Pointer into a Slice

A pointer can be transformed into a slice by specifying a range.
*/

#test
{
    var arr   = [10, 20, 30, 40]
    let ptr   = &arr[2]
    let slice = ptr[0 to 1]
    Swag.assert(slice[0] == 30)
    Swag.assert(slice[1] == 40)
    Swag.assert(slice.count == 2)
}

/**
# Comparing Slices

'==' asks what a slice holds, not where it points. Two slices are equal when they have the
same count and the same elements, so a copy into other storage compares equal to its
source, and a shorter view over the same storage does not.

Comparing against 'null' is the one exception: it asks whether the slice has any storage at
all, which is what a '#null' slice records.
*/

#test
{
    var source: [4] u8 = [1, 2, 3, 4]
    var copy:   [4] u8 = [1, 2, 3, 4]

    let whole = source[to]
    let other = copy[to]
    Swag.assert(whole.buffer != other.buffer)
    Swag.assert(whole == other)

    let head = source[to 2]
    Swag.assert(whole.buffer == head.buffer)
    Swag.assert(whole != head)

    let missing: #null const [..] u8 = null
    Swag.assert(missing == null)
}
