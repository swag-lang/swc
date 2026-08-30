#global private
using Core, Serialization

#test
{
    let level = Compress.Deflate.CompressionLevel.BestSpeed
    Swag.assert(level == .BestSpeed)
}
