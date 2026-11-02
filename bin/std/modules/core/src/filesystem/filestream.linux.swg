#global if #os == Swag.TargetOs.Linux
#global namespace File

// Encode fd + 1 so descriptor zero is distinct from the closed handle sentinel.
internal func nativeFileHandle(descriptor: s32)->FileHandle => cast(FileHandle, cast(u64, cast(s64, descriptor) + 1))
internal func nativeFileDescriptor(handle: FileHandle)->s32 => cast(s32, cast(s64, handle) - 1)

internal impl FileStream
{
    mtd readNative(buffer: *void, length: u32)->u32 fail
    {
        let bytes = cast([*] u8, buffer)
        var total = 0'u32

        // Linux caps each read below 2 GiB and may return a partial read on interruption.
        // The common stream layer treats a short chunk as EOF, so fill it here when possible.
        while total < length
        {
            let count = Linux.read(nativeFileDescriptor(.handle), bytes + total, length - total)
            if count > 0
            {
                total += cast(u32, count)
            }
            elif count == 0
            {
                break
            }
            else
            {
                let error = Linux.errno()
                if error != Linux.EINTR do
                    try Errors.failLinuxError(error, .name)
            }
        }

        return total
    }

    mtd writeNative(buffer: const *void, length: u32)->u32 fail
    {
        for
        {
            let count = Linux.write(nativeFileDescriptor(.handle), buffer, length)
            if count >= 0 do
                return cast(u32, count)
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error, .name)
        }
    }

    mtd closeNative()
    {
        // Linux releases the descriptor even when close reports EINTR. Retrying could close
        // an unrelated descriptor another thread has just acquired under the reused number.
        discard Linux.close(nativeFileDescriptor(.handle))
    }

    mtd sizeNative()->u64 fail
    {
        var info: Linux.stat
        for
        {
            if Linux.fstat(nativeFileDescriptor(.handle), &info) == 0 do
                return cast(u64, info.st_size)
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error, .name)
        }
    }

    mtd resizeNative() fail
    {
        let position = try .positionNative()
        for
        {
            if Linux.ftruncate(nativeFileDescriptor(.handle), cast(s64, position)) == 0 do
                return
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error, .name)
        }
    }

    mtd flushNative() fail
    {
        for
        {
            if Linux.fsync(nativeFileDescriptor(.handle)) == 0 do
                return
            let error = Linux.errno()
            if error != Linux.EINTR do
                try Errors.failLinuxError(error, .name)
        }
    }

    mtd positionNative()->u64 fail
    {
        let position = Linux.lseek(nativeFileDescriptor(.handle), 0, Linux.SEEK_CUR)
        if position < 0 do
            try Errors.failLinuxError(Linux.errno(), .name)
        return cast(u64, position)
    }

    mtd seekNative(origin: SeekOrigin, offset: u64) fail
    {
        var whence: s32
        switch #complete origin
        {
        case .Begin:   whence = Linux.SEEK_SET
        case .Current: whence = Linux.SEEK_CUR
        case .End:     whence = Linux.SEEK_END
        }

        // Relative seeks retain the existing API's signed interpretation of the u64 bits.
        let position = Linux.lseek(nativeFileDescriptor(.handle), cast #bit (s64, offset), whence)
        if position < 0 do
            try Errors.failLinuxError(Linux.errno(), .name)
    }
}
