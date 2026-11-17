#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func assertOpaqueImageMetadata(image: const *Image)
{
    Swag.require(image.metadata.count == 1)
    Swag.require(image.metadata[0].signature == 42 and image.metadata[0].isTag("opaque"))
    Swag.require(image.metadata[0].value.count == 1 and image.metadata[0].value[0] == 0x5A)
}

// Copying transforms retain opaque metadata just like their in-place counterparts.
#test
{
    var source = Image.create(4, 4, .RGBA8)
    source.fill(Argb.White)
    var metadata: ImageMetadata
    metadata.signature = 42
    metadata.tag       = "opaque"
    metadata.value.add(0x5A'u8)
    source.metadata.add(#move metadata)

    let converted  = source.convertedTo(.BGRA8)
    let resized    = source.resized(3, 3)
    let cropped    = source.cropped(1, 1, 2, 2)
    let expanded   = source.expanded(1, 1, 1, 1, Argb.Zero)
    let flipped    = source.flipped()
    let mirrored   = source.mirrored()
    let rotated    = source.rotated(.Clockwise90)
    let halved     = source.halved()
    let covered    = source.covered(3, 3)
    let oriented   = source.oriented(1)
    let associated = source.convertedAlphaTo(.Premultiplied)
    let mixed      = source.mixed(source, 0, 0)
    let filtered   = source.withKernelApplied(.BoxBlur3x3)

    for image in [converted, resized, cropped, expanded, flipped, mirrored, rotated, halved, covered, oriented, associated, mixed, filtered]
    {
        assertOpaqueImageMetadata(image)
    }

    var inPlace = source
    inPlace.convertTo(.BGRA8)
    inPlace.resize(3, 3)
    inPlace.crop(1, 1, 2, 2)
    inPlace.expand(1, 1, 1, 1, Argb.Zero)
    inPlace.flip()
    inPlace.mirror()
    inPlace.rotate(.Clockwise90)
    inPlace.halve()
    assertOpaqueImageMetadata(&inPlace)
}
