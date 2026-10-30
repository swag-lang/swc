#global internal

using Core, Pixel, Gui, Video, Audio

func albumAudio(file: string)->bool => Path.hasExtension(file, ".mp3") or Path.hasExtension(file, ".flac")

func localAlbumArtwork(file: string)->String
{
    if not albumAudio(file) do
        return {}
    let folder = Path.directoryName(file) orelse ""
    for name in ["cover.jpg", "folder.jpg", "front.jpg", "cover.png", "folder.png", "front.png"]
    {
        let image = Path.combine(folder, name)
        if File.exists(image) do
            return image
    }
    return {}
}

func onlinePreviewWanted(file: string, settings: const *ThumbnailSettings)->bool =>
    (settings.onlineMovies and Reader.canOpen(file)) or
    (settings.onlineMusic and albumAudio(file))

func onlinePreviewStamped(image: const *Image)->bool
{
    for &record in image.metadata where record.isTag(cast(const [..] u8, MovieCachedAtTag)) or
                                        record.isTag(cast(const [..] u8, MusicCachedAtTag)) do
        return true
    return false
}

// One scheduled operation produces a thumbnail or an extracted preview, never GUI resources.
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
    online:          bool     // The second pass enriches a published local preview.
    needsOnline:     bool
    settings:        String
}

impl ExplorerPreview
{
    mtd start(owner: *Wnd)
    {
        .image = {}
        .needsOnline = false
        .error.clear()
        .temporary.clear()
        let operation = me
        .submit(func|operation|()
        {
            catch operation.produce() { operation.error = Viewer.failureText(Swag.err) }
        },
                owner,
                priority: .opening ? Swag.TaskPriority.Normal : Swag.TaskPriority.Background)
    }

    private mtd produce() fail
    {
        let source = .archivePath.isEmpty() ? .path.toString() : .archivePath.toString()
        var member = String.from(.archivePath.isEmpty() ? "" : .path.toString())
        let localArtwork = .archivePath.isEmpty() ? localAlbumArtwork(.path) : String.from("")
        if not localArtwork.isEmpty()
        {
            let info = catch File.info(localArtwork)
            member += Format.toString("\n%\n%\n%", localArtwork, info.size, Hash.hash64(info.lastWriteTime))
        }
        var cache: String
        if not .opening
        {
            ThumbnailCache.pruneOnce()
            cache = catch ThumbnailCache.key(source, member, settings: .settings)
            .image = ThumbnailCache.read(cache)
            if .image.isValid() and not .online
            {
                let settings = try ThumbnailSettings.decode(.settings)
                .needsOnline = .archivePath.isEmpty() and onlinePreviewWanted(.path, &settings) and
                               not onlinePreviewStamped(&.image)
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

            if not .online
            {
                .needsOnline = .archivePath.isEmpty() and onlinePreviewWanted(file, &settings)
                if albumAudio(file)
                {
                    .image = localArtwork.isEmpty() ? Image.create(1, 1, .RGBA8) : try .service.render(localArtwork, .settings)
                    let tags = SoundTags.read(file)
                    labelLocalMusic(&.image, &tags)
                }
                else do
                    .image = try .service.render(file, .settings)
                let current = catch ThumbnailCache.key(source, member, settings: .settings)
                if not Swag.isCancelled() and cache == current do
                    catch ThumbnailCache.write(cache, &.image)
                return
            }

            var movie:     OnlineMovie
            var music:     OnlineMusic
            var musicTags: SoundTags
            let localDuration = thumbnailDuration(&.image)
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
            elif settings.onlineMusic and .archivePath.isEmpty() and albumAudio(file)
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

            if not .image.isValid()
            {
                if albumAudio(file) do
                    .image = localArtwork.isEmpty() ? Image.create(1, 1, .RGBA8) : try .service.render(localArtwork, .settings)
                else do
                    .image = try .service.render(file, .settings)
            }
            if localDuration and .image.isValid() and not thumbnailDuration(&.image)
            {
                var duration: ImageMetadata
                duration.tag   = Viewer.ThumbnailDurationTag
                duration.value = Format.toString("%", localDuration)
                .image.metadata.add(#move duration)
            }
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
