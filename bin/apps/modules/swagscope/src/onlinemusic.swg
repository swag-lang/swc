#global internal

using Core, Net, Pixel, Audio

struct MusicArtist
{
    name: String
}

struct MusicCredit
{
    name:       String
    artist:     MusicArtist
    joinphrase: String
}

struct OnlineMusic
{
    id:    String
    title: String
    #[Serialization.Key("first-release-date")]
    firstReleaseDate: String
    #[Serialization.Key("artist-credit")]
    artists: Array'MusicCredit
}

struct MusicSearch
{
    count: u32
    #[Serialization.Key("release-groups")]
    groups: Array'OnlineMusic
}

struct MusicSource
{
    apiHost: string = "musicbrainz.org"
    apiPort: u16    = 443
    artHost: string = "coverartarchive.org"
    artPort: u16    = 443
    secure:  bool   = true
}

struct MusicSummary
{
    title:  String
    artist: String
    date:   String
    source: String
}

struct CoverTarget
{
    host: String
    path: String
    port: u16
}

const MusicTitleTag    = "ScopeMBTitle"
const MusicArtistTag   = "ScopeMBArtist"
const MusicDateTag     = "ScopeMBDate"
const MusicSourceTag   = "ScopeMusicSource"
const MusicCachedAtTag = "ScopeMBCachedAt"

private var g_MusicLookupLock:  Swag.Mutex
private var g_LastMusicRequest: u64

struct MusicLookupCacheEntry
{
    host:      String
    port:      u16
    secure:    bool
    chosenId:  String
    album:     String
    artist:    String
    year:      String
    fetchedAt: u64
    music:     OnlineMusic
}

// Shared by preview workers in this process, protected by g_MusicLookupLock.
private var g_MusicLookupCache: Array'MusicLookupCacheEntry

struct MusicCoverCacheEntry
{
    host:      String
    port:      u16
    secure:    bool
    id:        String
    fetchedAt: u64
    bytes:     Array'u8
}

private var g_MusicCoverLock:  Swag.Mutex
private var g_MusicCoverCache: Array'MusicCoverCacheEntry

func musicSearchArtist(tags: const *SoundTags)->string
{
    return tags.albumArtist.isEmpty() ? tags.artist.toString() : tags.albumArtist.toString()
}

private func cachedMusic(tags: const *SoundTags, source: MusicSource, chosenId: string)->OnlineMusic
{
    let now = Time.monotonicMilliseconds()
    for index in reversed(g_MusicLookupCache.count)
    {
        let item = &g_MusicLookupCache[index]
        if now < item.fetchedAt or now - item.fetchedAt >= 10 * 60 * 1000
        {
            g_MusicLookupCache.removeAtOrdered(index)
            continue
        }

        if item.host != source.apiHost or
           item.port != source.apiPort or
           item.secure != source.secure or
           item.chosenId != chosenId do
            continue
        if chosenId.count or
           (item.album == tags.album and
            item.artist == musicSearchArtist(tags) and
            item.year == tags.year) do
            return item.music
    }

    return {}
}

private func rememberMusic(tags: const *SoundTags, source: MusicSource, chosenId: string, music: const *OnlineMusic)
{
    if music.id.isEmpty() do
        return
    if g_MusicLookupCache.count >= 32 do
        g_MusicLookupCache.removeAtOrdered(0)
    g_MusicLookupCache.add({host: source.apiHost, port: source.apiPort, secure: source.secure,
                            chosenId: chosenId, album: tags.album, artist: musicSearchArtist(tags), year: tags.year,
                            fetchedAt: Time.monotonicMilliseconds(), music: music[]})
}

func validMusicId(id: string)->bool
{
    if id.count != 36 do
        return false
    for byte, index in id
    {
        if index == 8 or index == 13 or index == 18 or index == 23
        {
            if byte != '-' do
                return false
        }
        elif not Latin1.isHexDigit(byte)
        {
            return false
        }
    }

    return true
}

// Escape Lucene syntax before percent-encoding the complete query.
func musicQueryLiteral(value: string)->String
{
    var result: #returntype
    for byte in value
    {
        if Utf8.indexOf("+-&|!(){}[]^\"~*?:\\/", cast(rune, byte)) != Swag.U64.Max do
            result.append('\\'u8)
        result.append(byte)
    }

    return result
}

private func musicTag(image: *Image, tag, value: string)
{
    if not value.count do
        return
    var record: ImageMetadata
    record.tag   = tag
    record.value = value
    image.metadata.add(#move record)
}

func stampMusicCache(image: *Image)
{
    musicTag(image, MusicCachedAtTag, Format.toString("%", Time.Timestamp.utcNow().ticks))
}

func localMusicSummary(tags: const *SoundTags)->MusicSummary =>
    {title: tags.album, artist: musicSearchArtist(tags), date: tags.year,
     source: tags.album.isEmpty() ? "" : "tags"}

func labelLocalMusic(image: *Image, tags: const *SoundTags)
{
    let summary = localMusicSummary(tags)
    musicTag(image, MusicTitleTag, summary.title)
    musicTag(image, MusicArtistTag, summary.artist)
    musicTag(image, MusicDateTag, summary.date)
    musicTag(image, MusicSourceTag, summary.source)
}

// Cover Art Archive redirects to Internet Archive. Never follow a URL to an unrelated host.
func coverRedirect(location: string, current: CoverTarget, source: MusicSource)->CoverTarget fail
{
    if location.count == 0 or location.count > 2048 do
        fail Errors.InvalidFormatError{}
    if location[0] == '/'
    {
        if location.count > 1 and location[1] == '/' do
            fail Errors.InvalidFormatError{}
        let absolute = Format.toString("https://local%", location)
        var target   = try Url.parseHttp(absolute)
        return {host: current.host, port: current.port, path: #move target.path}
    }

    var target     = try Url.parseHttp(location)
    let configured = String.toLower(source.artHost)
    let isArchive  = target.host == "archive.org" or Utf8.endsWith(target.host.toString(), ".archive.org")
    if target.host != configured and not isArchive do
        fail Errors.InvalidFormatError{}
    let port = target.host == configured ? source.artPort : 443'u16
    if target.hasPort and target.port != port do
        fail Errors.InvalidFormatError{}
    return {host: #move target.host, path: #move target.path, port: port}
}

impl MusicSummary
{
    func fromImage(image: const *Image)->MusicSummary
    {
        var result: #returntype
        for &record in image.metadata
        {
            let value = cast(string, record.toSlice())
            if record.isTag(cast(const [..] u8, MusicTitleTag)) do
                result.title = value
            elif record.isTag(cast(const [..] u8, MusicArtistTag)) do
                result.artist = value
            elif record.isTag(cast(const [..] u8, MusicDateTag)) do
                result.date = value
            elif record.isTag(cast(const [..] u8, MusicSourceTag)) do
                result.source = value
        }

        return result
    }

    mtd text()->String
    {
        if .title.isEmpty() do
            return {}
        let origin = .source == "tags" ? appStrings().explore_FileTags : "MusicBrainz"
        var result = Format.toString("%  ·  %", safeMediaText(.title), origin)
        let strings = appStrings()
        if not .artist.isEmpty() do
            result += Format.toString("\n%", Format.toString(strings.explore_MusicArtist, safeMediaText(.artist)))
        if not .date.isEmpty() do
            result += Format.toString("\n%", Format.toString(strings.explore_MusicDate, safeMediaText(.date)))
        return result
    }
}

impl MusicSearch
{
    // A partial result list cannot establish that an exact match is unique.
    mtd choose(tags: const *SoundTags)->u64
    {
        if .count > .groups.count do
            return Swag.U64.Max
        let album  = tags.album.toLower(.Unicode)
        let artist = String.from(musicSearchArtist(tags)).toLower(.Unicode)
        var chosen = Swag.U64.Max
        for &group, index in .groups
        {
            if group.title.toLower(.Unicode) != album do
                continue
            var artistMatches = group.artistText().toLower(.Unicode) == artist
            for credit in group.artists
            {
                if credit.name.toLower(.Unicode) == artist or credit.artist.name.toLower(.Unicode) == artist do
                    artistMatches = true
            }

            if not artistMatches do
                continue
            if not tags.year.isEmpty() and
               tags.year.length >= 4 and
               (group.firstReleaseDate.length < 4 or group.firstReleaseDate.toString()[0 until 4] != tags.year.toString()[0 until 4]) do
                continue
            if chosen != Swag.U64.Max and .groups[chosen].id != group.id do
                return Swag.U64.Max
            chosen = index
        }

        return chosen
    }
}

impl OnlineMusic
{
    mtd const artistText()->String
    {
        var result: #returntype
        for &credit in .artists
        {
            result += credit.name.isEmpty() ? credit.artist.name : credit.name
            result += credit.joinphrase
        }

        return result
    }

    // An explicit release-group ID bypasses matching; otherwise require local album and artist.
    func lookup(tags: const *SoundTags, source: MusicSource = {}, chosenId: string = "")->OnlineMusic fail
    {
        var path: String
        if chosenId.count
        {
            if not validMusicId(chosenId) do
                return {}
            path = Format.toString("/ws/2/release-group/%?inc=artist-credits&fmt=json", chosenId)
        }
        else
        {
            let artist = musicSearchArtist(tags)
            if tags.album.isEmpty() or
               artist.count == 0 or
               tags.album.length > 256 or
               artist.count > 256 do
                return {}
            let expression = Format.toString("releasegroup:\"%\" AND artist:\"%\"", musicQueryLiteral(tags.album), musicQueryLiteral(artist))
            path = Format.toString("/ws/2/release-group/?query=%&fmt=json&limit=100", Url.encodeComponent(cast(const [..] u8, expression.toString())))
        }

        // Space this process's requests below MusicBrainz's per-IP limit; other clients may
        // still share the same IP, in which case the server can refuse a request.
        if not lockMediaLookup(&g_MusicLookupLock) do
            return {}
        defer g_MusicLookupLock.unlock()
        let cached = cachedMusic(tags, source, chosenId)
        if not cached.id.isEmpty() do
            return cached
        while g_LastMusicRequest and Time.monotonicMilliseconds() - g_LastMusicRequest < 1100
        {
            if Swag.isCancelled() do
                return {}
            Threading.Thread.sleep(100'ms)
        }

        if Swag.isCancelled() do
            return {}
        g_LastMusicRequest = Time.monotonicMilliseconds()
        var options: Http.GetOptions
        options.userAgent    = "Swag Scope (https://github.com/swag-lang/swc)"
        options.timeoutMs    = 5_000
        options.maxBodyBytes = 512 * 1024
        let response = try Http.get(source.apiHost, source.apiPort, path.toString(), source.secure, options)
        if response.status != 200 do
            fail Errors.InvalidFormatError{}
        var decoder: Serialization.Decoder'Serialization.Read.Json
        if chosenId.count
        {
            let music = try decoder.readAll'OnlineMusic(response.body.toSlice())
            defer Memory.delete(music)
            if music.id.toLower(.Latin1) != String.toLower(chosenId) do
                fail Errors.InvalidFormatError{}
            rememberMusic(tags, source, chosenId, music)
            return music[]
        }

        let search = try decoder.readAll'MusicSearch(response.body.toSlice())
        defer Memory.delete(search)
        let index = search.choose(tags)
        if index == Swag.U64.Max do
            return {}
        rememberMusic(tags, source, chosenId, &search.groups[index])
        return search.groups[index]
    }

    mtd label(image: *Image, tags: const *SoundTags)
    {
        musicTag(image, MusicTitleTag, .title)
        let artist = .artistText()
        musicTag(image, MusicArtistTag, artist.isEmpty() ? musicSearchArtist(tags) : artist.toString())
        musicTag(image, MusicDateTag, .firstReleaseDate)
        musicTag(image, MusicSourceTag, "musicbrainz")
        stampMusicCache(image)
    }

    // Retrieve bounded cover bytes, following only the archive's known redirect hosts.
    mtd coverBytes(source: MusicSource = {})->Array'u8 fail
    {
        if not validMusicId(.id) do
            return {}
        if not lockMediaLookup(&g_MusicCoverLock) do
            return {}
        defer g_MusicCoverLock.unlock()
        let now = Time.monotonicMilliseconds()
        for index in reversed(g_MusicCoverCache.count)
        {
            let item = &g_MusicCoverCache[index]
            if now < item.fetchedAt or now - item.fetchedAt >= 10 * 60 * 1000
            {
                g_MusicCoverCache.removeAtOrdered(index)
                continue
            }

            if item.host == source.artHost and
               item.port == source.artPort and
               item.secure == source.secure and
               item.id == .id do
                return item.bytes
        }

        var target = CoverTarget{host: source.artHost, port: source.artPort,
                                 path: Format.toString("/release-group/%/front-250", .id)}
        var options: Http.GetOptions
        options.userAgent = "Swag Scope (https://github.com/swag-lang/swc)"
        options.timeoutMs = 5_000
        for 5
        {
            if Swag.isCancelled() do
                return {}
            var response = try Http.get(target.host, target.port, target.path, source.secure, options)
            if response.status == 200
            {
                // Small covers are shared across tracks; large images stay bounded by HTTP's limit.
                if response.body.count <= 512 * 1024
                {
                    if g_MusicCoverCache.count >= 16 do
                        g_MusicCoverCache.removeAtOrdered(0)
                    g_MusicCoverCache.add({host: source.artHost, port: source.artPort, secure: source.secure,
                                           id: .id, fetchedAt: Time.monotonicMilliseconds(), bytes: response.body})
                }

                return #move response.body
            }

            if response.status == 404 do
                return {}
            if response.status != 301 and
               response.status != 302 and
               response.status != 303 and
               response.status != 307 and
               response.status != 308 do
                fail Errors.InvalidFormatError{}
            target = try coverRedirect(response.location, target, source)
        }

        fail Errors.InvalidFormatError{}
    }
}
