#global internal

using Core, Pixel, Gui, Video, Audio

// A single bounded worker produces a thumbnail or an extracted preview, never GUI resources.
struct ExplorerPreview
{
    using operation: Viewer.BackgroundOperation
    path:            String
    archivePath:     String
    entry:           Viewers.Archive.ZipEntry
    service:         ThumbnailService
    image:           Image
    temporary:       String
    error:           String
    index:           u64
    generation:      u64
    opening:         bool
    bypassCache:     bool     // Renders even when a cached preview exists, and replaces it.
    settings:        String
}

impl ExplorerPreview
{
    mtd start(owner: *Wnd)
    {
        .image = {}
        .error.clear()
        .temporary.clear()
        let operation = me
        .submit(func|operation|()
        {
            catch operation.produce() { operation.error = Viewer.failureText(Swag.err) }
        },
                owner)
    }

    private mtd produce() fail
    {
        let source = .archivePath.isEmpty() ? .path.toString() : .archivePath.toString()
        let member = .archivePath.isEmpty() ? "" : .path.toString()
        var cache: String
        if not .opening
        {
            ThumbnailCache.pruneOnce()
            cache = catch ThumbnailCache.key(source, member, settings: .settings)
            if not .bypassCache
            {
                .image = ThumbnailCache.read(cache)
                if .image.isValid() do
                    return
            }
        }

        var file = String.from(.path)
        if not .archivePath.isEmpty()
        {
            var extension = String.from(Path.extension(.path) orelse ".bin")
            if extension.length > 24 do
                extension = ".bin"
            var name = Format.toString("scope-preview-%", Guid64.random())
            name += extension
            if not Path.isValidFileName(name) do
                fail Errors.InvalidFormatError{}
            .temporary = Path.combine(Env.getSpecialDirectory(.Temp), name)
            try Viewers.Archive.Zip.extractEntry(.archivePath, &.entry, .temporary)
            file = .temporary
        }

        defer
        {
            if not .opening and not .temporary.isEmpty()
            {
                catch File.delete(.temporary)
                .temporary.clear()
            }
        }

        if not .opening
        {
            var settings = try ThumbnailSettings.decode(.settings)
            if not settings.musicId.isEmpty()
            {
                let info = try File.info(file)
                if not settings.choiceMatches(&info)
                {
                    settings.musicId.clear()
                }
            }

            var movie:     OnlineMovie
            var music:     OnlineMusic
            var musicTags: SoundTags
            var providerFailed    = false
            var providerAttempted = false
            var musicAttempted    = false
            if settings.onlineMovies and .archivePath.isEmpty() and Reader.canOpen(file)
            {
                providerAttempted = true
                catch
                {
                    movie = try OnlineMovie.lookup(file, language: settings.movieLanguage)
                    if movie.found() and not Swag.isCancelled()
                    {
                        let poster = try movie.posterBytes()
                        if not poster.isEmpty() do
                            .image = try .renderOnlineImage(poster.toSlice())
                    }
                }
                {
                    providerFailed = true
                }
            }
            elif settings.onlineMusic and
                 .archivePath.isEmpty() and
                 (Path.hasExtension(file, ".mp3") or Path.hasExtension(file, ".flac"))
            {
                musicTags = SoundTags.read(file)
                if not settings.musicId.isEmpty() or (not musicTags.album.isEmpty() and musicSearchArtist(&musicTags).count > 0)
                {
                    providerAttempted = true
                    musicAttempted    = true
                    catch
                    {
                        music = try OnlineMusic.lookup(&musicTags, chosenId: settings.musicId)
                        if not music.id.isEmpty() and not Swag.isCancelled()
                        {
                            let cover = try music.coverBytes()
                            if not cover.isEmpty() do
                                .image = try .renderOnlineImage(cover.toSlice())
                        }
                    }
                    {
                        providerFailed = true
                        if not settings.musicId.isEmpty() do
                            .error = appStrings().explore_ChosenMusicFailed
                    }
                }
            }

            if not .image.isValid() do
                .image = try .service.render(file, .settings)
            if movie.found() and .image.isValid() do
                movie.label(&.image)
            elif not music.id.isEmpty() and .image.isValid() do
                music.label(&.image, &musicTags)
            elif musicAttempted and not providerFailed and .image.isValid() do
                stampMusicCache(&.image)
            elif providerAttempted and not providerFailed and .image.isValid() do
                stampMovieCache(&.image)

            // A file replaced during rendering must not publish an image under its old identity.
            let current = catch ThumbnailCache.key(source, member, settings: .settings)
            if not providerFailed and not Swag.isCancelled() and cache == current do
                catch ThumbnailCache.write(cache, &.image)
        }
    }

    // Decode remote bytes in the same isolated process as local previews.
    private mtd renderOnlineImage(bytes: const [..] u8)->Image fail
    {
        var extension = ".jpg"
        if bytes.count >= 8 and
           bytes[0] == 0x89 and
           bytes[1] == 'P' and
           bytes[2] == 'N' and
           bytes[3] == 'G' do
            extension = ".png"
        elif bytes.count >= 12 and
             cast(string, bytes[0 until 4]) == "RIFF" and
             cast(string, bytes[8 until 12]) == "WEBP" do
            extension = ".webp"
        var name = Format.toString("scope-artwork-%", Guid64.random())
        name += extension
        let file = Path.combine(Env.getSpecialDirectory(.Temp), name)
        defer catch File.delete(file)
        discard try File.writeAllBytes(file, bytes)
        return try .service.render(file)
    }

    mtd opDrop()
    {
        .wait()
        if not .temporary.isEmpty() do
            catch File.delete(.temporary)
    }
}
