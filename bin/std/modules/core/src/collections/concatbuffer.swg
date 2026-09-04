#global public

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
        firstBucket:     *ConcatBufferBucket?     // The first bucket in the chain.
        curBucket:       *ConcatBufferBucket?     // The bucket the cursor is located in.
        lastBucket:      *ConcatBufferBucket?     // The last bucket in the chain.
        currentSP:       [*] u8?                  // The cursor inside `curBucket`.
        isAtEnd:         bool = true              // Whether the cursor is at the very end.
        viewFirstBucket: ConcatBufferBucket       // Bucket reused by views, to skip an allocation.
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
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(bucket))
    {
        if !.source.firstBucket do
            return

        let firstBucket = .source.firstBucket!
        var tail        = .source.lastBucket!.next
        while tail != firstBucket
        {
            var bucket = firstBucket
            while bucket.next != tail do
                bucket = bucket.next!

            #inject(stmt, bucket = bucket)
            tail = bucket
        }
    }
}

impl ConcatBuffer
{
    // Returns the total number of bytes in the buffer.
    mtd opCount()->u64
    {
        return .count()
    }

    // Ensures all allocated memory is freed when the buffer goes out of scope.
    mtd opDrop()
    {
        .release()
    }

    // Provides a way to iterate over each bucket in the buffer.
    // This is a macro that accepts a code block to execute for each bucket.
    // Block parameter: 'bucket' is the bucket pointer.
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(bucket))
    {
        if !.firstBucket do
            return
        let lastBucket = .lastBucket!
        var b          = .firstBucket
        while b != lastBucket.next
        {
            let bucket = b!
            #inject(stmt, bucket = bucket)

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
    #[Swag.NoDoc]
    mtd grow(numBytes: u64)
    {
        Debug.assert(.isAtEnd)

        if .lastBucket
        {
            let lastBucket = .lastBucket
            let currentSP  = .currentSP!
            let data       = lastBucket.data!

            // Enough room in the last bucket
            let seek = cast(u64) (currentSP - data)
            if seek + numBytes <= lastBucket.size do
                return

            // Not enough room in the last bucket, but with have a bucket after that
            // can old the bytes (because of a previous clear())
            if lastBucket.next and numBytes <= lastBucket.next.size
            {
                let nextBucket = lastBucket.next
                nextBucket.countBefore = lastBucket.countBefore + lastBucket.count
                nextBucket.count       = 0

                .curBucket, .lastBucket = nextBucket
                .currentSP              = nextBucket.data
                return
            }
        }

        // Need to allocate a new bucket
        if !.allocator do
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
        Debug.assert(.firstBucket == null, "buffer is not empty")
        .allocator = alloc
    }

    // Sets the minimum size for new buckets allocated by the buffer.
    mtd setBucketSize(size: u64)
    {
        Debug.assert(size >= 4)
        .granularity = size
    }

    // Frees all memory associated with the buffer, including all buckets.
    mtd release()
    {
        if !.firstBucket do
            return

        var ptr = .firstBucket
        while ptr
        {
            let bucket  = ptr
            let nextPtr = bucket.next
            Memory.free(bucket.data, bucket.size, .allocator)
            if bucket != &.viewFirstBucket do
                Memory.free(bucket, #sizeof(ConcatBufferBucket), .allocator)
            ptr = nextPtr
        }

        .firstBucket = null
        .clear()
    }

    // Clears the buffer's content without deallocating memory.
    // This resets the buffer to be empty, allowing its allocated buckets to be reused.
    mtd clear()
    {
        if !.firstBucket do
            return

        let firstBucket = .firstBucket
        .curBucket, .lastBucket = firstBucket
        .currentSP              = firstBucket.data
        firstBucket.countBefore, firstBucket.count = 0
        .isAtEnd                = true
    }

    // Appends a native type (like u8, s32, f64) to the buffer.
    mtd(T) addNative(val: T)
    {
        if !.isAtEnd
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

    // Appends the raw byte content of a struct to the buffer.
    #[Swag.Inline]
    mtd(T) addStruct(val: T)
    {
        .addBytes(Swag.makeSlice(cast(const [*] u8) &val, #sizeof(T)))
    }

    // Appends a slice of bytes to the buffer.
    // If 'contiguous' is false, the slice can be split across multiple buckets if necessary.
    mtd addBytes(bytes: const [..] u8?, contiguous = true)
    {
        var num = bytes.count
        if !num do
            return

        var slicePtr = bytes.buffer

        // Be sure we have a buffer
        if !.lastBucket do
            .grow(1)

        // Divide the slice in the given amount of buckets if necessary
        if !contiguous
        {
            // Overwrite
            if !.isAtEnd
            {
                var curBucket = .curBucket!
                let curCount  = cast(u64) (.currentSP - curBucket.data)
                var remain    = curBucket.count - curCount
                while num > remain
                {
                    Memory.copy(.currentSP, slicePtr, remain)
                    num -= remain
                    slicePtr, .currentSP += remain
                    if !num do
                        return

                    // We have reached the end
                    // So we must grow
                    if !curBucket.next
                    {
                        .isAtEnd = true
                        .grow(num)
                        break
                    }

                    curBucket  = curBucket.next!
                    .curBucket = curBucket
                    .currentSP = curBucket.data
                    remain     = curBucket.count
                }

                Memory.copy(.currentSP, slicePtr, num)
                .currentSP += num
                if .isAtEnd
                {
                    let cb = .curBucket!
                    cb.count += num
                }
                else do
                    .setIsAtEnd()
                return
            }

            // Append
            else
            {
                var lastBucket = .lastBucket!
                let curCount   = cast(u64) (.currentSP - lastBucket.data)
                var remain     = lastBucket.size - curCount
                while num > remain
                {
                    Memory.copy(.currentSP, slicePtr, remain)
                    num                  -= remain
                    slicePtr, .currentSP += remain
                    lastBucket.count     += remain
                    if !num do
                        return
                    .grow(.granularity)     // Will alloc a new bucket as the current one is full
                    lastBucket = .lastBucket!
                    remain     = lastBucket.size
                }
            }
        }
        else
        {
            .grow(num)
        }

        // We should have enough size in the last bucket to store the
        // rest of the slice
        Memory.copy(.currentSP, slicePtr, num)
        .currentSP += num
        let lastBucket = .lastBucket!
        lastBucket.count += num
    }

    // Returns the absolute byte offset represented by `position`.
    func offsetOf(position: ConcatBufferPosition)->u64
    {
        return position.bucket ? position.bucket.countBefore + cast(u64) (position.pointer - position.bucket.data) : 0
    }

    // Returns the current write position.
    mtd position()->ConcatBufferPosition
    {
        var result: retval
        result.bucket  = .lastBucket
        result.pointer = .currentSP
        return result
    }

    // Reserves `count` bytes at the cursor and returns where to write them.
    //
    // The cursor moves past the reserved bytes, so the caller fills them in place and keeps
    // appending afterwards. The returned pointer stays valid until the next call that grows the
    // buffer. Reserve first and write later when the content depends on what follows, as a
    // length or a checksum field does.
    mtd reserveInPlace(count: u64)->[*] u8
    {
        let result = .currentSP!
        .advance(count)
        return cast([*] u8) result
    }

    // Advances the cursor by `num` bytes, growing the buffer when needed.
    mtd advance(num: u64)
    {
        var total = num

        if !.isAtEnd
        {
            var curBucket = .curBucket!
            var seek      = cast(u64) (.currentSP - curBucket.data)
            while curBucket.next and seek + total > curBucket.count
            {
                total -= (curBucket.count - seek)
                if !curBucket.next do
                    break
                curBucket  = curBucket.next!
                .curBucket = curBucket
                .currentSP = curBucket.data
                seek       = 0
            }

            if seek + total <= curBucket.count
            {
                .currentSP += total
                return
            }

            total    -= (curBucket.count - seek)
            .isAtEnd = true
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
        .isAtEnd = .currentSP == lastBucket.data + lastBucket.count
    }

    // Sets the current read/write position.
    mtd setPosition(position: ConcatBufferPosition)
    {
        if !position.bucket
        {
            let firstBucket = .firstBucket!
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

    // Truncates the buffer at `position` and moves the cursor there.
    mtd truncate(position: ConcatBufferPosition)
    {
        if !position.bucket
        {
            let firstBucket = .firstBucket!
            .curBucket, .lastBucket = firstBucket
            .currentSP              = firstBucket.data
            firstBucket.count       = 0
            .isAtEnd                = true
        }
        else
        {
            let bucket = position.bucket
            .curBucket, .lastBucket = bucket
            .currentSP              = position.pointer
            bucket.count            = cast(u64) (position.pointer - bucket.data)
            .isAtEnd                = true
        }
    }

    // Returns the buffer's content as a slice, but only if the buffer is 'linear'.
    // A buffer is linear if it consists of a single bucket. Returns 'null' otherwise.
    // See [[makeLinear]].
    mtd toSlice()->[..] u8?
    {
        if .lastBucket == .firstBucket
        {
            let firstBucket = .firstBucket!
            return Swag.makeSlice(firstBucket.data, firstBucket.count)
        }

        return null
    }

    // Initializes the buffer by taking ownership of an existing slice as its first bucket.
    // The slice is released through the buffer's allocator; its bucket header remains embedded.
    mtd setFirstBucket(data: [..] u8)
    {
        Debug.assert(.firstBucket == null)
        Swag.init(&.viewFirstBucket, 1)
        .viewFirstBucket.data                 = data.buffer
        .viewFirstBucket.size                 = data.count
        .firstBucket, .lastBucket, .curBucket = &.viewFirstBucket
        .currentSP                            = .viewFirstBucket.data
    }

    // Converts the buffer to a [[Core.String]] by copying its content.
    //
    // The buffer remains valid after this call.
    // See [[Core.ConcatBuffer.moveToString]] to reuse linear storage when possible.
    mtd const toString(alloc: Swag.IAllocator? = null)->String
    {
        var result: retval
        if !.firstBucket do
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

    private mtd eatBuffer()->{ data: [*] u8, size: u64, capacity: u64 }
    {
        // Must be linear ?
        Debug.assert(.lastBucket == .firstBucket)

        let firstBucket = .firstBucket!
        let rdata       = firstBucket.data!
        let rcount      = firstBucket.count
        let rcapacity   = firstBucket.size

        if firstBucket != &.viewFirstBucket do
            Memory.free(firstBucket, #sizeof(ConcatBufferBucket), .allocator)
        .firstBucket = null

        return {rdata, rcount, rcapacity}
    }

    // Moves the buffer's content into a new 'String', invalidating the buffer.
    // If the buffer is linear (one bucket), this is a fast operation that avoids copying.
    // Otherwise, it falls back to copying the data.
    mtd moveToString()->String
    {
        // We can only steal the storage when the buffer owns a single heap bucket.
        if .lastBucket != .firstBucket or .firstBucket == &.viewFirstBucket do
            return .toString(.allocator)

        // Otherwise we can just eat the buffer
        let eat = .eatBuffer()
        with var result: retval
        {
            .allocator = me.allocator
            .buffer    = eat.data
            .capacity  = eat.capacity
            .length    = eat.size
        }

        return result
    }

    // Merges all buckets into a single, contiguous memory block.
    // After this call, the buffer is guaranteed to be linear.
    mtd makeLinear()
    {
        // Already linear (and only one single bucket)
        if .lastBucket == .firstBucket do
            return

        let total = .count()
        if !total
        {
            .release()
            return
        }

        let newDatas = cast([*] u8) Memory.alloc(total, .allocator)

        var curPtr = newDatas
        for b in me
        {
            Memory.copy(curPtr, b.data, b.count)
            curPtr += b.count
        }

        Debug.assert(curPtr == newDatas + total)
        .release()

        // Make one single bucket
        .firstBucket            = Memory.new'ConcatBufferBucket(.allocator)
        .firstBucket.data       = newDatas
        .firstBucket.size       = total
        .firstBucket.count      = total
        .curBucket, .lastBucket = .firstBucket
        .currentSP              = .firstBucket.data + .firstBucket.count
        .isAtEnd                = true
    }
}
