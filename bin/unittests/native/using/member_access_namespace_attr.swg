#global private
using Core, Serialization

#test
{
    let level = Compress.Deflate.CompressionLevel.BestSpeed
    @assert(level == .BestSpeed)
}
