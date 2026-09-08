// bin/swc.dm.exe test -f src/chacha20.test.swg --module-file bench/chacha20/module.swg -bc release --no-test-jit --num-cores 6
#global if #command == Swag.CompilerCommand.Test

using Core

#test
{
    let sizes:    [5] u64 = [16384, 65535, 65536, 262144, 4194304]
    let workers:  [2] u32 = [1, 4]
    var key:      [Crypto.ChaCha20KeySize] u8
    var nonce:    [Crypto.ChaCha20NonceSize] u8
    var source:   Array'u8
    var output:   Array'u8
    var expected: Array'u8
    source.resize(sizes[4])
    output.resize(source.count)
    expected.resize(source.count)
    for index in source.count do
        source[index] = cast(u8) ((index * 47 + 13) & 0xFF)

    Swag.setWorkerCount(1)
    Swag.startWorkers()
    expect Crypto.chacha20Xor(key, nonce, source.toSlice(), expected.toSlice(), 7)
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        Swag.assert(Swag.workerCount() == count)
        for size in sizes
        {
            let input       = source.toSlice()[until size]
            let destination = output.toSlice()[until size]
            let reference   = expected.toSlice()[until size]
            let iterations  = 16 * 1024 * 1024 / size
            expect Crypto.chacha20Xor(key, nonce, input, destination, 7)
            Swag.assert(Crypto.constantTimeEqual(destination, reference))
            for sample in 3
            {
                var watch: Time.Stopwatch
                watch.start()
                for iteration in iterations do
                    expect Crypto.chacha20Xor(key, nonce, input, destination, 7)
                watch.stop()
                Swag.assert(Crypto.constantTimeEqual(destination, reference))
                Console.println("chacha20 bytes=", size, " workers=", count, " iterations=", iterations, " sample=", sample, " us=", watch.elapsedMicroseconds())
            }
        }
    }
}
