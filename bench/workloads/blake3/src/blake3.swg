#global private

using Core

alias Operation = func(const [..] u8, [..] u8)

func blake3(input: const [..] u8, output: [..] u8) => expect Hash.Blake3.compute(input, output)

func blake3Stream(input: const [..] u8, output: [..] u8, size: u64)
{
    var hash   = Hash.Blake3.create()
    var offset = 0'u64
    while offset < input.count
    {
        let end = offset + Math.min(size, input.count - offset)
        hash.update(input[offset until end])
        offset = end
    }

    expect hash.finalize(output)
}

func blake3Stream4k(input: const [..] u8, output: [..] u8)  => blake3Stream(input, output, 4096)
func blake3Stream64k(input: const [..] u8, output: [..] u8) => blake3Stream(input, output, 65536)
func blake3Stream1m(input: const [..] u8, output: [..] u8)  => blake3Stream(input, output, 1048576)

func selectOperation(name: string)->{operation: Operation, outputSize: u64}
{
    switch name
    {
    case "blake3":                return {&blake3, 32}
    case "blake3-stream-4096":    return {&blake3Stream4k, 32}
    case "blake3-stream-65536":   return {&blake3Stream64k, 32}
    case "blake3-stream-1048576": return {&blake3Stream1m, 32}
    default:                      unreachable
    }
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
    Swag.require(args.count == 6)
    let iterations = expect StrConv.toU64(args[4])
    let offset     = expect StrConv.toU64(args[5])
    let source     = expect File.readAllBytes(args[2])
    Swag.require(iterations and offset <= source.count)
    let input    = source.toSlice()[offset until source.count]
    let selected = selectOperation(args[1])
    var output: Array'u8
    output.resize(selected.outputSize)
    let destination = output.toSlice()

    let workerLimit = Env.variable("SWAG_RUNTIME_THREADS")
    let requested   = workerLimit.isEmpty() ? 1'u32 : expect StrConv.toU32(workerLimit.toString())
    let workers     = Swag.max(requested, 1)
    Swag.setWorkerCount(workers)
    Swag.startWorkers()
    Swag.require(Swag.workerCount() == workers)
    selected.operation(input, destination)
    let wallStart = Time.monotonicTicks()
    let cpuStart  = processTicks()
    for iterations do
        selected.operation(input, destination)
    let cpuElapsed  = processTicks() - cpuStart
    let wallElapsed = Time.monotonicTicks() - wallStart

    discard expect File.writeAllBytes(args[3], destination)
    Console.println(wallElapsed, " ", cpuElapsed, " ", Time.monotonicFrequency())
}
