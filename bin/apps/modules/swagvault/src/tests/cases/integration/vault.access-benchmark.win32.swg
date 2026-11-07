#global if WINDOWS and #hastag("vault.integration")

using Core

namespace Integration
{
    const BenchmarkClipCount = 16'u64
    const BenchmarkReadCount = 64'u64
    const BenchmarkClipSize  = 512'u64 * 1024
    const BenchmarkReadSize  = 4096'u64

    var g_ReadCallbackMicroseconds: u64
    var g_ReadWaitMicroseconds:     u64
    var g_ReadIoMicroseconds:       u64
    var g_ReadCryptoMicroseconds:   u64
    var g_ReadIoCount:             u64

    struct BenchmarkReadWork
    {
        paths:    [BenchmarkClipCount] String
        failures: u64
    }

    func readClip(path: string, seed: u64)->bool fail
    {
        var stream = try File.openRead(path)
        defer stream.close()

        var buffer: [BenchmarkReadSize] u8
        for index in BenchmarkReadCount
        {
            let block = (index * 37 + seed * 13) % (BenchmarkClipSize / BenchmarkReadSize)
            if not (try stream.readExactAt(block * BenchmarkReadSize, buffer)) do
                return false
        }

        return true
    }

    func reportAccessTime(name: string, elapsed: u64, count: u64)
    {
        Console.println(Format.toString("%: % us total, % us/op (% operations)", name, elapsed, elapsed / count, count))
    }

    func resetReadTimes()
    {
        g_ReadCallbackMicroseconds = 0
        g_ReadWaitMicroseconds     = 0
        g_ReadIoMicroseconds       = 0
        g_ReadCryptoMicroseconds   = 0
        g_ReadIoCount             = 0
    }

    func reportReadTimes()
    {
        Console.println(Format.toString("  callbacks: % us; lock wait: % us; host read: % us; decrypt: % us; host reads: %",
                                        g_ReadCallbackMicroseconds,
                                        g_ReadWaitMicroseconds,
                                        g_ReadIoMicroseconds,
                                        g_ReadCryptoMicroseconds,
                                        g_ReadIoCount))
    }

    #[Swag.Propagate]
    func runAccessBenchmark() fail
    {
        var box = Sandbox.create()
        defer box.cleanup()

        Console.println("Swag Vault access benchmark sandbox: ", box.root)
        Console.println("Temporary drive: ", box.mountPoint)
        var created = Volume.create(box.container, "", ContainerSize)
        created.close()
        box.mountVolume("")

        let clips = Path.combine(driveRoot(box.mountPoint), "clips")
        Directory.create(clips)
        var readWork: BenchmarkReadWork
        let clipPayload = createPayload(BenchmarkClipSize)
        for index in BenchmarkClipCount
        {
            readWork.paths[index] = Path.combine(clips, Format.toString("clip-%.bin", index))
            File.writeAllBytes(readWork.paths[index], clipPayload.toSlice())
        }

        let largePath    = Path.combine(clips, "large.bin")
        let largePayload = createPayload(8 * 1024 * 1024)
        File.writeAllBytes(largePath, largePayload.toSlice())

        // Warm the mounted path before comparing the same request set in each mode.
        for index in BenchmarkClipCount do
            verify(readClip(readWork.paths[index], index), "benchmark clips must be readable")

        var timer: Time.Stopwatch
        timer.start()
        for 100
        {
            let entries = Directory.enumerateFiles(clips)
            verify(entries.count == BenchmarkClipCount + 1, "benchmark directory must contain all files")
        }
        reportAccessTime("directory enumerate", timer.elapsedMicroseconds(), 100)

        timer.restart()
        var openedBytes = 0'u64
        for 100
        {
            var stream = File.openRead(largePath)
            openedBytes += stream.size()
            stream.close()
        }
        verify(openedBytes == 100 * largePayload.count, "benchmark opens must see the large file")
        reportAccessTime("open and size", timer.elapsedMicroseconds(), 100)

        resetReadTimes()
        timer.restart()
        for index in BenchmarkClipCount do
            verify(readClip(readWork.paths[index], index), "sequential request set must read every clip")
        reportAccessTime("random 4 KiB reads, serial", timer.elapsedMicroseconds(), BenchmarkClipCount * BenchmarkReadCount)
        reportReadTimes()

        resetReadTimes()
        timer.restart()
        parallel for |&readWork| index in BenchmarkClipCount
        {
            if not (expect readClip(readWork.paths[index], index)) do
                Atomic.add(&readWork.failures, 1)
        }
        verify(readWork.failures == 0, "parallel request set must read every clip")
        reportAccessTime("random 4 KiB reads, parallel", timer.elapsedMicroseconds(), BenchmarkClipCount * BenchmarkReadCount)
        reportReadTimes()

        var stream = File.openRead(largePath)
        defer stream.close()
        var buffer: [64 * 1024] u8
        resetReadTimes()
        timer.restart()
        for index in largePayload.count / buffer.count do
            verify(stream.readExactAt(index * buffer.count, buffer), "sequential read must complete")
        reportAccessTime("large file, 64 KiB reads", timer.elapsedMicroseconds(), largePayload.count / buffer.count)
        reportReadTimes()

        box.closeSandbox()
    }

    func runAccessBenchmarkAndExit()
    {
        discard catch runAccessBenchmark()
        {
            Console.println("FAIL: ", errorMessage(Swag.err))
            Env.exit(1)
        }
        Console.println("PASS: access benchmark completed.")
        Env.exit(0)
    }
}
