#global export

// Represents a single memory block (a bucket) within a ConcatBuffer.
struct ConcatBufferBucket
{
    public readonly
    {
        data:        [*] u8?                  // Pointer to the raw memory of the bucket.
        next:        *ConcatBufferBucket?     // Pointer to the next bucket in the chain.
        count:       u64                      // Number of bytes used in this bucket.
        size:        u64                      // Total allocated size of this bucket in bytes.
        countBefore: u64                      // Total number of bytes in all preceding buckets.
    }
}

// Represents a position (seek) within a ConcatBuffer.
// It holds both the bucket and the specific pointer within that bucket.
struct ConcatBufferPosition
{
    public readonly
    {
        bucket:  *ConcatBufferBucket?     // The bucket containing the position.
        pointer: [*] u8?                  // The exact memory address of the position.
    }
}

// Represents a growable buffer that is divided into buckets (chunks of memory).
// This structure avoids large reallocations and copies when the buffer needs to grow,
// making it efficient for building data piece by piece.
// It owns its storage and can be moved with `#move`; implicit copies are rejected.
struct ConcatBuffer
{
    public
    {
        allocator:   Swag.IAllocator?     // The allocator to use for all memory operations.
        granularity: u64 = 1024           // The default size for newly allocated buckets.
    }

    // The bucket chain and the cursor inside it. Append and seek through the methods, which keep
    // the chain, the per-bucket counts and the cursor consistent.

    private
    {
        firstBucket:         *ConcatBufferBucket?     // The first bucket in the chain.
        curBucket:           *ConcatBufferBucket?     // The bucket the cursor is located in.
        lastBucket:          *ConcatBufferBucket?     // The last bucket in the chain.
        currentSP:           [*] u8?                  // The cursor inside `curBucket`.
        isAtEnd:             bool = true              // Whether the cursor is at the very end.
        embeddedFirstBucket: ConcatBufferBucket       // Embedded header for storage supplied by the caller.
        usesEmbeddedBucket:  bool                     // The first bucket header lives inside this value.
    }
}

// Iterates a borrowed concatenation buffer from its last bucket to its first.
#[Swag.Opaque]
struct ReversedConcatBuffer
{
    source: const *ConcatBuffer
}

impl ReversedConcatBuffer
{
    // Visits borrowed buckets from the last bucket to the first.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(bucket))
    {
        if not .source.firstBucket do
            return

        let firstBucket = .source.firstBucket!
        var tail        = .source.lastBucket!.next
        #scope(Up)
        while tail != firstBucket
        {
            var bucket = firstBucket
            while bucket.next != tail do
                bucket = bucket.next!

            #scope(Down)
            {
                #inject(stmt, bucket = bucket, break = break to Up, continue = break to Down)
            }

            tail = bucket
        }
    }
}

impl ConcatBuffer
{
    // Returns the total number of bytes in the buffer.
    mtd const opCount()->u64
    {
        return .count()
    }

    // Ensures all allocated memory is freed when the buffer goes out of scope.
    mtd opDrop()
    {
        .release()
    }

    // Rebinds an embedded bucket header after ownership moves to another value.
    mtd opPostMove()
    {
        if not .usesEmbeddedBucket do
            return
        let previousFirst = .firstBucket
        .firstBucket = &.embeddedFirstBucket
        if .curBucket == previousFirst do
            .curBucket = .firstBucket
        if .lastBucket == previousFirst do
            .lastBucket = .firstBucket
    }

    // Provides a way to iterate over each bucket in the buffer.
    // This is a macro that accepts a code block to execute for each bucket.
    // Block parameter: 'bucket' is the bucket pointer.
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(bucket))
    {
        if not .firstBucket do
            return
        let lastBucket = .lastBucket!
        var b = .firstBucket
        #scope(Up)
        while b != lastBucket.next
        {
            let bucket = b!
            #scope(Down)
            {
                #inject(stmt, bucket = bucket, break = break to Up, continue = break to Down)
            }

            b = bucket.next
        }
    }

    // Returns an immutable zero-allocation view that traverses buckets from last to first.
    mtd const reversed()->ReversedConcatBuffer
    {
        return {source: me}
    }

    // Returns the total number of bytes currently stored in the buffer.
    mtd const count()->u64
    {
        return .lastBucket ? .lastBucket.countBefore + .lastBucket.count : 0
    }

    // Ensures that there is enough room to store at least 'numBytes' more bytes.
    // If the current bucket is full, a new one is allocated.
    private mtd grow(numBytes: u64)
    {
        Swag.assert(.isAtEnd)

        if .lastBucket
        {
            let lastBucket = .lastBucket
            let currentSP  = .currentSP!
            let data       = lastBucket.data!

            // Enough room in the last bucket
            let seek = cast(u64) (currentSP - data)
            if numBytes <= lastBucket.size - seek do
                return

            // Reuse a bucket retained by clear() or truncate() when it is large enough.
            if lastBucket.next and numBytes <= lastBucket.next.size
            {
                let nextBucket = lastBucket.next
                nextBucket.countBefore = lastBucket.countBefore + lastBucket.count
                nextBucket.count       = 0

                .curBucket, .lastBucket = nextBucket
                .currentSP = nextBucket.data
                return
            }
        }

        // Need to allocate a new bucket
        if not .allocator do
            .allocator = Swag.getContext().allocator
        let newBucket = Memory.new'ConcatBufferBucket(.allocator)

        if .lastBucket
        {
            let lastBucket = .lastBucket
            newBucket.next  = lastBucket.next
            lastBucket.next = newBucket
        }
        else do
            .firstBucket = newBucket

        // Each bucket knows the total count before it
        if .firstBucket and .lastBucket == .firstBucket do
            newBucket.countBefore = .firstBucket.count
        elif .lastBucket do
            newBucket.countBefore = .lastBucket.countBefore + .lastBucket.count

        .curBucket, .lastBucket = newBucket

        let bsize      = Math.max(.granularity, numBytes)
        let lastBucket = .lastBucket!
        lastBucket.data = Memory.alloc(bsize, .allocator)
        lastBucket.size = bsize
        .currentSP      = lastBucket.data
    }

    // Associates a specific allocator with the buffer.
    // This can only be called when the buffer is empty.
    mtd setAllocator(alloc: Swag.IAllocator)
    {
        Swag.assert(.firstBucket == null, "buffer is not empty")
        .allocator = alloc
    }

    // Sets the minimum size for new buckets allocated by the buffer.
    mtd setBucketSize(size: u64)
    {
        Swag.assert(size >= 4)
        .granularity = size
    }

    // Frees all memory associated with the buffer, including all buckets.
    //
    // Leaves an empty, reusable buffer with the same allocator and bucket size.
    // Every borrowed bucket, position, and byte pointer is invalidated. Repeated calls are safe.
    mtd release()
    {
        if not .firstBucket do
            return

        var ptr = .firstBucket
        while ptr
        {
            let bucket  = ptr
            let nextPtr = bucket.next
            Memory.free(bucket.data, bucket.size, .allocator)
            if bucket != &.embeddedFirstBucket do
                Memory.free(bucket, #sizeof(ConcatBufferBucket), .allocator)
            ptr = nextPtr
        }

        let allocator   = .allocator
        let granularity = .granularity
        Swag.init(me, 1)
        .allocator   = allocator
        .granularity = granularity
    }

    // Clears the buffer's content without deallocating memory.
    // This resets the buffer to be empty, allowing its allocated buckets to be reused.
    mtd clear()
    {
        if not .firstBucket do
            return

        let firstBucket = .firstBucket
        .curBucket, .lastBucket = firstBucket
        .currentSP = firstBucket.data
        firstBucket.countBefore, firstBucket.count = 0
        .isAtEnd   = true
    }

    // Writes a native value at the cursor, overwriting or extending the buffer as needed.
    mtd(T) addNative(val: T)
    {
        if not .isAtEnd
        {
            let curBucket = .curBucket!
            let currentSP = .currentSP!
            let data      = curBucket.data!

            // If not enough room in the current bucket, then we
            // have to split the content with the next bucket
            if #sizeof(T) > curBucket.count or
               currentSP > data + curBucket.count - #sizeof(T)
            {
                var v = val
                .addBytes(Swag.makeSlice(cast([*] u8) &v, #sizeof(T)), false)
                return
            }

            currentSP[as T] = val
            .currentSP      += #sizeof(T)
            .setIsAtEnd()
        }
        else
        {
            .grow(#sizeof(T))
            let curBucket = .curBucket!
            let currentSP = .currentSP!
            currentSP[as T] = val
            .currentSP      += #sizeof(T)
            curBucket.count += #sizeof(T)
        }
    }

    // Writes the raw bytes of a struct contiguously at the cursor, like [[addBytes]].
    #[Swag.Inline]
    mtd(T) addStruct(val: T)
    {
        .addBytes(Swag.makeSlice(cast(const [*] u8) &val, #sizeof(T)))
    }

    // Writes bytes at the cursor, overwriting existing bytes and extending the buffer as needed.
    // A contiguous write occupies one bucket; crossing existing buckets merges the buffer and
    // invalidates its borrowed positions and pointers. With `contiguous` false, bytes may span
    // buckets. Input borrowed from this buffer is copied before an overwrite can invalidate it.
    mtd addBytes(bytes: const [..] u8?, contiguous = true)
    {
        var num = bytes.count
        if not num do
            return
        Swag.assert(num <= Swag.U64.Max - offsetOf(.position()))

        // Appending preserves existing bytes. Overwriting may change or release the source.
        if not .isAtEnd
        {
            for bucket in me
            {
                if bytes.buffer >= bucket.data and bytes.buffer < bucket.data + bucket.count
                {
                    var copy: String
                    copy.allocator = .allocator
                    copy.append(Swag.makeString(bytes.buffer, num))
                    .addBytes(cast(const [..] u8) copy.toString(), contiguous)
                    return
                }
            }
        }

        var slicePtr = bytes.buffer
        if contiguous
        {
            let destination = .reserveInPlace(num)
            Memory.copy(destination, slicePtr, num)
            return
        }

        if not .lastBucket do
            .grow(1)
        while num
        {
            let bucket    = .curBucket!
            let offset    = cast(u64) (.currentSP - bucket.data)
            let available = (.isAtEnd ? bucket.size : bucket.count) - offset
            let chunk     = Math.min(num, available)
            Memory.copy(.currentSP, slicePtr, chunk)
            if .isAtEnd do
                bucket.count += chunk
            .currentSP, slicePtr += chunk
            num -= chunk
            .setIsAtEnd()
            if not num do
                return

            if .isAtEnd do
                .grow(Math.max(.granularity, 1'u64))
            else
            {
                .curBucket = bucket.next!
                .currentSP = .curBucket.data
            }
        }
    }

    // Returns the absolute byte offset represented by `position`.
    func offsetOf(position: ConcatBufferPosition)->u64
    {
        return position.bucket ? position.bucket.countBefore + cast(u64) (position.pointer - position.bucket.data) : 0
    }

    // Returns the current write position, including after restoring an earlier position.
    mtd const position()->ConcatBufferPosition
    {
        var result: retval
        result.bucket  = .curBucket
        result.pointer = .currentSP
        return result
    }

    // Reserves `count` contiguous bytes at the cursor and returns where to write them.
    //
    // The cursor moves past the reserved bytes, so the caller fills them in place and keeps
    // appending afterwards. Existing bytes outside the reservation are preserved. Crossing an
    // existing bucket boundary merges the buffer and invalidates earlier borrowed positions and
    // pointers. A zero-byte reservation does not move the cursor but may allocate on an empty buffer.
    mtd reserveInPlace(count: u64)->[*] u8
    {
        if .isAtEnd
        {
            Swag.assert(count <= Swag.U64.Max - .count())
            if count or not .lastBucket do
                .grow(Math.max(count, 1'u64))
            let result = .currentSP!
            let bucket = .lastBucket!
            .currentSP   += count
            bucket.count += count
            return result
        }

        let bucket = .curBucket!
        let offset = cast(u64) (.currentSP - bucket.data)
        if count <= bucket.count - offset or (.curBucket == .lastBucket and count <= bucket.size - offset)
        {
            let result = .currentSP!
            .currentSP   += count
            bucket.count = Math.max(bucket.count, offset + count)
            .setIsAtEnd()
            return result
        }

        let position = offsetOf(.position())
        Swag.assert(count <= Swag.U64.Max - position)
        let end = position + count
        .rebuildLinear(Math.max(.count(), end))
        let firstBucket = .firstBucket!
        let result      = firstBucket.data! + position
        firstBucket.count = Math.max(firstBucket.count, end)
        .currentSP        = result + count
        .setIsAtEnd()
        return result
    }

    // Advances the cursor by `num` bytes, growing the buffer when needed.
    mtd advance(num: u64)
    {
        if not num do
            return
        var total = num

        while not .isAtEnd
        {
            let curBucket = .curBucket!
            let seek      = cast(u64) (.currentSP - curBucket.data)
            let available = curBucket.count - seek
            if total <= available
            {
                .currentSP += total
                .setIsAtEnd()
                return
            }

            total -= available
            if curBucket == .lastBucket
            {
                .currentSP = curBucket.data + curBucket.count
                .isAtEnd   = true
                break
            }

            .curBucket = curBucket.next!
            .currentSP = .curBucket.data
        }

        .grow(total)
        let curBucket = .curBucket!
        .currentSP      += total
        curBucket.count += total
    }

    #[Swag.Inline]
    private mtd setIsAtEnd()
    {
        let lastBucket = .lastBucket!
        .isAtEnd = .curBucket == .lastBucket and .currentSP == lastBucket.data + lastBucket.count
    }

    // Restores a position borrowed from this buffer; a default position selects its beginning.
    mtd setPosition(position: ConcatBufferPosition)
    {
        if not position.bucket
        {
            if not .firstBucket do
                return
            let firstBucket = .firstBucket
            .curBucket = firstBucket
            .currentSP = firstBucket.data
        }
        else
        {
            .curBucket = position.bucket
            .currentSP = position.pointer
        }

        .setIsAtEnd()
    }

    // Truncates at a borrowed position; a default position clears the buffer and retains storage.
    mtd truncate(position: ConcatBufferPosition)
    {
        if not position.bucket
        {
            .clear()
        }
        else
        {
            let bucket = position.bucket
            .curBucket, .lastBucket = bucket
            .currentSP   = position.pointer
            bucket.count = cast(u64) (position.pointer - bucket.data)
            .isAtEnd     = true
        }
    }

    // Returns the buffer's content as a slice, but only if the buffer is 'linear'.
    //
    // A buffer is linear if it consists of a single bucket. Returns 'null' when no bucket
    // has been allocated or when several buckets hold content. The slice borrows the buffer.
    // See [[makeLinear]].
    mtd toSlice()->[..] u8?
    {
        if not .firstBucket do
            return null
        if .lastBucket == .firstBucket
        {
            let firstBucket = .firstBucket
            return Swag.makeSlice(firstBucket.data, firstBucket.count)
        }

        return null
    }

    // Borrows read-only bytes when the buffer has one active bucket; otherwise returns null.
    mtd const toSlice()->const [..] u8?
    {
        if not .firstBucket or .lastBucket != .firstBucket do
            return null
        let firstBucket = .firstBucket
        return Swag.makeSlice(cast(const [*] u8?) firstBucket.data, firstBucket.count)
    }

    // Initializes the buffer by taking ownership of an existing slice as its first bucket.
    // The slice supplies capacity, not content: the buffer starts empty. Its storage must be
    // releasable through the selected allocator, which is captured from the context when unset.
    // The bucket header remains embedded; moving the buffer invalidates positions in that header.
    mtd setFirstBucket(data: [..] u8)
    {
        Swag.assert(.firstBucket == null)
        if not .allocator do
            .allocator = Swag.getContext().allocator
        Swag.init(&.embeddedFirstBucket, 1)
        .embeddedFirstBucket.data = data.buffer
        .embeddedFirstBucket.size = data.count
        .usesEmbeddedBucket       = true
        .firstBucket, .lastBucket, .curBucket = &.embeddedFirstBucket
        .currentSP = .embeddedFirstBucket.data
    }

    // Converts the buffer to a [[Core.String]] by copying its content.
    //
    // The buffer remains valid after this call.
    // See [[Core.ConcatBuffer.moveToString]] to reuse linear storage when possible.
    mtd const toString(alloc: Swag.IAllocator? = null)->String
    {
        var result: retval
        if not .firstBucket do
            return result

        result.allocator = alloc
        result.reserve(.count() + 1)

        let lastBucket = .lastBucket!
        var ptr        = .firstBucket
        while ptr != lastBucket.next
        {
            let b = ptr!
            result.append(Swag.makeString(b.data, b.count))
            ptr = b.next
        }

        return result
    }

    // Copies all content into one independently owned byte array using `alloc`.
    //
    // A null allocator selects the current context allocator. The buffer's buckets, cursor,
    // and borrowed positions remain unchanged. An empty result allocates no storage.
    mtd const toArray(alloc: Swag.IAllocator? = null)->Array'u8
    {
        var result: retval
        result.allocator = alloc
        result.reserve(.count())
        for bucket in me do
            result.add(Swag.makeSlice(bucket.data, bucket.count))
        return result
    }

    private mtd eatBuffer()->{ data: [*] u8, size: u64, capacity: u64 }
    {
        // Must be linear ?
        Swag.assert(.lastBucket == .firstBucket)

        let firstBucket = .firstBucket!
        let rdata       = firstBucket.data!
        let rcount      = firstBucket.count
        let rcapacity   = firstBucket.size

        // Transfer the bytes, then release the header and any buckets retained by clear().
        firstBucket.data = null
        .release()

        return {rdata, rcount, rcapacity}
    }

    // Returns an owned string, transferring a single heap bucket when possible.
    //
    // Transferring storage leaves the buffer empty and reusable and invalidates its borrows.
    // Storage grows when needed to satisfy String capacity and null-termination requirements.
    // Multiple active buckets or an embedded first bucket are copied, leaving the buffer intact.
    // A buffer without allocated storage returns an empty string.
    mtd moveToString()->String
    {
        if not .firstBucket do
            return {}

        // We can only steal the storage when the buffer owns a single heap bucket.
        if .lastBucket != .firstBucket or .firstBucket == &.embeddedFirstBucket do
            return .toString(.allocator)

        // Otherwise we can just eat the buffer
        let eat = .eatBuffer()
        with var result: retval
        {
            .allocator = me.allocator
            .buffer    = eat.data
            .capacity  = eat.capacity
            .length    = eat.size

            // String identifies inline storage by capacity and requires a trailing zero.
            .grow(Math.max(eat.size + 1, StringSmallSize + 1))
            .storage()[.length] = 0
        }

        return result
    }

    // Merges all buckets into a single, contiguous memory block.
    // Merging invalidates all borrowed buckets, positions, and pointers and moves the cursor
    // to the end. An already linear or unallocated buffer is unchanged.
    mtd makeLinear()
    {
        // Already linear (and only one single bucket)
        if .lastBucket == .firstBucket do
            return

        let total = .count()
        if not total
        {
            .release()
            return
        }

        .rebuildLinear(total)
    }

    private mtd rebuildLinear(capacity: u64)
    {
        let total = .count()
        Swag.assert(capacity >= total)
        let newDatas = cast([*] u8) Memory.alloc(capacity, .allocator)

        var curPtr = newDatas
        for b in me
        {
            Memory.copy(curPtr, b.data, b.count)
            curPtr += b.count
        }

        Swag.assert(curPtr == newDatas + total)
        .release()

        // Make one single bucket
        .firstBucket            = Memory.new'ConcatBufferBucket(.allocator)
        .firstBucket.data       = newDatas
        .firstBucket.size       = capacity
        .firstBucket.count      = total
        .curBucket, .lastBucket = .firstBucket
        .currentSP              = .firstBucket.data + .firstBucket.count
        .isAtEnd                = true
    }
}
