#global private

// Slicing with an exclusive range whose bounds are equal produces an empty slice rather
// than a compile-time error.

//
// Constant empty exclusive ranges
//

#test
{
    func emptyArraySliceAtZero()->u64
    {
        let values = [10, 20, 30]
        let slice  = values[0 until 0]
        return @countof(slice)
    }

    const V = #run emptyArraySliceAtZero()
    #assert(V == 0)
    @assert(emptyArraySliceAtZero() == 0)
}

#test
{
    func emptyArraySliceInside()->u64
    {
        let values = [10, 20, 30]
        let slice  = values[2 until 2]
        return @countof(slice)
    }

    const V = #run emptyArraySliceInside()
    #assert(V == 0)
    @assert(emptyArraySliceInside() == 0)
}

#test
{
    func emptyStringSlice()->u64
    {
        let text  = "string"
        let slice = text[3 until 3]
        return @countof(slice)
    }

    const V = #run emptyStringSlice()
    #assert(V == 0)
    @assert(emptyStringSlice() == 0)
    @assert("string"[3 until 3] == "")
}

// The inclusive form with equal bounds still selects exactly one element.
#test
{
    func inclusiveSingleElement()->s32
    {
        let values = [10, 20, 30]
        let slice  = values[1 to 1]
        @assert(@countof(slice) == 1)
        return slice[0]
    }

    const V = #run inclusiveSingleElement()
    #assert(V == 20)
    @assert(inclusiveSingleElement() == 20)
}

//
// Dynamic bounds
//

func sliceCount(values: const [..] s32, low, high: u64)->u64
{
    let slice = values[low until high]
    return @countof(slice)
}

#test
{
    var storage: [4] s32        = [1, 2, 3, 4]
    let values:  const [..] s32 = storage

    @assert(sliceCount(values, 0, 0) == 0)
    @assert(sliceCount(values, 2, 2) == 0)
    @assert(sliceCount(values, 4, 4) == 0)
    @assert(sliceCount(values, 1, 3) == 2)
}

// An empty slice of an empty slice stays empty, and iterating it visits nothing.
#test
{
    func sliceOfEmptySlice()->s32
    {
        var storage: [3] s32        = [7, 8, 9]
        let values:  const [..] s32 = storage
        let empty                   = values[1 until 1]
        let again                   = empty[0 until 0]

        var acc: s32 = 0
        for v in again do
            acc += v
        for v in empty do
            acc += v
        return acc + cast(s32) (@countof(empty) + @countof(again))
    }

    const V = #run sliceOfEmptySlice()
    #assert(V == 0)
    @assert(sliceOfEmptySlice() == 0)
}

// An empty slice keeps pointing inside its source, so the source is left untouched.
#test
{
    func emptySliceLeavesSourceIntact()->s32
    {
        var storage: [3] s32        = [4, 5, 6]
        let values:  const [..] s32 = storage
        let empty                   = values[1 until 1]
        @assert(@countof(empty) == 0)
        return storage[0] + storage[1] + storage[2]
    }

    const V = #run emptySliceLeavesSourceIntact()
    #assert(V == 15)
    @assert(emptySliceLeavesSourceIntact() == 15)
}
