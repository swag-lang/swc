#global internal

using Core, Pixel

// Persistent previews are identified by source metadata, archive member and renderer executable.
struct ThumbnailCache {}

impl ThumbnailCache
{
    func key(source: string, member: string = "", executable: string = "", settings: string = "")->String fail
    {
        let appPath  = executable.count ? executable : Env.executablePath()
        let file     = try File.info(source)
        let app      = try File.info(appPath)
        let identity = Format.toString("scope-thumbnail-5\n%\n%\n%\n%\n%\n%\n%\n%\n%\n%",
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
        return Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "scope", "thumbnails", name)
    }

    func read(path: string)->Image
    {
        if not path.count or not File.exists(path) do
            return {}
        var result: retval
        catch { result = try Image.load(path) }
        {
            // A truncated or damaged entry is a miss and must not be retried on every visit.
            catch File.delete(path)
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
