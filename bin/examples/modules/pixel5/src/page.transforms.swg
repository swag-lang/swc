using Core, Pixel

func buildDetailCropImage(source: Image)->Image
{
    let x = cast(s32) (cast(f32) source.width * 0.21)
    let y = cast(s32) (cast(f32) source.height * 0.24)
    let w = cast(s32) (cast(f32) source.width * 0.38)
    let h = cast(s32) (cast(f32) source.height * 0.52)

    var result = source.cropped(x, y, w, h)
    result.expand(14, 14, 14, 14, Color.fromArgb(255, 245, 240, 230))
    return result
}

func buildPanoramaCropImage(source: Image)->Image
{
    let x = cast(s32) (cast(f32) source.width * 0.16)
    let y = cast(s32) (cast(f32) source.height * 0.22)
    let w = cast(s32) (cast(f32) source.width * 0.58)
    let h = cast(s32) (cast(f32) source.height * 0.30)

    var result = source.cropped(x, y, w, h)
    result.expand(12, 12, 12, 12, Color.fromArgb(255, 240, 244, 248))
    return result
}

func buildMirroredImage(source: Image)->Image
{
    var result = cloneImage(source)
    result.mirror()
    return result
}

func buildFlippedImage(source: Image)->Image
{
    var result = cloneImage(source)
    result.flip()
    return result
}

func buildRotatedImage(source: Image, angle: Image.Rotation)->Image
{
    return source.rotated(angle)
}

func buildExpandedImage(source: Image)->Image
{
    var result = cloneImage(source)
    result.expand(30, 18, 30, 18, Color.fromArgb(255, 249, 244, 234))
    return result
}

func buildTransformCards(source: Image)
{
    setImageCard(&g_TransformCards[0], "Detail crop", "cropped(...) + expand(...)", buildDetailCropImage(source))
    setImageCard(&g_TransformCards[1], "Wide crop", "cropped(...) + expand(...)", buildPanoramaCropImage(source))
    setImageCard(&g_TransformCards[2], "Mirror", "mirror()", buildMirroredImage(source))
    setImageCard(&g_TransformCards[3], "Flip", "flip()", buildFlippedImage(source))
    setImageCard(&g_TransformCards[4], "Rotate 90", "rotated(.Clockwise90)", buildRotatedImage(source, .Clockwise90))
    setImageCard(&g_TransformCards[5], "Rotate 180", "rotated(.HalfTurn)", buildRotatedImage(source, .HalfTurn))
    setImageCard(&g_TransformCards[6], "Rotate 270", "rotated(.Clockwise270)", buildRotatedImage(source, .Clockwise270))
    setImageCard(&g_TransformCards[7], "Expand frame", "expand(30, 18, 30, 18)", buildExpandedImage(source))
}

func drawTransformPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel image transforms", "Page 3 : crop, mirror, flip, turn and expand done directly on image buffers.")
    for i in CardsPerPage do
        drawCard(painter, getCardRect(i), g_TransformCards[i])
}
