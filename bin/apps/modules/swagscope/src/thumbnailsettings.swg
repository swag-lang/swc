#global internal

using Core, Gui

// The preview cache distinguishes viewer selection and opt-in online media artwork.
struct ThumbnailSettings
{
    preferences:         Array'ViewerPreference
    onlineMovies:        bool
    onlineMusic:         bool
    movieLanguage:       String
    movieProviderStamp:  u64
    musicId:             String
    choiceSize:          u64
    choiceCreationStamp: u64
    choiceModifiedStamp: u64
}

impl ThumbnailSettings
{
    func capture(window: *ViewerWindow, entry: const *ExplorerEntry? = null)->String
    {
        var settings: ThumbnailSettings
        settings.preferences  = window.preferences
        settings.onlineMovies = window.onlineMovies
        settings.onlineMusic  = window.onlineMusic
        if window.onlineMovies
        {
            settings.movieLanguage = window.app().language()
            var token = tmdbStoredCredential("tmdb.token")
            var key   = tmdbStoredCredential("tmdb.key")
            if token.isEmpty() do
                token = Env.variable("SWAG_SCOPE_TMDB_TOKEN")
            if key.isEmpty() do
                key = Env.variable("SWAG_SCOPE_TMDB_KEY")
            settings.movieProviderStamp = Hash.hash64(Format.toString("%:%", token, key))
        }
        if entry
        {
            settings.musicId = musicChoiceId(window.musicChoices.toSlice(), entry)
            if not settings.musicId.isEmpty()
            {
                settings.choiceSize = entry.size
                settings.choiceCreationStamp = entry.creationStamp
                settings.choiceModifiedStamp = entry.modifiedStamp
            }
        }

        var output:  ConcatBuffer
        var encoder: Serialization.Encoder'Serialization.Write.TagBin
        expect encoder.writeAll(&output, settings)
        return output.toString()
    }

    func decode(bytes: string)->ThumbnailSettings fail
    {
        if not bytes.count do
            return {}
        var decoder: Serialization.Decoder'Serialization.Read.TagBin
        let settings = try decoder.readAll'ThumbnailSettings(cast(const [..] u8, bytes))
        defer Memory.delete(settings)
        return settings[]
    }

    mtd usesDefaultViewer(key: string)->bool
    {
        for &preference in .preferences where preference.kind == key do
            return preference.viewer == key
        return true
    }

    // A file can be replaced after the listing was populated and before its job starts.
    mtd choiceMatches(file: const *File.FileInfo)->bool
    {
        return .choiceSize == file.size and
               .choiceCreationStamp == Hash.hash64(file.creationTime) and
               .choiceModifiedStamp == Hash.hash64(file.lastWriteTime)
    }
}
