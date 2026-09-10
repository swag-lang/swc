#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

var registryEncoderDrops: u32
var registryDecoderDrops: u32
var registryAllocator:    Swag.Allocator

struct(N: u32) RegistryPadding
{
    value: u32 = N
}

impl IImageEncoder for RegistryPadding
{
    mtd impl format()->ImageFormat => {"Registry padding", ".registrypadding"}
    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail {}
}

impl IImageDecoder for RegistryPadding
{
    mtd impl format()->ImageFormat => {"Registry padding", ".registrypadding"}
    mtd impl decode(bytes: const [..] u8, options: DecodeOptions)->Image fail => Image.create(1, 1, .RGBA8)
}

func(N: u32) registerPaddingCodecs()
{
    Image.registerEncoder'(RegistryPadding'N)()
    Image.registerDecoder'(RegistryPadding'N)()
    #static if N > 0 do
        registerPaddingCodecs'(N - 1)()
}

struct RegistryEncoder
{
    marker: u32 = 0xABCD
}

impl RegistryEncoder
{
    mtd opDrop()
    {
        Swag.assert(.marker == 0xABCD)
        registryEncoderDrops += 1
    }
}

impl IImageEncoder for RegistryEncoder
{
    mtd impl format()->ImageFormat => {"Registry encoder", ".registrytest"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        registerPaddingCodecs'31()
        if options != null do
            fail BadParameterError{}
        result.addBytes("encoded")
    }
}

struct RegistryDecoder
{
    marker: u32 = 0x1234
}

impl RegistryDecoder
{
    mtd opDrop()
    {
        Swag.assert(.marker == 0x1234)
        registryDecoderDrops += 1
    }
}

impl IImageDecoder for RegistryDecoder
{
    mtd impl format()->ImageFormat => {"Registry decoder", ".registrytest"}

    mtd impl decode(bytes: const [..] u8, options: DecodeOptions)->Image fail
    {
        registerPaddingCodecs'31()
        if bytes.count == 1 do
            fail BadParameterError{}
        return Image.create(1, 1, .RGBA8)
    }
}

internal impl Image
{
    // Isolate global registration and poison freed registry storage so stale borrows are visible.
    func checkRegistryCallback(decoding, failing: bool)
    {
        let backing: IAllocator = &registryAllocator
        var oldEncoders         = #move encoders
        var oldDecoders         = #move decoders
        defer
        {
            encoders = #move oldEncoders
            decoders = #move oldDecoders
        }

        encoders.allocator = backing
        decoders.allocator = backing
        registerEncoder'RegistryEncoder()
        registerDecoder'RegistryDecoder()
        let encoderStorage = encoders.buffer
        let decoderStorage = decoders.buffer
        registryEncoderDrops, registryDecoderDrops = 0

        if decoding
        {
            let bytes  = failing ? "x" : "input"
            let result = catch Image.decode("image.registrytest", cast(const [..] u8) bytes) as err
            Swag.assert((err != null) == failing)
            if not failing do
                Swag.assert(result.width == 1 and result.height == 1)
            Swag.assert(registryDecoderDrops == (failing ? 1 : 2))
        }
        else
        {
            let image         = Image.create(1, 1, .RGBA8)
            let options: any? = failing ? cast(any?) true : null
            let result        = catch image.encode("image.registrytest", options) as err
            Swag.assert((err != null) == failing)
            if not failing do
                Swag.assert(result.toString() == "encoded")
            Swag.assert(registryEncoderDrops == 1)
        }

        Swag.assert(encoders.buffer != encoderStorage)
        Swag.assert(decoders.buffer != decoderStorage)
        Swag.assert(encoders.count == 33 and decoders.count == 33)
    }
}

#test
{
    registryAllocator.setup()
    registryAllocator.configure(false, false, false, false, true)
    Image.checkRegistryCallback(false, false)
    Image.checkRegistryCallback(false, true)
    Image.checkRegistryCallback(true, false)
    Image.checkRegistryCallback(true, true)
    Swag.assert(registryAllocator.stats().countAlloc == 0)
    let backing: IAllocator = &registryAllocator
    var request: AllocatorRequest
    backing.freeAll(&request)
}
