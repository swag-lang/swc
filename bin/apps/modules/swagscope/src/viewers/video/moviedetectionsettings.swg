#global internal
#global namespace Viewers.Film

using Core, Gui, Video

// Both rules must match before automatic movie catalog access, regardless of tile arrangement.
struct MovieDetectionSettings
{
    #[Properties.Name("Movie Filename Pattern"), Properties.Description("Both movie rules must match. Empty accepts any filename."), Properties.EditSize(420)]
    namePattern: String

    #[Properties.Name("Minimum Movie Duration"), Properties.Description("Shorter videos use local frames without catalog requests. Zero accepts any duration."), Properties.Unit("min")]
    minimumMinutes: u32 = 40
}

impl MovieDetectionSettings
{
    func defaults()->MovieDetectionSettings =>
    {namePattern: #raw "[ ._(\[](19|20)[0-9]{2}([ ._)\]]|$)", minimumMinutes: 40}

    mtd const validate() fail
    {
        if .namePattern.isEmpty() do
            return
        var expression: Parser.RegExp
        try expression.compile(.namePattern, ignoreCase: true)
    }

    mtd sanitize() { .minimumMinutes = Math.min(.minimumMinutes, 24 * 60) }

    mtd const nameMatches(path: string)->bool
    {
        if not Reader.canOpen(path) or albumAudio(path) do
            return false
        if .namePattern.isEmpty() do
            return true
        var expression: Parser.RegExp
        catch expression.compile(.namePattern, ignoreCase: true) { return false }
        return expression.grep(Path.fileNameWithoutExtension(path) orelse path) != null
    }

    mtd const matches(path: string, seconds: u64)->bool =>
        seconds >= cast(u64, .minimumMinutes) * 60 and .nameMatches(path)
}

var g_MovieDetectionSettings: MovieDetectionSettings

#init
{
    g_MovieDetectionSettings = MovieDetectionSettings.defaults()
}
