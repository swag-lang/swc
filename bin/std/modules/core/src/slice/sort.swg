#global export
#global namespace Slice

// Insertion sort algorithm (slow)
private func(T) insertionSort(values: [..] T, compare: func||(T, T)->s32)
{
    var buffer = @dataof(values)
    let count  = @countof(values)

    for var i = 1'u64; i < count; i += 1
    {
        for var j = i; j > 0 and compare(buffer[j], buffer[j - 1]) < 0; j -= 1
        {
            swap(&buffer[j], &buffer[j - 1])
        }
    }
}

// Quick sort algorithm
private func(T) quickSort(values: [..] T, compare: func||(T, T)->s32)
{
    let count = cast(s64) @countof(values)
    if count == 0 do
        return

    var begin  = 0's64
    var end    = count - 1
    var buffer = @dataof(values)

    for
    {
        // If range is too small, simple sort
        if end - begin <= 10
        {
            insertionSort(@mkslice(buffer + begin, (end - begin) + 1), compare)
            return
        }

        let pivot = begin
        var low   = begin
        var high  = end
        for
        {
            while low < high and compare(buffer[low], buffer[pivot]) <= 0 do
                low += 1
            while compare(buffer[high], buffer[pivot]) > 0 do
                high -= 1
            if low >= high do
                break
            swap(&buffer[low], &buffer[high])
        }

        // Put the median in the "center" of the list
        swap(&buffer[pivot], &buffer[high])

        // To avoid too much recursions, we recurse only for the smaller partition
        let set1 = (high - 1) - begin
        let set2 = end - (high + 1)
        if set1 > 0 and set2 > 0
        {
            var first, last: s64 = undefined
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

            quickSort(@mkslice(buffer + first, (last - first) + 1), compare)
        }
        elif set1 > 0 do
            end = high - 1
        elif set2 > 0 do
            begin = high + 1
        else do
            break
    }
}

// Sort the slice, by picking the right algorithm depending on the type and the
// number of elements
func(T) sort(values: [..] T, descending = false)
    where Reflection.canCompare(T)
{
    if descending do
        sort(values, func(x, y: T)->s32 => y <=> x)
    else do
        sort(values, func(x, y: T)->s32 => x <=> y)
}

// Sort the slice, by picking the right algorithm depending on the type and the
// number of elements
func(T) sort(values: [..] T, compare: func||(T, T)->s32)
{
    Debug.assert(compare != null)
    if @countof(values) <= 10 do
        insertionSort(values, compare)
    else do
        quickSort(values, compare)
}

// Returns true if the slice is sorted
func(T) isSorted(values: const [..] T)->bool
    where Reflection.canCompare(T)
{
    return isSorted(values, func(x, y: T)->s32 => x <=> y)
}

// Returns true if the slice is sorted
func(T) isSorted(values: const [..] T, compare: func||(T, T)->s32)->bool
{
    Debug.assert(compare != null)
    let countof = @countof(values)
    if countof <= 1 do
        return true

    for [i] in countof - 1
    {
        if compare(values[i], values[i + 1]) > 0 do
            return false
    }

    return true
}
