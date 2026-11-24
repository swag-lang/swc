#global internal

using Core, Pixel

// Online media details are refreshed after four months.
func cachedMediaIsFresh(image: const *Image, nowTicks: u64)->bool
{
    for &record in image.metadata where record.isTag(cast(const [..] u8, MovieCachedAtTag)) or
                                        record.isTag(cast(const [..] u8, MusicCachedAtTag))
    {
        let cachedAt = catch StrConv.toU64(cast(string, record.toSlice())) { return false }
        return cachedAt != 0 and cachedAt <= nowTicks and nowTicks - cachedAt < 120 * Time.TicksPerDay
    }

    return true
}

// Persistent previews are identified by source metadata, archive member and renderer executable.
struct ThumbnailCache {}

private var g_CachePruneLock: Swag.Mutex
private var g_CachePruned:    bool

private func cacheFileName(name: string)->bool
{
    if name.count != 68 or not Utf8.endsWith(name, ".png") do
        return false
    for byte in name[0 until 64] where not Latin1.isHexDigit(byte) do
        return false
    return true
}

private func mountCacheDirectoryName(name: string)->bool
{
    const Prefix = "Swag.MountPrivacy.1."
    if not Utf8.startsWith(name, Prefix) or name.count < Prefix.count + 68 do
        return false
    for byte in name[Prefix.count until Prefix.count + 64] where not Latin1.isHexDigit(byte) do
        return false
    for byte in name[Prefix.count + 64 to] where byte != '.' and not Latin1.isDigit(byte) do
        return false
    return true
}

private func isMountCacheDirectory(entry: const *File.FileInfo)->bool =>
    entry.isDirectory() and
    not entry.attributes.has(.ReparsePoint) and
    mountCacheDirectoryName(Path.fileName(entry.fullName) orelse "")

impl ThumbnailCache
{
    private func policyDirectory(policy: const *File.MountPrivacy)->String
    {
        if policy.root.isEmpty() do
            return directory()
        return Path.combine(directory(), Format.toString("%.%.%", policy.channel, policy.instance, policy.activation))
    }

    // Remove only entries belonging to this mount. Ordinary files share the flat cache directory.
    func clearMount(channel: string) fail
    {
        let root = directory()
        if not Directory.exists(root) do
            return
        let entries = try Directory.enumerate(root, {})
        for &entry in entries where isMountCacheDirectory(entry)
        {
            let name = Path.fileName(entry.fullName) orelse ""
            if Utf8.startsWith(name, Format.toString("%.", channel))
            {
                discard try clear(entry.fullName)
                catch Directory.delete(entry.fullName)
            }
        }
    }

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
            if file.isDirectory()
            {
                if isMountCacheDirectory(file) do
                    try prune(file.fullName, nowTicks)
                continue
            }

            let name = Path.fileName(file.fullName) orelse ""
            if not cacheFileName(name) do
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

    // Remove only Scope's cache-shaped files; leave other application data in place.
    func clear(root: string, includeMounts = true)->u64 fail
    {
        if not Directory.exists(root) do
            return 0
        let files = try Directory.enumerate(root, {})
        var removed: u64
        for &file in files
        {
            if Swag.isCancelled() do
                break
            if file.isDirectory()
            {
                if includeMounts and isMountCacheDirectory(file)
                {
                    removed += try clear(file.fullName)
                    catch Directory.delete(file.fullName)
                }

                continue
            }

            if not cacheFileName(Path.fileName(file.fullName) orelse "") do
                continue
            try File.delete(file.fullName)
            removed += 1
        }

        return removed
    }

    func clearAll(root: string = "")->u64 fail
    {
        g_CachePruneLock.lock()
        defer g_CachePruneLock.unlock()
        if not root.count do
            g_CachePruned = true
        return try clear(root.count ? String.from(root) : ThumbnailCache.directory())
    }

    func key(source: string, member: string = "", executable: string = "", settings: string = "", privacy: File.MountPrivacy = {})->String fail
    {
        var policy = privacy.root.isEmpty() ? File.MountPrivacy.query(source) : privacy
        discard policy.refresh()
        if policy.privateMode do
            return ""
        let appPath  = executable.count ? executable : Env.executablePath()
        let file     = try File.info(source)
        let app      = try File.info(appPath)
        let identity = Format.toString("scope-thumbnail-10\n%\n%\n%\n%\n%\n%\n%\n%\n%\n%",
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
        return Path.combine(policyDirectory(&policy), name)
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
    func write(path: string, image: const *Image, source: string = "", privacy: File.MountPrivacy = {}) fail
    {
        if not path.count do
            return
        var policy: File.MountPrivacy
        if source.count
        {
            policy = privacy.root.isEmpty() ? File.MountPrivacy.query(source) : privacy
            discard policy.refresh()
            if policy.privateMode or not Path.equals(Path.directoryName(path) orelse "", policyDirectory(&policy)) do
                return
        }

        let instance   = policy.instance
        let activation = policy.activation
        try Directory.create(unwrap Path.directoryName(path), recurse: true)
        let temporary     = Path.combine(unwrap Path.directoryName(path), Format.toString("%.png", Guid64.random()))
        let encoded       = try image.encodeToBytes(temporary)
        var ownsTemporary = false
        defer
        {
            if ownsTemporary do
                discard catch File.delete(temporary)
        }

        var stream = try File.open(temporary, .CreateNew, .Write, .Delete)
        ownsTemporary = true
        try stream.writeAll(encoded.toSlice())
        stream.close()
        try File.move(path, temporary)
        ownsTemporary = false
        discard policy.refresh()
        if policy.privateMode or policy.instance != instance or policy.activation != activation do
            catch File.delete(path)
    }
}
