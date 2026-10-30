#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Net, Pixel

struct MovieServerFixture
{
    late listener: *TcpListener
    port:          u16
    poster:        Array'u8
    requests:      [3] String
    appleMiss:     bool
    tmdbHit:       bool
    tmdbMiss:      bool
}

func writeMovieBytes(stream: *TcpStream, bytes: const [..] u8)
{
    var written = 0'u64
    while written < bytes.count
    {
        let count = expect stream.write(bytes[written to])
        if count == 0 do
            return
        written += count
    }
}

func serveMovies(thread: const *Threading.Thread)
{
    let fixture = cast(*MovieServerFixture, unwrap thread.userParam)
    for index in (fixture.appleMiss or fixture.tmdbMiss ? 3 : 2)
    {
        var stream = expect fixture.listener.accept()
        var bytes: [1024] u8
        while Utf8.indexOf(fixture.requests[index].toString(), "\r\n\r\n") == Swag.U64.Max
        {
            let count = expect stream.read(bytes)
            if count == 0 do
                return
            fixture.requests[index] += cast(string, bytes[0 until count])
        }

        var body: Array'u8
        if fixture.tmdbMiss and index == 0
        {
            body.add(cast(const [..] u8, """{"results":[]}"""))
        }
        elif fixture.tmdbHit and index == 0
        {
            let json = """{"results":[{"id":78,"title":"Blade Runner","original_title":"Blade Runner","release_date":"1982-06-25","overview":"A detective hunts replicants.","poster_path":"/blade-runner.jpg","vote_average":8.1,"vote_count":1000},{"id":335984,"title":"Blade Runner 2049","release_date":"2017-10-06"}]}"""
            body.add(cast(const [..] u8, json))
        }
        elif fixture.appleMiss and index == 0
        {
            body.add(cast(const [..] u8, """{"resultCount":0,"results":[]}"""))
        }
        elif fixture.appleMiss and index == 1
        {
            let json = Format.toString("""{"query":{"pages":[{"title":"Blade Runner (film)","description":"film de Ridley Scott sorti en 1982","extract":"A futuristic detective story.","pageprops":{"wikibase_item":"Q184843"},"thumbnail":{"source":"http://127.0.0.1:%/poster.png","width":100,"height":150}}]}}""", fixture.port)
            body.add(cast(const [..] u8, json.toString()))
        }
        elif fixture.appleMiss and index == 2
        {
            let json = """{"results":{"bindings":[{"directorLabel":{"value":"Ridley Scott"},"castLabel":{"value":"Harrison Ford"},"score":{"value":"8.1/10"},"scoreDate":{"value":"2026-02-25T00:00:00Z"}}]}}"""
            body.add(cast(const [..] u8, json))
        }
        elif index == 0 or (fixture.tmdbMiss and index == 1)
        {
            // A trimmed catalogue response: one exact match and one different sequel.
            let json = Format.toString("""{"resultCount":2,"results":[{"trackName":"Blade Runner","trackViewUrl":"https://tv.apple.com/movie/blade-runner","releaseDate":"1982-06-25T07:00:00Z","artworkUrl100":"http://127.0.0.1:%/poster/100x100bb.jpg","longDescription":"In a dark future, a blade runner hunts replicants.","primaryGenreName":"Sci-Fi & Fantasy"},{"trackName":"Blade Runner 2049","releaseDate":"2017-10-06T07:00:00Z","artworkUrl100":"http://127.0.0.1:%/other/100x100bb.jpg"}]}""", fixture.port, fixture.port)
            body.add(cast(const [..] u8, json.toString()))
        }
        else
        {
            body.add(fixture.poster.toSlice())
        }

        let header = Format.toString("HTTP/1.1 200 OK\r\nContent-Length: %\r\nConnection: close\r\n\r\n", body.count)
        writeMovieBytes(&stream, cast(const [..] u8, header.toString()))
        writeMovieBytes(&stream, body.toSlice())
    }
}

// A TMDB miss still reaches the Apple catalogue before Wikipedia.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MovieServerFixture{listener: &listener, port: endpoint.port, tmdbMiss: true}
    var image    = Image.create(8, 8, .RGB8)
    let encoded  = expect image.encode("poster.png")
    fixture.poster.add(unwrap encoded.toSlice())
    var thread: Threading.Thread
    expect thread.init(&serveMovies, &fixture)
    expect thread.start()
    let host = MovieSource{tmdbHost: "127.0.0.1", tmdbToken: "fixture-token-abcdefghijkl", appleHost: "127.0.0.1",
                           imageHost: "127.0.0.1", port: endpoint.port, secure: false, useLocalCredentials: false}
    let movie = expect OnlineMovie.lookup("Blade.Runner (1982).mkv", host, "fr")
    discard expect movie.posterBytes(host)
    thread.wait()
    Swag.assert(movie.id == "apple" and movie.sources == "Apple")
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/3/search/movie?"))
    Swag.assert(Utf8.contains(fixture.requests[1].toString(), "/search?term=Blade%20Runner"))
    Swag.assert(Utf8.contains(fixture.requests[2].toString(), "/poster/600x900bb.jpg"))
}

// A v3 key works when no token is configured; neither credential is embedded in the app.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MovieServerFixture{listener: &listener, port: endpoint.port, tmdbHit: true}
    var image    = Image.create(8, 8, .RGB8)
    let encoded  = expect image.encode("poster.png")
    fixture.poster.add(unwrap encoded.toSlice())
    var thread: Threading.Thread
    expect thread.init(&serveMovies, &fixture)
    expect thread.start()
    let host = MovieSource{tmdbHost: "127.0.0.1", tmdbKey: "0123456789abcdef0123456789abcdef",
                           imageHost: "127.0.0.1", port: endpoint.port, secure: false, useLocalCredentials: false}
    let movie = expect OnlineMovie.lookup("Blade.Runner (1982).mkv", host)
    discard expect movie.posterBytes(host)
    thread.wait()
    Swag.assert(movie.id == "tmdb:78")
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "api_key=0123456789abcdef0123456789abcdef"))
    Swag.assert(not Utf8.contains(fixture.requests[0].toString(), "Authorization: Bearer"))
}

#test
{
    let text = safeMediaText("Title <url>https://example.com</url>\r\nNext")
    Swag.assert(not Utf8.contains(text.toString(), "<url>"))
    Swag.assert(not Utf8.contains(text.toString(), "\n"))
    Swag.assert(validWikiId("Q184843") and not validWikiId("Q1/../other"))
    let query = MovieQuery.fromFile("D:/Films/Blade.Runner (1982).mkv")
    Swag.assert(query.title == "Blade Runner" and query.year == "1982")
    let json   = """{"query":{"pages":[{"title":"Blade Runner","description":"1982 film","pageprops":{"wikibase_item":"Q1"}},{"title":"Blade Runner (film)","description":"1982 film","pageprops":{"wikibase_item":"Q2"}}]}}"""
    var decoder: Serialization.Decoder'Serialization.Read.Json
    let search = expect decoder.readAll'MovieSearch(cast(const [..] u8, json))
    defer Memory.delete(search)
    Swag.assert(query.choose(search) == Swag.U64.Max)
}

// Search, credits and artwork are exercised without credentials against a local service.
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MovieServerFixture{listener: &listener, port: endpoint.port}
    var image    = Image.create(8, 8, .RGB8)
    let encoded  = expect image.encode("poster.png")
    fixture.poster.add(unwrap encoded.toSlice())
    var thread: Threading.Thread
    expect thread.init(&serveMovies, &fixture)
    expect thread.start()
    let host = MovieSource{wikiHost: "127.0.0.1", dataHost: "127.0.0.1", appleHost: "127.0.0.1", tmdbHost: "",
                           imageHost: "127.0.0.1", port: endpoint.port, secure: false}
    var movie       = expect OnlineMovie.lookup("Blade.Runner (1982).mkv", host, "fr")
    let posterBytes = expect movie.posterBytes(host)
    var poster      = expect Image.decode("poster.png", posterBytes.toSlice())
    thread.wait()
    Swag.assert(movie.id == "apple" and poster.isValid())
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/search?term=Blade%20Runner&entity=movie"))
    Swag.assert(Utf8.contains(fixture.requests[1].toString(), "/poster/600x900bb.jpg"))
    Swag.assert(movie.sources == "Apple" and movie.articleUrl == "https://tv.apple.com/movie/blade-runner")
    movie.label(&poster)
    let summary = MovieSummary.fromImage(&poster)
    Swag.assert(summary.title == "Blade Runner" and summary.director.isEmpty())
    Swag.assert(summary.overview == "In a dark future, a blade runner hunts replicants.")
    Swag.assert(summary.sources == "Apple" and Utf8.contains(summary.text().toString(), "Apple: https://tv.apple.com"))

    // Only one film of the catalogue answers to a title and a year; a title alone that several
    // films share is not taken.
    let json   = """{"results":[{"trackName":"Dune","releaseDate":"1984-12-14T08:00:00Z"},{"trackName":"Dune","releaseDate":"2021-10-22T07:00:00Z"}]}"""
    var decoder: Serialization.Decoder'Serialization.Read.Json
    let search = expect decoder.readAll'AppleSearch(cast(const [..] u8, json))
    defer Memory.delete(search)
    let dated   = MovieQuery{title: "Dune", year: "2021"}
    let undated = MovieQuery{title: "Dune"}
    let other   = MovieQuery{title: "Arrival"}
    Swag.assert(dated.chooseApple(search) == 1)
    Swag.assert(undated.chooseApple(search) == Swag.U64.Max)
    Swag.assert(other.chooseApple(search) == Swag.U64.Max)
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MovieServerFixture{listener: &listener, port: endpoint.port, appleMiss: true}
    var thread: Threading.Thread
    expect thread.init(&serveMovies, &fixture)
    expect thread.start()
    let host = MovieSource{wikiHost: "127.0.0.1", dataHost: "127.0.0.1", appleHost: "127.0.0.1", tmdbHost: "",
                           port: endpoint.port, secure: false}
    let movie = expect OnlineMovie.lookup("Blade.Runner (1982).mkv", host, "fr")
    thread.wait()
    Swag.assert(movie.id == "Q184843" and movie.sources == "Wikipedia · Wikidata")
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/search?term=Blade%20Runner&entity=movie"))
    Swag.assert(Utf8.contains(fixture.requests[1].toString(), "/w/api.php"))
    Swag.assert(Utf8.contains(fixture.requests[2].toString(), "/sparql?"))
}

#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var fixture  = MovieServerFixture{listener: &listener, port: endpoint.port, tmdbHit: true}
    var image    = Image.create(8, 8, .RGB8)
    let encoded  = expect image.encode("poster.png")
    fixture.poster.add(unwrap encoded.toSlice())
    var thread: Threading.Thread
    expect thread.init(&serveMovies, &fixture)
    expect thread.start()
    let host = MovieSource{tmdbHost: "127.0.0.1", tmdbToken: "fixture-token-abcdefghijkl", appleHost: "127.0.0.1",
                           imageHost: "127.0.0.1", port: endpoint.port, secure: false, useLocalCredentials: false}
    var movie = expect OnlineMovie.lookup("Blade.Runner (1982).mkv", host, "fr")
    let expectedPoster = Format.toString("http://127.0.0.1:%/t/p/w500/blade-runner.jpg", endpoint.port)
    Swag.assert(movie.posterUrl == expectedPoster, movie.posterUrl)
    let posterBytes = expect movie.posterBytes(host)
    var poster = expect Image.decode("poster.png", posterBytes.toSlice())
    thread.wait()
    Swag.assert(movie.id == "tmdb:78" and movie.sources == "TMDB" and poster.isValid())
    Swag.assert(movie.ratingSource == "TMDB" and movie.imdbRating == "8.1/10")
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/3/search/movie?query=Blade%20Runner&language=fr-FR"))
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "Authorization: Bearer fixture-token-abcdefghijkl"))
    Swag.assert(Utf8.contains(fixture.requests[1].toString(), "/t/p/w500/blade-runner.jpg"))
    movie.label(&poster)
    let summary = MovieSummary.fromImage(&poster)
    Swag.assert(summary.ratingSource == "TMDB" and Utf8.contains(summary.text().toString(), "TMDB rating: 8.1/10"))

    let json = """{"results":[{"id":10,"title":"Dune","release_date":"1984-12-14"},{"id":11,"title":"Dune","release_date":"2021-10-22"}]}"""
    var decoder: Serialization.Decoder'Serialization.Read.Json
    let search = expect decoder.readAll'TmdbSearch(cast(const [..] u8, json))
    defer Memory.delete(search)
    Swag.assert(MovieQuery{title: "Dune", year: "2021"}.chooseTMDB(search) == 1)
    Swag.assert(MovieQuery{title: "Dune"}.chooseTMDB(search) == Swag.U64.Max)
}

#[Swag.TestTag("integration.network")]
#test
{
    let source = MovieSource{tmdbHost: ""}
    var movie = expect OnlineMovie.lookup("Blade Runner (1982).mkv", source, language: "en")
    Swag.assert(movie.id == "Q184843" and not movie.overview.isEmpty())
    let poster = expect movie.posterBytes()
    Swag.assert(poster.count > 100)
    var french = expect OnlineMovie.lookup("Blade Runner (1982).mkv", source, language: "fr")
    Swag.assert(french.id == movie.id and not french.overview.isEmpty())
    let frenchPoster = expect french.posterBytes()
    Swag.assert(frenchPoster.count > 100 and Utf8.contains(french.posterUrl.toString(), "/wikipedia/en/"))
    var matrix = expect OnlineMovie.lookup("The Matrix (1999).mkv", source, language: "fr")
    Swag.assert(matrix.id == "Q83495" and (expect matrix.posterBytes()).count > 100)
}
