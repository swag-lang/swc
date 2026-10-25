#global internal

using Core, Gui

// One immutable presentation snapshot travels with a thumbnail job and identifies its cache.
struct ThumbnailSettings
{
    theme:       u32
    preferences: Array'ViewerPreference
    markdown:    Viewers.MarkdownText.ViewerSettings
    midi:        Viewers.Midi.ViewerSettings
    subtitles:   Viewers.Film.SubtitleSettings
}

impl ThumbnailSettings
{
    func capture(window: *ViewerWindow)->String
    {
        var settings: ThumbnailSettings
        settings.theme       = window.themeIndex
        settings.preferences = window.preferences
        settings.markdown    = Viewers.MarkdownText.g_ViewerSettings
        settings.midi        = Viewers.Midi.g_ViewerSettings
        settings.subtitles   = Viewers.Film.g_SubtitleSettings
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

    mtd apply(window: *ViewerWindow)
    {
        Viewers.MarkdownText.g_ViewerSettings = .markdown
        Viewers.Midi.g_ViewerSettings         = .midi
        Viewers.Film.g_SubtitleSettings       = .subtitles
        window.preferences = .preferences
        window.applyTheme(.theme)
    }

    mtd usesDefaultViewer(key: string)->bool
    {
        for &preference in .preferences where preference.kind == key do
            return preference.viewer == key
        return true
    }
}
