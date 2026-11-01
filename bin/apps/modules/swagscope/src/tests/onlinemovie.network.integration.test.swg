#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Net, Pixel

#[Swag.TestTag("integration.network")]
#test
{
    let source = MovieSource{tmdbHost: ""}
    var movie  = expect OnlineMovie.lookup("Blade Runner (1982).mkv", source, language: "en")
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
