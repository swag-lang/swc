#global internal

using Core, Net, Pixel, Video

struct MovieQuery
{
    title: String
    year:  String
}

struct WikiImage
{
    source: String
    width:  u32
    height: u32
}

struct WikiPageProperties
{
    #[Serialization.Key("wikibase_item")]
    id: String
    disambiguation: String
}

struct WikiPage
{
    title:       String
    description: String
    extract:     String
    thumbnail:   WikiImage
    pageprops:   WikiPageProperties
}

struct WikiPageList
{
    pages: Array'WikiPage
}

struct MovieSearch
{
    query: WikiPageList
}

struct WikiValue
{
    value: String
}

struct WikiMovieRow
{
    directorLabel: WikiValue
    castLabel:     WikiValue
    score:         WikiValue
    scoreDate:     WikiValue
}

struct WikiRows
{
    bindings: Array'WikiMovieRow
}

struct WikiDetails
{
    results: WikiRows
}

// One film of the Apple iTunes Search API, as much of it as Scope reads.
struct AppleMovie
{
    trackName:        String
    releaseDate:      String
    artworkUrl100:    String
    longDescription:  String
    primaryGenreName: String
}

struct AppleSearch
{
    results: Array'AppleMovie
}

struct MovieSource
{
    // Empty wikiHost selects the Wikipedia language; tests can supply a local service.
    wikiHost:  string = ""
    appleHost: string = "itunes.apple.com"
    dataHost:  string = "query.wikidata.org"
    imageHost: string = ""
    port:      u16    = 443
    secure:    bool   = true
}

struct OnlineMovie
{
    id:          String
    title:       String
    overview:    String
    releaseDate: String
    director:    String
    actors:      String
    imdbRating:  String
    ratingDate:  String
    posterUrl:   String
    articleUrl:  String
    sources:     String     // Who said what is shown, for the attribution line: Apple, Wikipedia, Wikidata.
}

private var g_MovieLookupLock: Swag.Mutex

// When the Apple catalogue was last asked, in ticks. Its rate limit is not documented, so two
// questions stand a little apart.
private var g_AppleLastRequest: u64
const AppleRequestSpacing = 1500'u64     // Milliseconds between two questions to the Apple catalogue.

// Waiting workers can retire promptly when a navigation change cancels their task.
func lockMediaLookup(mutex: *Swag.Mutex)->bool
{
    while not mutex.tryLock()
    {
        if Swag.isCancelled() do
            return false
        Threading.Thread.sleep(50'ms)
    }

    if Swag.isCancelled()
    {
        mutex.unlock()
        return false
    }

    return true
}

const MovieTitleTag      = "ScopeWikiTitle"
const MovieImdbRatingTag = "ScopeWikiIMDbRating"
const MovieDirectorTag   = "ScopeWikiDirector"
const MovieCastTag       = "ScopeWikiCast"
const MovieDateTag       = "ScopeWikiDate"
const MovieOverviewTag   = "ScopeWikiOverview"
const MovieSourceTag     = "ScopeWikiSource"
const MovieCachedAtTag   = "ScopeWikiCachedAt"
const MovieSourcesTag    = "ScopeMovieSources"

struct MovieSummary
{
    title:      String
    imdbRating: String
    director:   String
    actors:     String
    date:       String
    overview:   String
    source:     String
    sources:    String
}

// Provider text is data, not Pixel rich-text markup or additional layout controls.
func safeMediaText(value: string)->String
{
    var result: #returntype
    for byte in value
    {
        if byte == '<' do
            result += "‹"
        elif byte < ' ' or byte == 0x7F do
            result.append(' 'u8)
        else do
            result.append(byte)
    }

    return result
}

impl MovieSummary
{
    func fromImage(image: const *Image)->MovieSummary
    {
        var result: #returntype
        for &record in image.metadata
        {
            let value = cast(string, record.toSlice())
            if record.isTag(cast(const [..] u8, MovieTitleTag)) do
                result.title = value
            elif record.isTag(cast(const [..] u8, MovieImdbRatingTag)) do
                result.imdbRating = value
            elif record.isTag(cast(const [..] u8, MovieDirectorTag)) do
                result.director = value
            elif record.isTag(cast(const [..] u8, MovieCastTag)) do
                result.actors = value
            elif record.isTag(cast(const [..] u8, MovieDateTag)) do
                result.date = value
            elif record.isTag(cast(const [..] u8, MovieOverviewTag)) do
                result.overview = value
            elif record.isTag(cast(const [..] u8, MovieSourceTag)) do
                result.source = value
            elif record.isTag(cast(const [..] u8, MovieSourcesTag)) do
                result.sources = value
        }

        return result
    }

    mtd text()->String
    {
        if .title.isEmpty() do
            return {}
        var result  = safeMediaText(.title)
        let strings = appStrings()
        if not .imdbRating.isEmpty() do
            result += Format.toString("  ·  %", Format.toString(strings.explore_ImdbRating, safeMediaText(.imdbRating)))
        if not .date.isEmpty() do
            result += Format.toString("  ·  %", Format.toString(strings.explore_MovieDate, safeMediaText(.date)))
        if not .director.isEmpty() do
            result += Format.toString("\n%", Format.toString(strings.explore_MovieDirector, safeMediaText(.director)))
        if not .actors.isEmpty() do
            result += Format.toString("\n%", Format.toString(strings.explore_MovieCast, safeMediaText(.actors)))
        if not .overview.isEmpty() do
            result += Format.toString("\n%", Format.toString(strings.explore_MovieOverview, safeMediaText(.overview)))
        if not .source.isEmpty() do
            result += Format.toString("\nWikipedia / Wikidata: %", safeMediaText(.source))
        return result
    }
}

private func addMovieTag(image: *Image, tag, value: string)
{
    if not value.count do
        return
    var record: ImageMetadata
    record.tag   = tag
    record.value = value
    image.metadata.add(#move record)
}

func stampMovieCache(image: *Image)
{
    addMovieTag(image, MovieCachedAtTag, Format.toString("%", Time.Timestamp.utcNow().ticks))
}

func validWikiId(id: string)->bool
{
    if id.count < 2 or id.count > 16 or id[0] != 'Q' do
        return false
    for c in id[1 to] where not Latin1.isDigit(c) do
        return false
    return id[1] != '0'
}

impl MovieQuery
{
    func fromFile(path: string)->MovieQuery
    {
        let stem = Path.fileNameWithoutExtension(path) orelse ""
        var result: #returntype
        var end  = stem.count
        if stem.count >= 6
        {
            for index in 0 until stem.count - 5
            {
                if stem[index] != '(' or stem[index + 5] != ')' do
                    continue
                var valid = true
                for at in index + 1 until index + 5 where not Latin1.isDigit(stem[at]) do
                    valid = false
                if valid
                {
                    result.year = stem[index + 1 until index + 5]
                    end         = index
                    break
                }
            }
        }

        for byte in stem[0 until end] do
            result.title.append(byte == '.' or byte == '_' ? ' 'u8 : byte)
        result.title = Latin1.trim(result.title.toString())
        return result
    }

    // Requires films of the catalogue named exactly the title, of its year when the name says one,
    // and all of one year; a title several films share without a year says which is ambiguous.
    mtd const chooseApple(search: const *AppleSearch)->u64
    {
        let wanted = .title.toLower(.Unicode)
        var chosen = Swag.U64.Max
        var year: String
        for &film, index in search.results
        {
            let title = film.trackName.toLower(.Unicode)
            if title != wanted do
                continue
            let filmYear = film.releaseDate.length >= 4 ? String.from(film.releaseDate.toString()[0 until 4]) : String.from("")
            if not .year.isEmpty() and filmYear != .year do
                continue
            if chosen != Swag.U64.Max and filmYear != year do
                return Swag.U64.Max
            if chosen == Swag.U64.Max
            {
                chosen = index
                year   = filmYear
            }
        }

        return chosen
    }

    // Require one exact article title, optionally followed by a film disambiguator.
    mtd const choose(search: const *MovieSearch)->u64
    {
        let wanted = .title.toLower(.Unicode)
        let prefix = Format.toString("% (", wanted)
        var chosen = Swag.U64.Max
        for &page, index in search.query.pages
        {
            if not validWikiId(page.pageprops.id) do
                continue
            let description = page.description.toLower(.Unicode)
            if not Utf8.contains(description.toString(), "film") do
                continue
            let title = page.title.toLower(.Unicode)
            if title != wanted and not Utf8.startsWith(title.toString(), prefix.toString()) do
                continue
            if not .year.isEmpty() and not Utf8.contains(description.toString(), .year.toString()) do
                continue
            if chosen != Swag.U64.Max and search.query.pages[chosen].pageprops.id != page.pageprops.id do
                return Swag.U64.Max
            chosen = index
        }

        return chosen
    }
}

impl OnlineMovie
{
    mtd label(image: *Image)
    {
        addMovieTag(image, MovieTitleTag, .title)
        addMovieTag(image, MovieDateTag, .releaseDate)
        addMovieTag(image, MovieOverviewTag, .overview)
        addMovieTag(image, MovieImdbRatingTag, .imdbRating)
        addMovieTag(image, MovieDirectorTag, .director)
        addMovieTag(image, MovieCastTag, .actors)
        addMovieTag(image, MovieSourceTag, .articleUrl)
        addMovieTag(image, MovieSourcesTag, .sources)
        stampMovieCache(image)
    }

    // Reports whether anything was found for the film: an article, or a poster from the catalogue.
    mtd const found()->bool => not .id.isEmpty() or not .posterUrl.isEmpty()

    // Wikipedia provides the article and illustration; Wikidata supplies structured credits.
    func lookup(path: string, source: MovieSource = {}, language: string = "en")->OnlineMovie fail
    {
        let query = MovieQuery.fromFile(path)
        if query.title.isEmpty() or query.title.length > 256 do
            return {}
        if not lockMediaLookup(&g_MovieLookupLock) do
            return {}
        defer g_MovieLookupLock.unlock()
        var movie = try lookupArticle(query, source, language)
        if movie.id.isEmpty() and language == "fr" do
            movie = try lookupArticle(query, source, "en")
        if not movie.id.isEmpty() do
            movie.sources = String.from("Wikipedia · Wikidata")

        // The Apple catalogue holds the real poster and the synopsis of a film; Wikipedia and
        // Wikidata keep its direction, its cast and its rating.
        catch movie.lookupApple(query, source, language)
        return movie
    }

    // Asks the Apple catalogue for the film `query` names, and takes its poster, its synopsis and
    // its year when exactly one film answers to its title, and to its year when the name says it.
    private mtd lookupApple(query: MovieQuery, source: MovieSource, language: string) fail
    {
        if not source.appleHost.count do
            return

        // Questions stand apart, and a cancelled preview stops waiting.
        while true
        {
            let now     = Time.Timestamp.utcNow().ticks
            let elapsed = (now - g_AppleLastRequest) / Time.TicksPerMillisecond
            if g_AppleLastRequest == 0 or now < g_AppleLastRequest or elapsed >= AppleRequestSpacing do
                break
            if Swag.isCancelled() do
                return
            Threading.Thread.sleep(50'ms)
        }

        g_AppleLastRequest = Time.Timestamp.utcNow().ticks
        let country = language == "fr" ? "FR" : "US"
        let path    = Format.toString("/search?term=%&entity=movie&limit=10&country=%", Url.encodeComponent(cast(const [..] u8, query.title.toString())), country)
        var options: Http.GetOptions
        options.userAgent = "SwagScope/1.0 (https://github.com/swag-lang/swc)"
        options.timeoutMs = 5_000
        let response = try Http.get(source.appleHost, source.port, path.toString(), source.secure, options)
        if response.status != 200 do
            return
        var decoder: Serialization.Decoder'Serialization.Read.Json
        let search = try decoder.readAll'AppleSearch(response.body.toSlice())
        defer Memory.delete(search)
        let index = query.chooseApple(search)
        if index == Swag.U64.Max do
            return

        let film = &search.results[index]
        if .title.isEmpty() do
            .title = query.title
        if .releaseDate.isEmpty() and film.releaseDate.length >= 4 do
            .releaseDate = film.releaseDate.toString()[0 until 4]
        if not film.longDescription.isEmpty() do
            .overview = film.longDescription
        if not film.artworkUrl100.isEmpty()
        {
            // The artwork address names its size; a poster asks for a larger one.
            var url = film.artworkUrl100.toString()
            let at  = Utf8.indexOf(url, "100x100")
            if at != Swag.U64.Max do
                .posterUrl = Format.toString("%600x900%", url[0 until at], url[at + 7 to])
            else do
                .posterUrl = film.artworkUrl100
        }

        .sources = .sources.isEmpty() ? String.from("Apple") : Format.toString("Apple · %", .sources)
    }

    private func lookupArticle(query: MovieQuery, source: MovieSource, language: string)->OnlineMovie fail
    {
        let wikiHost   = source.wikiHost.count ? source.wikiHost : (language == "fr" ? "fr.wikipedia.org" : "en.wikipedia.org")
        let term       = Format.toString("% film", query.title)
        let searchPath = Format.toString("/w/api.php?action=query&generator=search&gsrsearch=%&gsrlimit=10&prop=pageimages%%7Cdescription%%7Cextracts%%7Cpageprops&piprop=thumbnail&pithumbsize=350&pilicense=any&exintro=1&explaintext=1&exchars=400&format=json&formatversion=2", Url.encodeComponent(cast(const [..] u8, term.toString())))
        var options: Http.GetOptions
        options.userAgent = "SwagScope/1.0 (https://github.com/swag-lang/swc)"
        options.timeoutMs = 5_000
        let response = try Http.get(wikiHost, source.port, searchPath.toString(), source.secure, options)
        if response.status != 200 do
            fail Errors.InvalidFormatError{}
        var decoder: Serialization.Decoder'Serialization.Read.Json
        let search = try decoder.readAll'MovieSearch(response.body.toSlice())
        defer Memory.delete(search)
        let index = query.choose(search)
        if index == Swag.U64.Max do
            return {}
        let page = &search.query.pages[index]
        var movie: OnlineMovie
        movie.id          = page.pageprops.id
        movie.title       = query.title
        movie.releaseDate = query.year
        movie.overview    = page.extract
        movie.posterUrl   = page.thumbnail.source
        movie.articleUrl  = Format.toString("https://%/wiki/%", wikiHost, Url.encodeComponent(cast(const [..] u8, page.title.toString())))

        // Missing structured data must not discard an otherwise useful article or illustration.
        catch movie.loadDetails(source, options, language)

        // The French article often has a landscape logo while the English one has the poster.
        if language == "fr" and (page.thumbnail.height <= page.thumbnail.width or page.thumbnail.source.isEmpty()) do
            catch movie.loadEnglishPoster(query, source, searchPath, options)
        return movie
    }

    private mtd loadEnglishPoster(query: MovieQuery, source: MovieSource, path: string, options: Http.GetOptions) fail
    {
        let host     = source.wikiHost.count ? source.wikiHost : "en.wikipedia.org"
        let response = try Http.get(host, source.port, path, source.secure, options)
        if response.status != 200 do
            return
        var decoder: Serialization.Decoder'Serialization.Read.Json
        let search = try decoder.readAll'MovieSearch(response.body.toSlice())
        defer Memory.delete(search)
        let index = query.choose(search)
        if index == Swag.U64.Max do
            return
        let page = &search.query.pages[index]
        if page.pageprops.id == .id and page.thumbnail.height > page.thumbnail.width do
            .posterUrl = page.thumbnail.source
    }

    private mtd loadDetails(source: MovieSource, options: Http.GetOptions, language: string) fail
    {
        if not validWikiId(.id) do
            return
        let lang     = language == "fr" ? "fr,en" : "en"
        let sparql   = Format.toString("""SELECT ?directorLabel ?castLabel ?score ?scoreDate WHERE { OPTIONAL { wd:% wdt:P57 ?director } OPTIONAL { wd:% wdt:P161 ?cast } OPTIONAL { wd:% p:P444 ?s . ?s ps:P444 ?score; pq:P447 wd:Q37312 . OPTIONAL { ?s pq:P585 ?scoreDate } } SERVICE wikibase:label { bd:serviceParam wikibase:language "%" . } } LIMIT 20""", .id, .id, .id, lang)
        let request  = Format.toString("/sparql?query=%&format=json", Url.encodeComponent(cast(const [..] u8, sparql.toString())))
        let response = try Http.get(source.dataHost, source.port, request.toString(), source.secure, options)
        if response.status != 200 do
            fail Errors.InvalidFormatError{}
        var decoder: Serialization.Decoder'Serialization.Read.Json
        let details = try decoder.readAll'WikiDetails(response.body.toSlice())
        defer Memory.delete(details)
        for &row in details.results.bindings
        {
            if .director.isEmpty() do
                .director = row.directorLabel.value
            if .imdbRating.isEmpty() and not row.score.value.isEmpty()
            {
                .imdbRating = row.score.value
                if row.scoreDate.value.length >= 10 do
                    .imdbRating += Format.toString(" (%)", row.scoreDate.value.toString()[0 until 10])
            }

            if not row.castLabel.value.isEmpty() and not Utf8.contains(.actors.toString(), row.castLabel.value.toString())
            {
                if not .actors.isEmpty() do
                    .actors += ", "
                .actors += row.castLabel.value
            }
        }
    }

    // Restrict redirects and the final request to the image hosts of Wikimedia and Apple.
    mtd posterBytes(source: MovieSource = {})->Array'u8 fail
    {
        if .posterUrl.isEmpty() do
            return {}
        let target = try Url.parseHttp(.posterUrl)
        if source.imageHost.count
        {
            if target.host != source.imageHost or target.port != source.port do
                fail Errors.InvalidFormatError{}
        }
        elif not target.secure or
             target.port != 443 or
             (target.host != "upload.wikimedia.org" and target.host != "thumb.wikimedia.org" and not Utf8.endsWith(target.host, ".mzstatic.com"))
        {
            fail Errors.InvalidFormatError{}
        }

        var options: Http.GetOptions
        options.userAgent = "SwagScope/1.0 (https://github.com/swag-lang/swc)"
        options.timeoutMs = 5_000
        var response = try Http.get(target.host, target.port, target.path, target.secure, options)
        if response.status != 200 do
            fail Errors.InvalidFormatError{}
        return #move response.body
    }
}
