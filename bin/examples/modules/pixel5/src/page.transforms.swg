using Core, Pixel

func buildDetailCropImage(source: const &Image)->Image
{
    let x = cast(s32) (cast(f32) source.width * 0.21)
    let y = cast(s32) (cast(f32) source.height * 0.24)
    let w = cast(s32) (cast(f32) source.width * 0.38)
    let h = cast(s32) (cast(f32) source.height * 0.52)

    var result = source.toCrop(x, y, w, h)
    result.expand(14, 14, 14, 14, Color.fromArgb(255, 245, 240, 230))
    return result
}

func buildPanoramaCropImage(source: const &Image)->Image
{
    let x = cast(s32) (cast(f32) source.width * 0.09)
    let y = cast(s32) (cast(f32) source.height * 0.18)
    let w = cast(s32) (cast(f32) source.width * 0.78)
    let h = cast(s32) (cast(f32) source.height * 0.42)

    var result = source.toCrop(x, y, w, h)
    result.expand(12, 12, 12, 12, Color.fromArgb(255, 240, 244, 248))
    return result
}

func buildMirroredImage(source: const &Image)->Image
{
    var result = cloneImage(source)
    result.mirror()
    return result
}

func buildFlippedImage(source: const &Image)->Image
{
    var result = cloneImage(source)
    result.flip()
    return result
}

func buildTurnedImage(source: const &Image, angle: Image.TurnAngle)->Image
{
    return source.toTurn(angle)
}

func buildExpandedImage(source: const &Image)->Image
{
    var result = cloneImage(source)
    result.expand(30, 18, 30, 18, Color.fromArgb(255, 249, 244, 234))
    return result
}

func buildTransformCards(source: const &Image)
{
    setImageCard(&g_TransformCards[0], "Detail crop", "toCrop(...) + expand(...)", buildDetailCropImage(source))
    setImageCard(&g_TransformCards[1], "Wide crop", "toCrop(...) + expand(...)", buildPanoramaCropImage(source))
    setImageCard(&g_TransformCards[2], "Mirror", "mirror()", buildMirroredImage(source))
    setImageCard(&g_TransformCards[3], "Flip", "flip()", buildFlippedImage(source))
    setImageCard(&g_TransformCards[4], "Turn 90", "toTurn(.T90)", buildTurnedImage(source, .T90))
    setImageCard(&g_TransformCards[5], "Turn 180", "toTurn(.T180)", buildTurnedImage(source, .T180))
    setImageCard(&g_TransformCards[6], "Turn 270", "toTurn(.T270)", buildTurnedImage(source, .T270))
    setImageCard(&g_TransformCards[7], "Expand frame", "expand(30, 18, 30, 18)", buildExpandedImage(source))
}

func drawTransformPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel image transforms", "Page 3 : crop, mirror, flip, turn and expand done directly on image buffers.")
    for i in CardsPerPage do
        drawCard(painter, getCardRect(i), g_TransformCards[i])
}
