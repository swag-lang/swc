#global private
using Core, Serialization

#test
{
    let level = Compress.Deflate.CompressionLevel.BestSpeed
    Swag.require(level == .BestSpeed)
}
