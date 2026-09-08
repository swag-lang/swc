// Focused native lane-scaling benchmark; the compression kernel is identical in both runs.
// bin/swc.dm.exe test -f src/argon2.test.swg --module-file bench/argon2/module.swg -bc release --no-test-jit --num-cores 6
#global if #command == Swag.CompilerCommand.Test

using Core

#test
{
    let workers:  [2] u32 = [1, 4]
    let memory:   [2] u32 = [65536, 262144]
    var expected: [2][32] u8
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        Swag.assert(Swag.workerCount() == count)
        for index in memory.count
        {
            var tag: [32] u8
            expect Crypto.argon2id("parallel benchmark", "benchmark salt!!", {memoryKib: memory[index], iterations: 3, parallelism: 4}, tag)
            if count == 1 do
                expected[index] = tag
            else do
                Swag.assert(Crypto.constantTimeEqual(tag, expected[index]))

            for sample in 3
            {
                var watch: Time.Stopwatch
                watch.start()
                expect Crypto.argon2id("parallel benchmark", "benchmark salt!!", {memoryKib: memory[index], iterations: 3, parallelism: 4}, tag)
                watch.stop()
                Swag.assert(Crypto.constantTimeEqual(tag, expected[index]))
                Console.println("argon2id memoryKib=", memory[index], " workers=", count, " sample=", sample, " us=", watch.elapsedMicroseconds())
            }
        }
    }
}
