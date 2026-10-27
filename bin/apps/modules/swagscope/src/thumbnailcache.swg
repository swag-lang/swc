#global internal

using Core, Pixel

// Online media details are refreshed after four months.
func cachedMediaIsFresh(image: const *Image, nowTicks: u64)->bool
{
    for &record in image.metadata where record.isTag(cast(const [..] u8, MovieCachedAtTag)) or
                                        record.isTag(cast(const [..] u8, MusicCachedAtTag))
    {
        let cachedAt = catch StrConv.toU64(cast(string, record.toSlice()))
        return cachedAt != 0 and cachedAt <= nowTicks and nowTicks - cachedAt < 120 * Time.TicksPerDay
    }

    return true
}

// Persistent previews are identified by source metadata, archive member and renderer executable.
struct ThumbnailCache {}

private var g_CachePruneLock: Swag.Mutex
private var g_CachePruned:    bool

impl ThumbnailCache
{
    func directory()->String => Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "scope", "thumbnails")

    // Remove abandoned cache entries when the application is used again. Never follow names
    // outside the cache's SHA-256 filename format or remove files modified in the last 120 days.
    func prune(root: string, nowTicks: u64) fail
    {
        if not Directory.exists(root) do
            return
        let files = try Directory.enumerate(root, {})
        for &file in files
        {
            if file.isDirectory() do
                continue
            let name = Path.fileName(file.fullName) orelse ""
            if name.count != 68 or not Utf8.endsWith(name, ".png") do
                continue
            var valid = true
            for byte in name[0 until 64] where not Latin1.isHexDigit(byte) do
                valid = false
            if not valid do
                continue
            let modified = Time.Timestamp.fromDateTime(file.lastWriteTime).ticks
            if modified and modified <= nowTicks and nowTicks - modified >= 120 * Time.TicksPerDay do
                catch File.delete(file.fullName)
        }
    }

    // One worker cleans in the background; other workers do not wait for a large cache scan.
    func pruneOnce()
    {
        if not g_CachePruneLock.tryLock() do
            return
        defer g_CachePruneLock.unlock()
        if g_CachePruned do
            return
        g_CachePruned = true
        catch ThumbnailCache.prune(ThumbnailCache.directory(), Time.Timestamp.utcNow().ticks)
    }

    func key(source: string, member: string = "", executable: string = "", settings: string = "")->String fail
    {
        let appPath  = executable.count ? executable : Env.executablePath()
        let file     = try File.info(source)
        let app      = try File.info(appPath)
        let identity = Format.toString("scope-thumbnail-6\n%\n%\n%\n%\n%\n%\n%\n%\n%\n%",
                                       try Path.absolute(source),
                                       member,
                                       file.size,
                                       Hash.hash64(file.lastWriteTime),
                                       Hash.hash64(file.creationTime),
                                       appPath,
                                       app.size,
                                       Hash.hash64(app.lastWriteTime),
                                       Hash.hash64(app.creationTime),
                                       settings)
        let digest = Hash.Sha256.compute(cast(const [..] u8, identity.toString()))
        var name: String
        for word in digest do
            name += Format.toString("%{X08}", word)
        name += ".png"
        return Path.combine(ThumbnailCache.directory(), name)
    }

    func read(path: string)->Image
    {
        if not path.count or not File.exists(path) do
            return {}
        var result: #returntype
        catch { result = try Image.load(path) }
        {
            // A truncated or damaged entry is a miss and must not be retried on every visit.
            catch File.delete(path)
        }

        if result.isValid() and not cachedMediaIsFresh(&result, Time.Timestamp.utcNow().ticks)
        {
            catch File.delete(path)
            return {}
        }

        return result
    }

    // Publish only complete PNGs. A competing process may already have published the same key.
    func write(path: string, image: const *Image) fail
    {
        if not path.count do
            return
        try Directory.create(unwrap Path.directoryName(path), recurse: true)
        let temporary = Path.combine(unwrap Path.directoryName(path), Format.toString("%.png", Guid64.random()))
        defer catch File.delete(temporary)
        try image.save(temporary)
        try File.move(path, temporary)
    }
}
