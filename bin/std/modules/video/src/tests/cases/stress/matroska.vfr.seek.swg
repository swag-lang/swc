#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// A distant seek in VFR media must preserve display rank when it rebuilds the index from cues.
#[Swag.TestTag("stress")]
#test
{
    var reader = expect Reader.open(videoFixturePath("matroska-vfr-seek.mkv"), pictureOnly: true)
    let first  = expect reader.decodeFrame(0)
    let target = expect reader.decodeFrame(2_300)
    Swag.require(first.isValid() and target.isValid())
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(2_300), 94.0, 0.001))
}
