#global export

using Swag

// A key-value pair stored in a [[Core.HashTable]].
struct(K, V) HashTableEntry
{
    hash: u32

    public
    {
        readonly key: K     // The key.
        value:        V     // The value associated with the key.
    }
}

// An open-addressing hash table that maps unique keys to values.
//
// Lookups, insertions, and removals take expected constant time. The table grows by rehashing,
// which moves every entry and invalidates every entry and value pointer borrowed from it.
struct(K, V) HashTable
{
    // Special hash values to indicate the state of a slot in the table.
    #[Swag.NoDoc]
    const HASH_FREE = 0'u32
    #[Swag.NoDoc]
    const HASH_DELETED = 1'u32
    #[Swag.NoDoc]
    const HASH_FIRST = 2'u32

    internal allocator: IAllocator?

    // Sizes are reported, never set: the table grows itself when it needs to.

    public readonly
    {
        count:    u64     // The number of valid key-value pairs currently in the table.
        capacity: u64     // The total number of slots, always a power of two.
    }

    // Open-addressing state. The layout is an implementation choice: reaching into it from
    // outside would tie callers to the probing scheme and the load factor.

    private
    {
        table:         [*] HashTableEntry?     // Contiguous memory block for the slots.
        deleted:       u64                     // The number of slots marked as deleted.
        growThreshold: u64                     // Used slot count that triggers a resize, derived from 'capacity'.
    }
}

// Iterates a borrowed hash table by descending storage slot.
#[Swag.Opaque]
struct(K, V) ReversedHashTable
{
    source: const *HashTable'(K, V)
}

impl ReversedHashTable
{
    // Visits borrowed key-value pairs in descending storage-slot order.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(key, value))
    {
        let table  = .source.constTablePtr()
        var remain = .source.count
        #scope(Up)
        for offset in .source.capacity
        {
            let tableIndex = .source.capacity - offset - 1
            if table[tableIndex].hash < 2'u32 do
                continue

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(*K) &table[tableIndex].key, value = cast(*V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) and Reflection.isStruct(V) do
                    #inject(stmt, key = cast(const *K) &table[tableIndex].key, value = cast(const *V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const *K) &table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(V) do
                    #inject(stmt, key = table[tableIndex].key, value = cast(const *V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if not remain do
                break
        }
    }
}

impl HashTable
{
    #[Swag.NoDoc]
    func normalizeCapacity(newCapacity: u64)->u64
    {
        var result = 32'u64
        let target = Math.max(newCapacity, result)
        while result < target do
            result <<= 1
        return result
    }

    #[Swag.NoDoc]
    mtd tablePtr()->[*] HashTableEntry => .table orelse cast([*] HashTableEntry'(K, V)) 1'u64

    #[Swag.NoDoc]
    mtd const constTablePtr()->const [*] HashTableEntry => cast(const [*] HashTableEntry'(K, V)) (.table orelse cast([*] HashTableEntry'(K, V)) 1'u64)

    // Returns the number of key-value pairs in the table.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the table contains no key-value pairs.
    #[Inline]
    mtd const isEmpty()->bool => .count == 0

    // Drops every entry and releases the slots.
    mtd opDrop()
    {
        .free()
    }

    // Replaces the content with copies of the pairs in `slice`.
    //
    // A later pair replaces the value of an earlier pair with the same key. Every pair is copied
    // in, so this only exists when both halves can be copied.
    mtd opSet(slice: const [..] { k: K, v: V })
        where Reflection.canCopy(#typeof(K)) and Reflection.canCopy(#typeof(V))
    {
        .clear()
        for v in slice do
            .add(v.k, v.v)
    }

    #static if Reflection.canCopy(K) and Reflection.canCopy(V)
    {
        // Gives a copied table its own slots holding copies of the entries.
        //
        // A key or a value that owns a release states no copy of its own, and nothing here can
        // duplicate what it owns: the table then states none either, and is handed over with '#move'.
        mtd opPostCopy()
        {
            if not .table do
                return

            if not .allocator do
                .allocator = Swag.getContext().allocator

            let oldTable = .tablePtr()
            let newTable = cast([*] HashTableEntry'(K, V)) Memory.alloc(.capacity * #sizeof(HashTableEntry'(K, V)), .allocator)
            #static if Reflection.hasDynamicStorage(HashTableEntry'(K, V)) do
                Swag.init(newTable, .capacity)
            else do
                Memory.clear(newTable, .capacity * #sizeof(HashTableEntry'(K, V)))
            #static if Reflection.hasPostCopy(K) or Reflection.hasPostCopy(V)
            {
                for i in .capacity
                {
                    let hashVal = oldTable[i].hash
                    if hashVal < HashTable.HASH_DELETED do
                        continue

                    newTable[i].hash  = hashVal
                    newTable[i].key   = #nodrop oldTable[i].key
                    newTable[i].value = #nodrop oldTable[i].value
                }
            }
            else
            {
                Memory.copy(newTable, oldTable, .capacity * #sizeof(HashTableEntry'(K, V)))
            }

            .table = newTable
        }
    }

    // Returns the address of the value mapped to `key` and asserts if the key is absent.
    mtd const opIndexPtr(key: K)->const *V => &.find(key).value

    // Returns the mutable address of the value mapped to `key` and asserts if the key is absent.
    //
    // See [[Core.HashTable.opIndexSet]] for insertion or update.
    mtd opIndexPtr(key: K)->*V => &.find(key).value

    // Maps `key` to a copy of `val`, replacing the value of an existing key.
    //
    // The value is copied in, so this only exists when it can be copied.
    mtd opIndexSet(key: K, val: V)
        where Reflection.canCopy(#typeof(V))
    {
        .add(key, val)
    }

    // Visits every entry in storage-slot order, binding `key` and `value`.
    //
    // The order is unspecified and changes when the table grows. Visiting by address binds mutable
    // pointers; otherwise struct halves are bound through constant pointers and others by value.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(key, value))
    {
        if not .count do
            return

        let table  = .constTablePtr()
        var remain = .count
        #scope(Up)
        for tableIndex in .capacity
        {
            if table[tableIndex].hash < HashTable.HASH_FIRST do
                continue

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(*K) &table[tableIndex].key, value = cast(*V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) and Reflection.isStruct(V) do
                    #inject(stmt, key = cast(const *K) &table[tableIndex].key, value = cast(const *V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const *K) &table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(V) do
                    #inject(stmt, key = table[tableIndex].key, value = cast(const *V) &table[tableIndex].value, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = table[tableIndex].key, value = table[tableIndex].value, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if not remain do
                break
        }
    }

    // Returns an immutable zero-allocation view that scans occupied slots in reverse order.
    mtd const reversed()->ReversedHashTable'(K, V) => {source: me}

    // Returns the hash of `key`, lifted above the reserved free and deleted slot markers.
    //
    // Only the two reserved values are lifted, never a whole bit: forcing a bit on
    // would make every starting probe index share it, so half of the slots could
    // only ever be reached by probing.
    #[Inline, Swag.NoDoc]
    func hashKey(key: K)->u32
    {
        let hashVal = Hash.hash32(key)
        return hashVal < HashTable.HASH_FIRST ? HashTable.HASH_FIRST : hashVal
    }

    // Drops every entry, releases the slots, and leaves the table empty.
    mtd free()
    {
        if not .table do
            return
        let table = .tablePtr()

        // Deleted slots still hold their key and value until they are reused.
        #static if Reflection.hasDrop(#typeof(K)) or Reflection.hasDrop(#typeof(V))
        {
            for i in .capacity where table[i].hash >= HashTable.HASH_DELETED
            {
                Swag.drop(&table[i].key)
                Swag.drop(&table[i].value)
            }
        }

        Memory.free(table, .capacity * #sizeof(HashTableEntry'(K, V)), .allocator)
        .table = null
        .count, .capacity, .deleted, .growThreshold = 0
    }

    // Returns whether the next insertion grows, and so rehashes, the table.
    //
    // Every insertion path asks, so it is a single compare against a threshold computed once per
    // resize. An empty table has a zero threshold and always grows.
    #[Inline, Swag.NoDoc]
    mtd const growsOnInsert()->bool => .count + .deleted >= .growThreshold

    // Doubles the capacity when the used slots, deleted ones included, reach half of it.
    #[Inline, Swag.NoDoc]
    mtd grow()
    {
        if .growsOnInsert() do
            .reserve(.capacity * 2)
    }

    // Grows the table to at least `newCapacity` slots, rehashing every entry.
    //
    // The slot count is rounded up to a power of two of at least 32. Requests at or below the
    // current capacity do nothing.
    mtd reserve(newCapacity: u64)
    {
        let reqCapacity = normalizeCapacity(newCapacity)
        if reqCapacity <= .capacity do
            return

        let oldTable = .table
        .count, .deleted = 0
        let newCapacityBytes = reqCapacity * #sizeof(HashTableEntry'(K, V))

        if not .allocator do
            .allocator = Swag.getContext().allocator
        .table = cast([*] HashTableEntry'(K, V)) Memory.alloc(newCapacityBytes, .allocator)
        let table = .tablePtr()

        // Every slot starts free, which is a zero hash.
        #static if Reflection.hasDynamicStorage(HashTableEntry'(K, V)) do
            Swag.init(table, reqCapacity)
        else do
            Memory.clear(table, newCapacityBytes)

        // Relocate the live entries into the new slots and drop the deleted ones.
        let oldCapacity = .capacity
        .capacity      = reqCapacity
        .growThreshold = reqCapacity / 2
        let oldTablePtr = oldTable orelse cast([*] HashTableEntry'(K, V)) 1'u64
        for i in oldCapacity
        {
            let h = oldTablePtr[i].hash
            if h >= HashTable.HASH_FIRST
            {
                .emplaceInternal(h, &oldTablePtr[i].key, &oldTablePtr[i].value)
            }
            elif h == HashTable.HASH_DELETED
            {
                Swag.drop(&oldTablePtr[i].key)
                Swag.drop(&oldTablePtr[i].value)
            }
        }

        Memory.free(oldTable, oldCapacity * #sizeof(HashTableEntry'(K, V)), .allocator)
    }

    // Returns the slot of `key`, or the slot where it would be inserted, probing linearly from `idx`.
    //
    // A deleted slot met on the way is reused when the key is absent.
    //
    // Both loops test the cached hash first: an occupied slot that does not match is by far
    // the most frequent outcome, and it must cost a single compare. A table that has never
    // seen a removal takes the shorter loop, which has no deleted slot to remember.
    #[Swag.NoDoc]
    mtd getNewIndex(key: K, idx: u64, hashVal: u64)->u64
    {
        let mask  = .capacity - 1
        var index = idx
        let table = .tablePtr()

        if not .deleted
        {
            for
            {
                let entryHash = table[index].hash
                if entryHash == hashVal
                {
                    if table[index].key == key do
                        return index
                }
                elif entryHash == HashTable.HASH_FREE do
                    return index

                index = (index + 1) & mask
            }
        }

        var firstDeleted = Swag.U64.Max
        for
        {
            let entryHash = table[index].hash
            if entryHash == hashVal
            {
                if table[index].key == key do
                    return index
            }
            elif entryHash < HashTable.HASH_FIRST
            {
                if entryHash == HashTable.HASH_FREE do
                    return firstDeleted != Swag.U64.Max ? firstDeleted : index
                if firstDeleted == Swag.U64.Max do
                    firstDeleted = index
            }

            index = (index + 1) & mask
        }
    }

    // Maps `key` to `value` and returns the entry.
    //
    // The key is always copied; the value is copied unless passed with `#move`. When `key` is
    // already present, its value is replaced only if `updateValue` is true.
    #[Discardable]
    mtd add(key: K, value: #fwd V, updateValue = true)->*HashTableEntry
        where Reflection.canCopy(#typeof(K))
    {
        // Growing rehashes the table a struct `key` or `value` may live in, so take them out first.
        // Any other key or value arrives by value and cannot alias the table.
        if .growsOnInsert()
        {
            #static if Reflection.isStruct(K) or Reflection.isStruct(V)
            {
                let stagedKey = key
                #static if Reflection.isStruct(V)
                {
                    var stagedValue: V = #fwd value
                    .grow()
                    return .add(stagedKey, #move stagedValue, updateValue)
                }
                else
                {
                    .grow()
                    return .add(stagedKey, value, updateValue)
                }
            }
            else
            {
                .grow()
            }
        }

        let hashVal = hashKey(key)
        var index   = cast(u64) hashVal & (.capacity - 1)
        let table   = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashTable.HASH_FIRST
        {
            if updateValue do
                table[index].value = #fwd value
            return table + index
        }

        if table[index].hash == HashTable.HASH_FREE
        {
            table[index].key   = #nodrop key
            table[index].value = #nodrop #fwd value
        }
        else
        {
            if table[index].hash == HashTable.HASH_DELETED do
                .deleted -= 1
            table[index].key   = key
            table[index].value = #fwd value
        }

        table[index].hash = hashVal
        .count += 1
        return table + index
    }

    // Relocates `key` and `value` into the table under a precomputed hash.
    //
    // Rehashing relocates every entry rather than copying it, so a value that owns a release
    // travels here untouched. The key is still compared by value through getNewIndex.
    #[Discardable, Swag.NoDoc]
    mtd emplaceInternal(hashVal: u32, key: *K, value: *V)->*HashTableEntry
        where Reflection.canCopy(#typeof(K))
    {
        .grow()

        var index = cast(u64) hashVal & (.capacity - 1)
        let table = .tablePtr()

        index = .getNewIndex(key[], index, hashVal)
        if table[index].hash >= HashTable.HASH_FIRST
        {
            Swag.drop(&table[index].value)
            table[index].value = #relocate value[]
            return table + index
        }

        if table[index].hash == HashTable.HASH_FREE
        {
            table[index].key   = #relocate key[]
            table[index].value = #relocate value[]
        }
        else
        {
            if table[index].hash == HashTable.HASH_DELETED do
                .deleted -= 1
            Swag.drop(&table[index].key)
            Swag.drop(&table[index].value)
            table[index].key   = #relocate key[]
            table[index].value = #relocate value[]
        }

        table[index].hash = hashVal
        .count += 1
        return table + index
    }

    // Removes the entry for `key`; does nothing when the key is absent.
    //
    // The slot is only marked as deleted: its key and value are dropped when the slot is reused,
    // when the table grows, or when it is cleared or freed.
    mtd remove(key: K)
    {
        if not .table do
            return

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .tablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key
            {
                table[index].hash = HashTable.HASH_DELETED
                .count   -= 1
                .deleted += 1
                return
            }

            index = (index + 1) & mask
        }
    }

    // Returns whether the table contains `key`.
    mtd const contains(key: K)->bool
    {
        if not .table do
            return false

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .constTablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return true
            index = (index + 1) & mask
        }

        return false
    }

    // Returns the entry for `key`, or null when the key is absent.
    mtd tryFind(key: K)->*HashTableEntry?
    {
        if not .table do
            return null

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .tablePtr()

        // Read each slot hash once, and test the match before the end of chain: a lookup walks
        // occupied slots, so that is the compare worth putting first.
        for
        {
            let entryHash = table[index].hash
            if entryHash == hashVal
            {
                if table[index].key == key do
                    return table + index
            }
            elif entryHash == HashTable.HASH_FREE do
                return null

            index = (index + 1) & mask
        }
    }

    // Returns the entry for `key`, or null when the key is absent.
    mtd const tryFind(key: K)->const *HashTableEntry?
    {
        if not .table do
            return null

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .constTablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return table + index
            index = (index + 1) & mask
        }

        return null
    }

    // Returns the entry for `key` and asserts if the key is absent.
    //
    // Use [[Core.HashTable.tryFind]] when the key can be absent.
    mtd find(key: K)->*HashTableEntry
    {
        let result = .tryFind(key)
        Swag.assert(result != null, "key not found")
        return result!
    }

    // Returns the entry for `key` and asserts if the key is absent.
    //
    // Use [[Core.HashTable.tryFind]] when the key can be absent.
    mtd const find(key: K)->const *HashTableEntry
    {
        let result = .tryFind(key)
        Swag.assert(result != null, "key not found")
        return result!
    }

    // Returns a copy of the value mapped to `key`, or `defaultValue` when the key is absent.
    mtd const getOrDefault(key: K, defaultValue: V)->V
    {
        let it = .tryFind(key)
        if not it do
            return defaultValue
        return it.value
    }

    // Returns the entry for `key`, adding one with a default-initialized value when the key is absent.
    //
    // The key is hashed and probed once, whether it is found or inserted, instead of
    // paying a full lookup and then a full insert on every miss.
    mtd findOrAdd(key: K)->*HashTableEntry
        where Reflection.canCopy(#typeof(K))
    {
        // Growing rehashes the table a struct `key` may live in, so take it out first.
        if .growsOnInsert()
        {
            #static if Reflection.isStruct(K)
            {
                let stagedKey = key
                .grow()
                return .findOrAdd(stagedKey)
            }
            else
            {
                .grow()
            }
        }

        let hashVal = hashKey(key)
        var index   = cast(u64) hashVal & (.capacity - 1)
        let table   = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashTable.HASH_FIRST do
            return table + index

        var val: V
        if table[index].hash == HashTable.HASH_FREE
        {
            table[index].key   = #nodrop key
            table[index].value = #nodrop val
        }
        else
        {
            .deleted           -= 1
            table[index].key   = key
            table[index].value = val
        }

        table[index].hash = hashVal
        .count += 1
        return table + index
    }

    // Drops every entry and leaves the table empty, keeping its slots for reuse.
    mtd clear()
    {
        // Free every slot, dropping what live and deleted slots still hold.
        if .count or .deleted
        {
            let table = .tablePtr()
            for i in .capacity
            {
                let hashval = table[i].hash

                if hashval >= HashTable.HASH_DELETED
                {
                    Swag.drop(&table[i].key)
                    Swag.drop(&table[i].value)
                }

                if hashval == HashTable.HASH_DELETED do
                    .deleted -= 1
                elif hashval >= HashTable.HASH_FIRST do
                    .count -= 1
                table[i].hash = HashTable.HASH_FREE

                // The remaining slots are already free once no live or deleted slot is left.
                if not .count and not .deleted do
                    break
            }
        }
    }
}

impl StrConv.IConvert for HashTable
{
    mtd const impl convert(buf: *ConcatBuffer, convFmt: StrConv.ConvertFormat, strFormat: string?)
    {
        buf.addBytes("[")
        var first = true
        for k, v in me
        {
            if not first do
                buf.addBytes(", ")
            first = false

            buf.addBytes("key = ")
            StrConv.convert'K(buf, k, convFmt, strFormat)
            buf.addBytes(" value = ")
            StrConv.convert'V(buf, v, convFmt, strFormat)
        }

        buf.addBytes("]")
    }
}
