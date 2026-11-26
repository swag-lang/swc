#global private

using Core

func processMicroseconds()->u64
{
    var stamp: Linux.timespec
    let status = Linux.clock_gettime(Linux.CLOCK_PROCESS_CPUTIME_ID, &stamp)
    Swag.require(status == 0)
    return cast(u64, stamp.tv_sec) * 1_000_000 + cast(u64, stamp.tv_nsec) / 1000
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 3)
    let costN  = expect StrConv.toU32(args[1])
    let blockR = expect StrConv.toU32(args[2])

    Swag.setWorkerCount(1)
    Swag.startWorkers()

    const MaxMemory = 1024'u64 * 1024 * 1024
    var warmup: [32] u8
    var tag:    [32] u8
    expect Crypto.scrypt("parallel benchmark", "benchmark salt!!", costN, blockR, 1, MaxMemory, warmup)

    var watch: Time.Stopwatch
    watch.start()
    let cpuStart = processMicroseconds()
    expect Crypto.scrypt("parallel benchmark", "benchmark salt!!", costN, blockR, 1, MaxMemory, tag)
    let cpuElapsed = processMicroseconds() - cpuStart
    watch.stop()
    Swag.require(Crypto.constantTimeEqual(warmup, tag))

    const Digits = "0123456789abcdef"
    var text: [64] u8
    for byte, index in tag
    {
        text[2 * index]     = Digits[byte >> 4]
        text[2 * index + 1] = Digits[byte & 15]
    }

    Console.println(watch.elapsedMicroseconds(), " ", cpuElapsed, " ", cast(string, text))
}
