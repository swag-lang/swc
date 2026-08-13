#global export

using Swag

// Stores unique keys in ascending order.
//
// Lookup and range boundaries use binary search. Insertion and removal can move keys and
// therefore invalidate every pointer, reference, slice, and iterator borrowed from the set.
// Call [[OrderedSet.initialize]] before the first operation to select the ordering explicitly.
struct(K) OrderedSet
{
    private
    {
        keys:       Array'K
        comparator: #null *void
    }

    public readonly count: u64     // The number of keys in the set.
}

// Iterates a borrowed ordered set from its greatest key to its least key.
#[Swag.Opaque]
struct(K) ReversedOrderedSet
{
    source: const *OrderedSet'K
}

impl ReversedOrderedSet
{
    // Iterates keys from greatest to least.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(key, index: u64))
    {
        #scope(Up)
            for offset in .source.count
        {
            let keyIndex = .source.count - offset - 1
            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(&K) &.source.keys[keyIndex], index = offset, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &.source.keys[keyIndex], index = offset, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = .source.keys[keyIndex], index = offset, break = break to Up, continue = break to Down)
            }
        }
    }
}

impl OrderedSet
{
    // Creates an empty set that uses `comparator` to order keys.
    func create(comparator: func(const *K, const *K)->s32)->OrderedSet
    {
        var result: retval
        result.initialize(comparator)
        return result
    }

    // Selects the comparator used by subsequent operations.
    // The set must be empty so that no key was positioned by another ordering.
    mtd initialize(comparator: func(const *K, const *K)->s32)
    {
        Debug.assert(comparator != null)
        Debug.assert(.isEmpty(), "ordered set is not empty")
        .comparator = cast(*void) comparator
    }

    // Returns the number of keys in the set.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the set contains no keys.
    #[Inline]
    mtd const isEmpty()->bool => .count == 0

    // Returns the number of keys that fit without allocating.
    #[Inline]
    mtd const capacity()->u64 => .keys.capacity

    // Reserves storage for at least `newCapacity` keys without changing the set.
    mtd reserve(newCapacity: u64)
    {
        .keys.reserve(newCapacity)
    }

    #[Swag.NoDoc]
    mtd const compareKeys(left, right: const &K)->s32
    {
        if .comparator do
            return (cast(func(const *K, const *K)->s32) .comparator!)(&left, &right)

        Debug.assert(false, "ordered set has not been initialized with a comparator")
        return 0
    }

    // Returns the first index whose key is not less than `key`.
    mtd const lowerBound(key: K)->u64
    {
        var first  = 0'u64
        var length = .count
        while length
        {
            let half = length / 2
            let mid  = first + half
            if .compareKeys(.keys[mid], key) < 0
            {
                first  = mid + 1
                length -= half + 1
            }
            else do
                length = half
        }

        return first
    }

    // Returns the first index whose key is greater than `key`.
    mtd const upperBound(key: K)->u64
    {
        var first  = 0'u64
        var length = .count
        while length
        {
            let half = length / 2
            let mid  = first + half
            if .compareKeys(key, .keys[mid]) >= 0
            {
                first  = mid + 1
                length -= half + 1
            }
            else do
                length = half
        }

        return first
    }

    // Returns the sorted keys in the half-open interval `[lower, upper)`.
    // The returned slice borrows the set and is invalidated by any insertion or removal.
    mtd const range(lower, upper: K)->const [..] K
    {
        let first = .lowerBound(lower)
        let last  = .lowerBound(upper)
        if last <= first do
            return @mkslice(cast(const [*] K) 1'u64, 0)
        return @mkslice(.keys.buffer! + first, last - first)
    }

    // Returns whether the set contains `key`.
    mtd const contains(key: K)->bool
    {
        let index = .lowerBound(key)
        return index < .count and .compareKeys(.keys[index], key) == 0
    }

    // Adds `key` in sorted position and returns whether it was newly inserted.
    // The key is copied; pass it with `#move` to transfer it.
    #[Discardable]
    mtd add(key: #fwd K)->bool
    {
        let index = .lowerBound(key)
        if index < .count and .compareKeys(.keys[index], key) == 0 do
            return false
        .keys.insertAt(index, #fwd key)
        .count += 1
        return true
    }

    // Removes `key` and returns whether it was present.
    mtd remove(key: K)->bool
    {
        let index = .lowerBound(key)
        if index == .count or .compareKeys(.keys[index], key) != 0 do
            return false
        .keys.removeAtOrdered(index)
        .count -= 1
        return true
    }

    // Removes all keys while retaining allocated capacity and the selected comparator.
    mtd clear()
    {
        .keys.clear()
        .count = 0
    }

    // Removes all keys and releases allocated storage.
    mtd free()
    {
        .keys.free()
        .count = 0
    }

    // Iterates keys from least to greatest.
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(key, index: u64))
    {
        #scope(Up)
            for keyIndex in .count
        {
            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(&K) &.keys[keyIndex], index = keyIndex, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &.keys[keyIndex], index = keyIndex, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = .keys[keyIndex], index = keyIndex, break = break to Up, continue = break to Down)
            }
        }
    }

    // Returns an immutable zero-allocation view that traverses keys in descending order.
    mtd const reversed()->ReversedOrderedSet'K => {source: &me}
}
