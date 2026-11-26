#global private

using Core

alias HashOperation = func(const [..] u8)->u64

func murmur(input: const [..] u8)->u64 => Hash.murmur3(input.buffer, input.count, 0)
func city(input: const [..] u8)->u64   => Hash.City32.compute(input)

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
    Swag.require(args.count == 6)
    let iterations = expect StrConv.toU64(args[4])
    let offset     = expect StrConv.toU64(args[5])
    let source     = expect File.readAllBytes(args[2])
    Swag.require(iterations and source.count >= offset)
    var empty: [1] u8
    let input = source.count == offset ? empty[until 0] : source.toSlice()[offset to]

    let isCity = args[1] == "cityhash32"
    Swag.require(isCity or args[1] == "murmur64a")
    let operation: HashOperation = isCity ? &city : &murmur
    let outputSize = isCity ? 4 : 8
    let expected   = operation(input)
    var hash       = expected
    let wallStart  = Time.monotonicTicks()
    let cpuStart   = processTicks()
    for iterations do
        hash = operation(input)
    let cpuElapsed  = processTicks() - cpuStart
    let wallElapsed = Time.monotonicTicks() - wallStart

    Swag.require(hash == expected)
    var output: [8] u8
    for byte in outputSize do
        output[byte] = cast(u8, (hash >> cast(u32, byte * 8)))
    discard expect File.writeAllBytes(args[3], output[until outputSize])
    Console.println(wallElapsed, " ", cpuElapsed, " ", Time.monotonicFrequency())
}
