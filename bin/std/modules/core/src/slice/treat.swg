#global export
#global namespace Slice

// Applies `action` to the address of every element.
#[Swag.Inline]
func(T) forEachMutable(values: [..] T, action: func||(*T))
{
    for [i] in @countof(values) do
        action(&values[i])
}

// Map the content of a slice to an array of type 'R'.
// The lambda must return the value of 'R' for each element of the slice.
func(T, R) map(values: const [..] T, transform: func||(T)->R)->Array'R
{
    var result: retval
    for v in values do
        result.add(transform(v))
    return result
}

// Reduce the content of a slice to one single value.
// The lambda is called with the previous reduced value and each element of the slice.
// The first reduced value is the first element of the slice.
func(T) reduce(values: const [..] T, combine: func||(T, T)->T)->T
{
    Debug.assert(@countof(values) > 0, "cannot reduce an empty slice")
    var result = values[0]
    if @countof(values) == 1 do
        return result
    for [i] in 1 to @countof(values) - 1 do
        result = combine(result, values[i])
    return result
}

// Get the minimum value of a slice, and the corresponding value index.
func(T) min(values: const [..] T)->{ value: T, index: u64 }
{
    Debug.assert(@countof(values) > 0, "cannot get the minimum of an empty slice")
    var result: retval
    result.value = values[0]
    if @countof(values) == 1 do
        return result

    for [i] in 1 to @countof(values) - 1
    {
        if values[i] < result.value
        {
            result.value = values[i]
            result.index = i
        }
    }

    return result
}

// Get the maximum value of a slice, and the corresponding value index.
func(T) max(values: const [..] T)->{ value: T, index: u64 }
{
    Debug.assert(@countof(values) > 0, "cannot get the maximum of an empty slice")
    var result: retval
    result.value = values[0]
    if @countof(values) == 1 do
        return result

    for [i] in 1 to @countof(values) - 1
    {
        if values[i] > result.value
        {
            result.value = values[i]
            result.index = i
        }
    }

    return result
}

// Returns true if 'cb' returns true for all values
func(T) allOf(values: const [..] T, predicate: func||(T)->bool)->bool
{
    for v in values
    {
        if !predicate(v) do
            return false
    }

    return true
}

// Returns true if 'cb' returns true for at least one value
func(T) anyOf(values: const [..] T, predicate: func||(T)->bool)->bool
{
    for v in values
    {
        if predicate(v) do
            return true
    }

    return false
}

// Returns true if 'cb' returns false for all values
func(T) noneOf(values: const [..] T, predicate: func||(T)->bool)->bool
{
    for v in values
    {
        if predicate(v) do
            return false
    }

    return true
}

// Reverse the content of a slice
func(T) reverse(values: [..] T)
{
    if @countof(values) <= 1 do
        return
    var i = 0'u64
    var j = @countof(values) - 1
    let d = @dataof(values)
    while i < j
    {
        swap(d + i, d + j)
        i += 1
        j -= 1
    }
}

// Get a permutation of the slice
// Shuffle the slice until no more permutation is possible, and then returns 'false'.
// To obtain all permutations, the slice must be sorted the first time.
func(T) nextPermutation(values: [..] T)->bool
{
    let count = @countof(values)
    if count < 2 do
        return false

    var pivot = count - 2
    while values[pivot] >= values[pivot + 1]
    {
        if !pivot do
            return false
        pivot -= 1
    }

    var successor = count - 1
    while values[successor] <= values[pivot] do
        successor -= 1

    swap(&values[pivot], &values[successor])
    if pivot + 1 != count - 1 do
        reverse(values[pivot + 1 to count - 1])

    return true
}
