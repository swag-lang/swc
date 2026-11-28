#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel

// Add a sparse, valid RIFF JUNK chunk to the active movie list. Reopen ByteSink at EOF
// with its normal absolute file offset so the production writer performs all rollovers.
func appendSparseJunk(writer: *Writer, path: string, end: u64)
{
    let start = writer.sink.position()
    Swag.require(end - start >= 10 and (end - start) % 2 == 0)
    expect writer.sink.writeText("JUNK")
    expect writer.sink.writeLittleEndian(cast(u32, end - start - 8))
    expect writer.sink.close()

    var file = expect File.open(path, .Open, .ReadWrite, .Zero)
    expect file.seek(.Begin, end - 1)
    var zero: [1] u8
    expect file.writeAll(zero)
    file.close()
    writer.sink = expect ByteSink.openAppendFile(path)
}

// Release the writer after closing real continuations on both sides of 4 GiB.
#[Swag.TestTag("stress")]
#test
{
    let path = videoTempPath("avi-writer-sparse", "avi")
    defer discard catch File.delete(path)

    let rate    = expect FrameRate.create(25, 1)
    var writer  = expect Writer.create(path, 32, 24, rate)
    let encoder = cast(*Avi.Encoder, (unwrap writer.encoder).buffer)
    const Shades = [24_u8, 64, 104, 144, 184, 224]
    for shade, rank in Shades
    {
        expect writer.addFrame(videoGrayImage(32, 24, shade))
        if rank + 1 < Shades.count
        {
            appendSparseJunk(&writer, path, encoder.riffStart + encoder.riffLimit - 128)
        }
    }

    Swag.require(encoder.riffStart > Swag.U32.Max and encoder.standardIndexes == 5)
    Swag.require(writer.frameCount() == Shades.count)
    expect writer.end()
    expect writer.end()

    var direct = expect ByteSource.openFile(path)
    var avi:     Avi.Decoder
    let decoder: IDecoder = &avi
    let info   = expect decoder.open(&direct)
    Swag.require(info.frameCount == Shades.count)
    Swag.require(avi.frames[0].offset < Swag.U32.Max and avi.frames[5].offset > Swag.U32.Max)
    Swag.require(avi.frames[5].isSync)

    var reader = expect Reader.open(path, pictureOnly: true)
    Swag.require(reader.frameCount() == Shades.count)
    var picture: Image
    for rank in [5_u64, 0, 3, 2, 4, 1]
    {
        expect reader.decodeFrameInto(&picture, rank)
        videoAssertGray(picture.pixelColor(16, 12), Shades[rank], tolerance: 6)
        Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(rank), cast(f64, rank) / 25, 0.000001))
    }
}
