using Core

func compute(index, rounds: u64)->u64
{
    var value = index + 1
    for round in rounds
    {
        value ^= value << 13
        value ^= value >> 7
        value ^= value << 17
    }

    return value
}

func fill(values: [..] u64, rounds, heavyBegin, heavyEnd, heavyRounds: u64)
{
    parallel for |values, rounds, heavyBegin, heavyEnd, heavyRounds| index in values.count do
        values[index] = compute(index, index >= heavyBegin and index < heavyEnd ? heavyRounds : rounds)
}

#[Swag.Safety(.Assert, true)]
func measure(name: string, count, rounds, heavyBegin, heavyEnd, heavyRounds, repeats: u64)
{
    var values: [2048] u64
    let target = values[0 until count]
    for warmup in 32 do
        fill(target, rounds, heavyBegin, heavyEnd, heavyRounds)
    for sample in 3
    {
        var watch: Time.Stopwatch
        watch.start()
        for repeat in repeats do
            fill(target, rounds, heavyBegin, heavyEnd, heavyRounds)
        watch.stop()
        for index in count do
            Swag.assert(values[index] == compute(index, index >= heavyBegin and index < heavyEnd ? heavyRounds : rounds))
        Console.println(name, " workers=", Swag.workerCount(), " sample=", sample, " us=", watch.elapsedMicroseconds())
    }
}

#main
{
    let workers: [2] u32 = [1, 4]
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        measure("cheap", 64, 1, 0, 0, 0, 65536)
        measure("uniform", 2048, 2048, 0, 0, 0, 8)
        measure("heavy-head", 2048, 256, 0, 512, 8192, 8)
        measure("heavy-tail", 2048, 256, 1536, 2048, 8192, 8)
        measure("four", 4, 262144, 0, 0, 0, 8)
    }
}
