#global export
#global namespace Slice

// Sorts in place with an insertion sort: quadratic, but the cheapest choice for a short range.
private func(T) insertionSort(values: [..] T, compare: func||(T, T)->s32)
{
    var buffer = values.buffer
    let count  = values.count

    for var i = 1'u64; i < count; i += 1
    {
        for var j = i; j > 0 and compare(buffer[j], buffer[j - 1]) < 0; j -= 1
        {
            swap(&buffer[j], &buffer[j - 1])
        }
    }
}

// Sorts in place with a median-of-three quick sort that recurses only into the smaller partition.
private func(T) quickSort(values: [..] T, compare: func||(T, T)->s32)
{
    let count = cast(s64) values.count
    if count == 0 do
        return

    var begin  = 0's64
    var end    = count - 1
    var buffer = values.buffer

    for
    {
        // A short range is cheaper to finish with an insertion sort.
        if end - begin <= 10
        {
            insertionSort(Swag.makeSlice(buffer + begin, (end - begin) + 1), compare)
            return
        }

        // Order the first, middle and last values, then partition around the median of the
        // three, which this leaves at 'begin'. Taking the front value itself is the quadratic
        // case for a range that is already sorted, or exactly reversed — and re-sorting an
        // array that is already in order is an ordinary thing for a caller to do.
        let mid = begin + (end - begin) / 2
        if compare(buffer[mid], buffer[begin]) < 0 do
            swap(&buffer[mid], &buffer[begin])
        if compare(buffer[end], buffer[begin]) < 0 do
            swap(&buffer[end], &buffer[begin])
        if compare(buffer[end], buffer[mid]) < 0 do
            swap(&buffer[end], &buffer[mid])
        swap(&buffer[begin], &buffer[mid])

        // Both scans stop on a value equal to the pivot, so a run of equal values is split
        // down the middle. A scan that walked over its equals instead would peel one element
        // per level, which is the same quadratic case reached from the other side.
        let pivot = begin
        var low   = begin
        var high  = end + 1
        for
        {
            low += 1
            while low <= end and compare(buffer[low], buffer[pivot]) < 0 do
                low += 1
            high -= 1
            while compare(buffer[high], buffer[pivot]) > 0 do
                high -= 1
            if low >= high do
                break
            swap(&buffer[low], &buffer[high])
        }

        // Move the pivot between the two partitions.
        swap(&buffer[pivot], &buffer[high])

        // Recursing only into the smaller partition bounds the recursion depth to a logarithm of the count.
        let set1 = (high - 1) - begin
        let set2 = end - (high + 1)
        if set1 > 0 and set2 > 0
        {
            var first, last: s64
            if set1 <= set2
            {
                first = begin
                last  = high - 1
                begin = high + 1
            }
            else
            {
                first = high + 1
                last  = end
                end   = high - 1
            }

            quickSort(Swag.makeSlice(buffer + first, (last - first) + 1), compare)
        }
        elif set1 > 0 do
            end = high - 1
        elif set2 > 0 do
            begin = high + 1
        else do
            break
    }
}

// Sorts the slice in place, in ascending order or in descending order when `descending` is true.
//
// Short slices use an insertion sort and longer ones a quick sort. The sort is not stable: equal
// elements can change their relative order.
func(T) sort(values: [..] T, descending = false)
    where Reflection.canCompare(T)
{
    if descending do
        sort(values, func(x, y: T)->s32 => y <=> x)
    else do
        sort(values, func(x, y: T)->s32 => x <=> y)
}

// Sorts the slice in place in the order defined by `compare`.
//
// `compare` returns a negative value when its first argument must come before the second, zero
// when both are equivalent, and a positive value otherwise.
func(T) sort(values: [..] T, compare: func||(T, T)->s32)
{
    Swag.assert(compare != null)
    if values.count <= 10 do
        insertionSort(values, compare)
    else do
        quickSort(values, compare)
}

// Returns whether the slice is in ascending order.
func(T) isSorted(values: const [..] T)->bool
    where Reflection.canCompare(T)
{
    return isSorted(values, func(x, y: T)->s32 => x <=> y)
}

// Returns whether the slice is in the order defined by `compare`.
//
// The slice is sorted when `compare` returns no positive value for any two adjacent elements.
func(T) isSorted(values: const [..] T, compare: func||(T, T)->s32)->bool
{
    Swag.assert(compare != null)
    if values.count <= 1 do
        return true

    for i in values.count - 1 where compare(values[i], values[i + 1]) > 0 do
        return false
    return true
}
