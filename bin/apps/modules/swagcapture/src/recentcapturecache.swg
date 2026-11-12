// A decoded picture is owned by the recent window while it is away from the editor.
struct RecentCachedCapture
{
    capture: *Capture?
    revision: File.FileInfo
    bytes:    u64
}

impl RecentCachedCapture
{
    mtd opDrop()
    {
        if .capture do
            Memory.delete(.capture)
    }
}

// A byte-bounded LRU of decoded recent pictures. The active document is never in this cache.
struct RecentCaptureCache
{
    const MaxBytes = 128 * 1024 * 1024

    entries: ArrayPtr'RecentCachedCapture
    bytes:   u64
    maxBytes: u64 = MaxBytes
}

impl RecentCaptureCache
{
    func sameRevision(a, b: File.FileInfo)->bool =>
        not a.fullName.isEmpty() and not b.fullName.isEmpty() and
        a.size == b.size and a.creationTime == b.creationTime and a.lastWriteTime == b.lastWriteTime

    // Returns ownership only while the on-disk file still has the version that was decoded.
    mtd take(file: string, revision: *File.FileInfo)->*Capture?
    {
        for item, i in .entries
        {
            let entry   = unwrap item
            if not entry.capture do
                continue
            if entry.capture.file != file do
                continue
            let current = catch File.info(file)
            let valid   = sameRevision(entry.revision, current)
            let result  = valid ? entry.capture : null
            if valid
            {
                entry.capture = null
                revision[]    = current
            }
            .bytes -= entry.bytes
            .entries.deleteAt(i)
            return result
        }

        return null
    }

    // Takes ownership even when the picture is too large or has become stale.
    mtd put(capture: *Capture, revision: File.FileInfo)
    {
        let current = catch File.info(capture.file)
        if capture.changed or capture.isTimed() or g_CaptureSaves.writing(capture.file) or
           not sameRevision(revision, current)
        {
            Memory.delete(capture)
            return
        }

        var size = cast(u64, capture.backImg.byteCount + capture.backImgOriginal.byteCount + capture.preview.byteCount + capture.previewBytes.count)
        for form in capture.forms where Swag.kindOf(form) == FormImage do
            size += (assume cast(*FormImage, form)).image.byteCount
        if size > .maxBytes
        {
            Memory.delete(capture)
            return
        }

        .invalidate(capture.file)
        capture.detachView()
        with let entry = .entries.addNew()
        {
            .capture  = capture
            .revision = current
            .bytes    = size
        }
        .bytes += size
        while .bytes > .maxBytes
        {
            .bytes -= .entries[0]!.bytes
            .entries.deleteAt(0)
        }
    }

    mtd invalidate(file: string)
    {
        var i = 0'u64
        while i < .entries.count
        {
            if .entries[i]!.capture!.file != file
            {
                i += 1
                continue
            }
            .bytes -= .entries[i]!.bytes
            .entries.deleteAt(i)
        }
    }
}
