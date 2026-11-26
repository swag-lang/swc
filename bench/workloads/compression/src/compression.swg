#global private

using Core, Core.Compress

func encode(zlib: *ZLib, codec: string, input: const [..] u8)->Array'u8
{
    #static if not #hastag("compression.baseline")
    {
        if codec == "lz4" do
            return expect Lz4.compress(input)
        if codec == "snappy" do
            return expect Snappy.compress(input)
    }

    Swag.require(codec == "zlib1" or codec == "zlib6")
    return expect zlib.compress(input, codec == "zlib1" ? .BestSpeed : .Default)
}

func decode(zlib: *ZLib, codec: string, output: [..] u8, input: const [..] u8)
{
    #static if not #hastag("compression.baseline")
    {
        if codec == "lz4"
        {
            expect Lz4.decompressInto(output, input)
            return
        }

        if codec == "snappy"
        {
            let snappySize = expect Snappy.decompressInto(output, input)
            Swag.require(snappySize == output.count)
            return
        }
    }

    Swag.require(codec == "zlib1" or codec == "zlib6")
    let written = expect zlib.decompressInto(output, input)
    Swag.require(written == output.count)
}

func processTicks()->u64
{
    var stamp: Linux.timespec
    let status = Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &stamp)
    Swag.require(status == 0)
    return cast(u64, stamp.tv_sec) * 1_000_000_000 + cast(u64, stamp.tv_nsec)
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 7)
    let input  = expect File.readAllBytes(args[3])
    let rounds = expect StrConv.toU64(args[5])
    let size   = expect StrConv.toU64(args[6])
    Swag.require(rounds > 0)

    var zlib:    ZLib
    var result:  Array'u8
    var elapsed: u64
    if args[2] == "encode"
    {
        discard encode(&zlib, args[1], input.toSlice())
        let start = processTicks()
        for rounds do
            result = encode(&zlib, args[1], input.toSlice())
        elapsed = processTicks() - start
    }
    else
    {
        Swag.require(args[2] == "decode")
        result.resize(size)
        decode(&zlib, args[1], result.toSlice(), input.toSlice())
        let start = processTicks()
        for rounds do
            decode(&zlib, args[1], result.toSlice(), input.toSlice())
        elapsed = processTicks() - start
    }

    discard expect File.writeAllBytes(args[4], result.toSlice())
    Console.println(elapsed)
}
