#global private

using Core

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 3)
    let memoryKib = expect StrConv.toU32(args[1])
    let workers   = expect StrConv.toU32(args[2])
    Swag.require(workers == 1 or workers == 4)

    Swag.setWorkerCount(workers)
    Swag.startWorkers()
    Swag.require(Swag.workerCount() == workers)

    let parameters = Crypto.Argon2Parameters{memoryKib, iterations: 3, parallelism: 4}
    var warmup: [32] u8
    var tag:    [32] u8
    expect Crypto.argon2id("parallel benchmark", "benchmark salt!!", parameters, warmup)
    var watch: Time.Stopwatch
    watch.start()
    expect Crypto.argon2id("parallel benchmark", "benchmark salt!!", parameters, tag)
    watch.stop()
    Swag.require(Crypto.constantTimeEqual(warmup, tag))

    const Digits = "0123456789abcdef"
    var text: [64] u8
    for byte, index in tag
    {
        text[2 * index]     = Digits[byte >> 4]
        text[2 * index + 1] = Digits[byte & 15]
    }

    Console.println(watch.elapsedMicroseconds(), " ", cast(string, text))
}
