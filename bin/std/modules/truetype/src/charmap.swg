using Swag, Core

// Describes the Unicode character map selected for a [[TrueType.Face]].
//
// Use [[TrueType.Face.glyphIndex]] or [[TrueType.Face.loadChar]] for lookups.
// The numeric identifiers are the platform and encoding values stored in the
// font's `cmap` table.
public struct CharMap
{
    // The selected mapping is owned by the face and cannot be replaced by callers.
    public readonly
    {
        #[Swag.Late]
        face:       *Face     // Borrowed pointer to the owning face.
        encoding:   u32       // Four-byte encoding tag, or zero for the selected Unicode map.
        platformID: u16       // TrueType platform identifier.
        encodingID: u16       // Platform-specific encoding identifier.
    }
}

impl CharMap
{
    mtd initialize(face: *Face)
    {
        .face = face
    }

    mtd select(platformID, encodingID: u16)
    {
        .platformID = platformID
        .encodingID = encodingID
    }
}
