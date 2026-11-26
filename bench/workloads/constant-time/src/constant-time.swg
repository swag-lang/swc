#global private

using Core

func processTicks()->u64
{
    var stamp: Linux.timespec
    Swag.require(Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &stamp) == 0)
    return cast(u64, stamp.tv_sec) * 1_000_000_000 + cast(u64, stamp.tv_nsec)
}

#main
{
    let args = Env.arguments()
    if args.count == 2 and args[1] == "--guard"
    {
        checkGuardedInputs()
        return
    }

    Swag.require(args.count == 6)
    let iterations = expect StrConv.toU64(args[4])
    let offset     = expect StrConv.toU64(args[5])
    let input      = expect File.readAllBytes(args[2])
    Swag.require(iterations and offset <= input.count)

    var copied: Array'u8
    copied.resize(input.count)
    if input.count do
        Memory.copy(copied.toSlice().buffer, input.toSlice().buffer, input.count)

    let left  = input.toSlice()[offset until input.count]
    let right = copied.toSlice()[offset until copied.count]
    let equal = args[1] == "ct-equal"
    if not equal
    {
        Swag.require(right.count and (args[1] == "ct-first" or args[1] == "ct-last"))
        let position = args[1] == "ct-first" ? 0 : right.count - 1
        right[position] ^= 1
    }

    Swag.require(Crypto.constantTimeEqual(left, right) == equal)
    var matches   = 0'u64
    let wallStart = Time.monotonicTicks()
    let cpuStart  = processTicks()
    for iterations do
        matches += cast(u64, Crypto.constantTimeEqual(left, right))
    let cpuElapsed  = processTicks() - cpuStart
    let wallElapsed = Time.monotonicTicks() - wallStart

    Swag.require(matches == (equal ? iterations : 0))
    let output: [1] u8 = [cast(u8, matches == iterations)]
    discard expect File.writeAllBytes(args[3], output)
    Console.println(wallElapsed, " ", cpuElapsed, " ", Time.monotonicFrequency())
}
