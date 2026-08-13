#global export

using Swag

// Stores one key-value pair in an [[OrderedMap]].
struct(K, V) OrderedMapEntry
{
    public
    {
        readonly key: K     // The key that determines the entry's position.
        value: V            // The value associated with the key.
    }
}

// Maps unique keys to values while keeping entries in ascending key order.
//
// Lookup and range boundaries use binary search. Insertion and removal can move entries and
// therefore invalidate every pointer, reference, slice, and iterator borrowed from the map.
// Call [[OrderedMap.initialize]] before the first operation to select the ordering explicitly.
struct(K, V) OrderedMap
{
    private
    {
        entries:    Array'(OrderedMapEntry'(K, V))
        comparator: #null *void
    }

    public readonly count: u64     // The number of key-value pairs in the map.
}

// Iterates a borrowed ordered map from its greatest key to its least key.
#[Swag.Opaque]
struct(K, V) ReversedOrderedMap
{
    source: const *OrderedMap'(K, V)
}

impl ReversedOrderedMap
{
    // Iterates entries from the greatest key to the least key.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(key, value, index: u64))
    {
        #scope(Up)
        for offset in .source.count
        {
            let entryIndex = .source.count - offset - 1
            let entry      = &.source.entries[entryIndex]
            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(&K) &entry.key, value = cast(&V) &entry.value, index = offset, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) and Reflection.isStruct(V) do
                    #inject(stmt, key = cast(const &K) &entry.key, value = cast(const &V) &entry.value, index = offset, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &entry.key, value = entry.value, index = offset, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(V) do
                    #inject(stmt, key = entry.key, value = cast(const &V) &entry.value, index = offset, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = entry.key, value = entry.value, index = offset, break = break to Up, continue = break to Down)
            }
        }
    }
}

impl OrderedMap
{
    // Creates an empty map that uses `comparator` to order keys.
    func create(comparator: func(const *K, const *K)->s32)->OrderedMap
    {
        var result: retval
        result.initialize(comparator)
        return result
    }

    // Selects the comparator used by subsequent operations.
    // The map must be empty so that no key was positioned by another ordering.
    mtd initialize(comparator: func(const *K, const *K)->s32)
    {
        Debug.assert(comparator != null)
        Debug.assert(.isEmpty(), "ordered map is not empty")
        .comparator = cast(*void) comparator
    }

    // Returns the number of entries in the map.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the map contains no entries.
    #[Inline]
    mtd const isEmpty()->bool => .count == 0

    // Returns the number of entries that fit without allocating.
    #[Inline]
    mtd const capacity()->u64 => .entries.capacity

    // Reserves storage for at least `newCapacity` entries without changing the map.
    mtd reserve(newCapacity: u64)
    {
        .entries.reserve(newCapacity)
    }

    #[Swag.NoDoc]
    mtd const compareKeys(left, right: const &K)->s32
    {
        if .comparator do
            return (cast(func(const *K, const *K)->s32) .comparator!)(&left, &right)

        Debug.assert(false, "ordered map has not been initialized with a comparator")
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
            if .compareKeys(.entries[mid].key, key) < 0
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
            if .compareKeys(key, .entries[mid].key) >= 0
            {
                first  = mid + 1
                length -= half + 1
            }
            else do
                length = half
        }

        return first
    }

    // Returns the sorted entries with keys in the half-open interval `[lower, upper)`.
    // The returned slice borrows the map and is invalidated by any insertion or removal.
    mtd const range(lower, upper: K)->const [..] OrderedMapEntry'(K, V)
    {
        let first = .lowerBound(lower)
        let last  = .lowerBound(upper)
        if last <= first do
            return @mkslice(cast(const [*] OrderedMapEntry'(K, V)) 1'u64, 0)
        return @mkslice(.entries.buffer! + first, last - first)
    }

    // Returns whether the map contains `key`.
    mtd const contains(key: K)->bool
    {
        return .tryFind(key) != null
    }

    // Returns the entry for `key`, or `null` when the key is absent.
    // The returned pointer is invalidated by insertion or removal.
    mtd tryFind(key: K)->#null *OrderedMapEntry
    {
        let index = .lowerBound(key)
        if index == .count or .compareKeys(.entries[index].key, key) != 0 do
            return null
        return .entries.buffer! + index
    }

    // Returns the entry for `key`, or `null` when the key is absent.
    // The returned pointer is invalidated by insertion or removal.
    mtd const tryFind(key: K)->#null const *OrderedMapEntry
    {
        let index = .lowerBound(key)
        if index == .count or .compareKeys(.entries[index].key, key) != 0 do
            return null
        return .entries.buffer! + index
    }

    // Returns the entry for `key` and asserts if the key is absent.
    mtd find(key: K)->*OrderedMapEntry
    {
        let result = .tryFind(key)
        Debug.assert(result != null, "key not found")
        return result!
    }

    // Returns the entry for `key` and asserts if the key is absent.
    mtd const find(key: K)->const *OrderedMapEntry
    {
        let result = .tryFind(key)
        Debug.assert(result != null, "key not found")
        return result!
    }

    // Returns a mutable reference to the value for `key` and asserts if the key is absent.
    mtd opIndex(key: K)->&V => &.find(key).value

    // Returns an immutable reference to the value for `key` and asserts if the key is absent.
    mtd const opIndex(key: K)->const &V => &.find(key).value

    // Adds a key-value pair in sorted position, replacing the value of an existing key.
    // The key and value are copied; pass either with `#move` to transfer it.
    #[Discardable]
    mtd add(key: #fwd K, value: #fwd V)->*OrderedMapEntry
    {
        let index = .lowerBound(key)
        if index < .count and .compareKeys(.entries[index].key, key) == 0
        {
            .entries[index].value = #fwd value
            return .entries.buffer! + index
        }

        .entries.insertAt(index, OrderedMapEntry'(K, V){key: #fwd key, value: #fwd value})
        .count += 1
        return .entries.buffer! + index
    }

    // Assigns `value` to `key`, inserting the key when necessary.
    mtd opIndexSet(key: K, value: V)
    {
        discard .add(key, value)
    }

    // Removes `key` and returns whether an entry was present.
    mtd remove(key: K)->bool
    {
        let index = .lowerBound(key)
        if index == .count or .compareKeys(.entries[index].key, key) != 0 do
            return false
        .entries.removeAtOrdered(index)
        .count -= 1
        return true
    }

    // Removes all entries while retaining allocated capacity and the selected comparator.
    mtd clear()
    {
        .entries.clear()
        .count = 0
    }

    // Removes all entries and releases allocated storage.
    mtd free()
    {
        .entries.free()
        .count = 0
    }

    // Iterates entries from the least key to the greatest key.
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(key, value, index: u64))
    {
        #scope(Up)
        for entryIndex in .count
        {
            let entry = &.entries[entryIndex]
            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(&K) &entry.key, value = cast(&V) &entry.value, index = entryIndex, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) and Reflection.isStruct(V) do
                    #inject(stmt, key = cast(const &K) &entry.key, value = cast(const &V) &entry.value, index = entryIndex, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const &K) &entry.key, value = entry.value, index = entryIndex, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(V) do
                    #inject(stmt, key = entry.key, value = cast(const &V) &entry.value, index = entryIndex, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = entry.key, value = entry.value, index = entryIndex, break = break to Up, continue = break to Down)
            }
        }
    }

    // Returns an immutable zero-allocation view that traverses entries in descending key order.
    mtd const reversed()->ReversedOrderedMap'(K, V) => {source: &me}
}
