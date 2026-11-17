using Core

impl Image
{
    // Turns the image upright from an EXIF `Orientation` value, in place.
    //
    // `orientation` says how the stored pixels relate to the upright picture, from 1 (already
    // upright) to 8; [[Pixel.Exif.orientationOf]] reads it from decoded metadata. Values 5 to 8
    // swap the width and the height. Any value outside 2 to 8 leaves the image unchanged. When
    // the image carries an EXIF Orientation field, it is reset to 1 after the pixels are turned.
    public mtd orient(orientation: u32)
    {
        switch orientation
        {
        case 2:
            .mirror()

        case 3:
            .rotate(.HalfTurn)

        case 4:
            .flip()

        case 5:
            .rotate(.Clockwise90)
            .mirror()

        case 6:
            .rotate(.Clockwise90)

        case 7:
            .rotate(.Clockwise270)
            .mirror()

        case 8:
            .rotate(.Clockwise270)
        }

        if orientation >= 2 and orientation <= 8 do
            Exif.resetOrientation(&.metadata)
    }

    // Returns an upright copy of the image for an EXIF `Orientation` value.
    //
    // The source is unchanged. Values outside 2 to 8 return an identical copy.
    public mtd const oriented(orientation: u32)->Image
    {
        var result: #returntype = me
        result.orient(orientation)
        return result
    }
}
