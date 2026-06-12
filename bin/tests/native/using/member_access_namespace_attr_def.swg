#global public
#global namespace Core

namespace Compress
{
    struct Deflate
    {
        enum CompressionLevel
        {
            Default,
            BestSpeed,
        }
    }
}

namespace Serialization
{
    attr Compress()
}
