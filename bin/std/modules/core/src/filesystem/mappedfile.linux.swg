#global if #os == Swag.TargetOs.Linux
#global namespace File

internal impl MappedRegion
{
    func releasePagesNative(bytes: const [..] u8)
    {
        let pageSize = cast(u64, Linux.getpagesize())
        let address  = cast(u64, bytes.buffer)
        let start    = address / pageSize * pageSize
        let prefix   = address - start
        if bytes.count > Swag.U64.Max - prefix do
            return

        // Unlike MADV_DONTNEED, PAGEOUT preserves private dirty and anonymous bytes.
        // Unsupported or pinned pages may remain resident: this is only an accounting hint.
        discard Linux.madvise(cast(*void, start), prefix + bytes.count, Linux.MADV_PAGEOUT)
    }
}
