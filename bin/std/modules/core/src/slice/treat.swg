#global export
#global namespace Slice

// Applies `action` to the address of every element.
#[Swag.Inline]
func(T) forEachMutable(values: [..] T, action: func||(*T))
{
    for &value in values do
        action(value)
}

// Returns an array holding the result of `transform` for every element, in order.
func(T, R) map(values: const [..] T, transform: func||(T)->R)->Array'R
{
    var result: retval
    for v in values do
        result.add(transform(v))
    return result
}

// Folds the elements from left to right into one value with `combine`.
//
// The first element is the initial accumulator, and `combine` receives the accumulator and the
// next element. The slice must not be empty.
func(T) reduce(values: const [..] T, combine: func||(T, T)->T)->T
{
    Swag.assert(values.count > 0, "cannot reduce an empty slice")
    var result = values[0]
    for i in 1 until values.count do
        result = combine(result, values[i])
    return result
}

// Returns the smallest element and its index.
//
// When several elements are the smallest, the first one is returned. The slice must not be empty.
func(T) min(values: const [..] T)->{ value: T, index: u64 }
{
    Swag.assert(values.count > 0, "cannot get the minimum of an empty slice")
    var result: retval
    result.value = values[0]
    for i in 1 until values.count
    {
        if values[i] < result.value
        {
            result.value = values[i]
            result.index = i
        }
    }

    return result
}

// Returns the greatest element and its index.
//
// When several elements are the greatest, the first one is returned. The slice must not be empty.
func(T) max(values: const [..] T)->{ value: T, index: u64 }
{
    Swag.assert(values.count > 0, "cannot get the maximum of an empty slice")
    var result: retval
    result.value = values[0]
    for i in 1 until values.count
    {
        if values[i] > result.value
        {
            result.value = values[i]
            result.index = i
        }
    }

    return result
}

// Returns whether `predicate` holds for every element.
//
// Returns true for an empty slice.
func(T) allOf(values: const [..] T, predicate: func||(T)->bool)->bool
{
    for v in values where not predicate(v) do
        return false
    return true
}

// Returns whether `predicate` holds for at least one element.
//
// Returns false for an empty slice.
func(T) anyOf(values: const [..] T, predicate: func||(T)->bool)->bool
{
    for v in values where predicate(v) do
        return true
    return false
}

// Returns whether `predicate` holds for no element.
//
// Returns true for an empty slice.
func(T) noneOf(values: const [..] T, predicate: func||(T)->bool)->bool
{
    for v in values where predicate(v) do
        return false
    return true
}

// Reverses the order of the elements in place.
func(T) reverse(values: [..] T)
{
    if values.count <= 1 do
        return
    var i = 0'u64
    var j = values.count - 1
    let d = values.buffer
    while i < j
    {
        swap(d + i, d + j)
        i += 1
        j -= 1
    }
}

// Rearranges the elements into the next permutation in lexicographic order.
//
// Returns false, leaving the slice unchanged, when it already holds the last permutation, which is
// the descending order. Starting from ascending order and calling it until it returns false visits
// every distinct permutation once.
func(T) nextPermutation(values: [..] T)->bool
{
    let count = values.count
    if count < 2 do
        return false

    var pivot = count - 2
    while values[pivot] >= values[pivot + 1]
    {
        if not pivot do
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
