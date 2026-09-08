using Core

// A balanced specialization tree creates more distinct loop bodies than the runtime can cache.
// Each leaf writes a different constant, so identical-code folding cannot merge their bodies.
func(First: u64, Count: u64) visitBodies(values: *[512][3] u64)
{
    #static if Count == 1
    {
        parallel for |values| index in 3 do
            values[][First][index] += First + index + 1
    }
    else
    {
        visitBodies'(First, Count / 2)(values)
        visitBodies'(First + Count / 2, Count - Count / 2)(values)
    }
}

#[Swag.Safety(.Assert, true)]
#main
{
    let workers: [2] u32 = [1, 4]
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        Swag.assert(Swag.workerCount() == count)
        for sample in 3
        {
            var values: [512][3] u64
            visitBodies'(0, 512)(&values)
            var watch: Time.Stopwatch
            watch.start()
            for repeat in 32 do
                visitBodies'(0, 512)(&values)
            watch.stop()
            for leaf in 512
            {
                for index in 3 do
                    Swag.assert(values[leaf][index] == 33 * (leaf + index + 1))
            }

            Console.println("parallel-cache bodies=512 iterations=3 calls=16384 workers=", count, " sample=", sample, " us=", watch.elapsedMicroseconds())
        }
    }
}
