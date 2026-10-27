#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Net, Pixel

struct MovieServerFixture
{
    late listener: *TcpListener
    port: u16
    poster: Array'u8
    requests: [3] String
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
    for index in 3
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
        if index == 0
        {
            let json = Format.toString("""{"query":{"pages":[{"title":"Blade Runner (film)","description":"film de Ridley Scott sorti en 1982","extract":"A futuristic detective story.","pageprops":{"wikibase_item":"Q184843"},"thumbnail":{"source":"http://127.0.0.1:%/poster.png","width":100,"height":150}}]}}""", fixture.port)
            body.add(cast(const [..] u8, json.toString()))
        }
        elif index == 1
        {
            let json = """{"results":{"bindings":[{"directorLabel":{"value":"Ridley Scott"},"castLabel":{"value":"Harrison Ford"},"score":{"value":"8.1/10"},"scoreDate":{"value":"2026-02-25T00:00:00Z"}}]}}"""
            body.add(cast(const [..] u8, json))
        }
        else do
            body.add(fixture.poster.toSlice())
        let header = Format.toString("HTTP/1.1 200 OK\r\nContent-Length: %\r\nConnection: close\r\n\r\n", body.count)
        writeMovieBytes(&stream, cast(const [..] u8, header.toString()))
        writeMovieBytes(&stream, body.toSlice())
    }
}

#test
{
    let text = safeMediaText("Title <url>https://example.com</url>\r\nNext")
    Swag.assert(not Utf8.contains(text.toString(), "<url>"))
    Swag.assert(not Utf8.contains(text.toString(), "\n"))
    Swag.assert(validWikiId("Q184843") and not validWikiId("Q1/../other"))
    let query = MovieQuery.fromFile("D:/Films/Blade.Runner (1982).mkv")
    Swag.assert(query.title == "Blade Runner" and query.year == "1982")
    let json = """{"query":{"pages":[{"title":"Blade Runner","description":"1982 film","pageprops":{"wikibase_item":"Q1"}},{"title":"Blade Runner (film)","description":"1982 film","pageprops":{"wikibase_item":"Q2"}}]}}"""
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
    var fixture = MovieServerFixture{listener: &listener, port: endpoint.port}
    var image = Image.create(8, 8, .RGB8)
    let encoded = expect image.encode("poster.png")
    fixture.poster.add(unwrap encoded.toSlice())
    var thread: Threading.Thread
    expect thread.init(&serveMovies, &fixture)
    expect thread.start()
    let host = MovieSource{wikiHost: "127.0.0.1", dataHost: "127.0.0.1",
                           imageHost: "127.0.0.1", port: endpoint.port, secure: false}
    var movie = expect OnlineMovie.lookup("Blade.Runner (1982).mkv", host, "fr")
    let posterBytes = expect movie.posterBytes(host)
    var poster = expect Image.decode("poster.png", posterBytes.toSlice())
    thread.wait()
    Swag.assert(movie.id == "Q184843" and poster.isValid())
    Swag.assert(Utf8.contains(fixture.requests[0].toString(), "/w/api.php"))
    Swag.assert(Utf8.contains(fixture.requests[1].toString(), "/sparql?"))
    Swag.assert(Utf8.contains(fixture.requests[2].toString(), "/poster.png"))
    movie.label(&poster)
    let summary = MovieSummary.fromImage(&poster)
    Swag.assert(summary.title == "Blade Runner" and summary.director == "Ridley Scott")
    Swag.assert(summary.actors == "Harrison Ford" and summary.imdbRating == "8.1/10 (2026-02-25)")
    Swag.assert(summary.overview == "A futuristic detective story.")
}

#[Swag.TestTag("integration.network")]
#test
{
    var movie = expect OnlineMovie.lookup("Blade Runner (1982).mkv", language: "en")
    Swag.assert(movie.id == "Q184843" and not movie.overview.isEmpty())
    let poster = expect movie.posterBytes()
    Swag.assert(poster.count > 100)
    var french = expect OnlineMovie.lookup("Blade Runner (1982).mkv", language: "fr")
    Swag.assert(french.id == movie.id and not french.overview.isEmpty())
    let frenchPoster = expect french.posterBytes()
    Swag.assert(frenchPoster.count > 100 and Utf8.contains(french.posterUrl.toString(), "/wikipedia/en/"))
    var matrix = expect OnlineMovie.lookup("The Matrix (1999).mkv", language: "fr")
    Swag.assert(matrix.id == "Q83495" and (expect matrix.posterBytes()).count > 100)
}
