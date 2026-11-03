#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Pixel, Video

func videoPreviewFile(name: string, frameCount = 4'u32)->String fail => try videoPreviewFileAt(Path.combine(Env.getSpecialDirectory(.Temp), name), frameCount)

// Writes a short silent movie of `frameCount` solid pictures at `fileName`.
func videoPreviewFileAt(fileName: string, frameCount = 4'u32)->String fail
{
    let rate    = try FrameRate.create(4, 1)
    var clip    = try Clip.create(160, 90, rate)
    let palette = [Color.fromRgb(18, 24, 32), Color.fromRgb(56, 189, 248), Color.fromRgb(247, 249, 0), Color.fromRgb(130, 70, 180)]

    for index in frameCount
    {
        var frame = Image.create(160, 90, .RGB8)
        frame.fill(palette[index % palette.count])
        try clip.addFrame(frame)
    }

    try clip.save(fileName)
    return fileName
}
