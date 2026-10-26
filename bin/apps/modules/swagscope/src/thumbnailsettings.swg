#global internal

using Core, Gui

// Viewer selection is the only user preference that changes how a thumbnail is produced.
struct ThumbnailSettings
{
    preferences: Array'ViewerPreference
}

impl ThumbnailSettings
{
    func capture(window: *ViewerWindow)->String
    {
        var settings: ThumbnailSettings
        settings.preferences = window.preferences
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
}
