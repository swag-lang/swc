#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

const LinuxBatchThreadCount = 65'u64

func linuxBatchThreadBody(thread: const *Threading.Thread)
{
    let completed = cast(*Swag.AtomicValue'u32, unwrap thread.userParam)
    discard completed.add(1)
}

func linuxBatchDelayedThreadBody(thread: const *Threading.Thread)
{
    Threading.Thread.sleep(100'ms)
    linuxBatchThreadBody(thread)
}

#[Swag.TestTag("stress.thread")]
#test
{
    Swag.require(not Swag.jit(), "run the native wait batch with --no-test-jit")
    var completed: Swag.AtomicValue'u32
    var threads: [LinuxBatchThreadCount] Threading.Thread
    for i in LinuxBatchThreadCount
    {
        let body = i + 1 == LinuxBatchThreadCount ? &linuxBatchDelayedThreadBody : &linuxBatchThreadBody
        expect threads[i].init(body, &completed)
    }
    for &thread in threads do
        expect thread.start()

    // The last thread lies beyond the 64-handle native batch and finishes after the first batch.
    Threading.wait(&threads[0], &threads[1], &threads[2], &threads[3], &threads[4], &threads[5], &threads[6], &threads[7], &threads[8], &threads[9], &threads[10], &threads[11], &threads[12], &threads[13], &threads[14], &threads[15], &threads[16], &threads[17], &threads[18], &threads[19], &threads[20], &threads[21], &threads[22], &threads[23], &threads[24], &threads[25], &threads[26], &threads[27], &threads[28], &threads[29], &threads[30], &threads[31], &threads[32], &threads[33], &threads[34], &threads[35], &threads[36], &threads[37], &threads[38], &threads[39], &threads[40], &threads[41], &threads[42], &threads[43], &threads[44], &threads[45], &threads[46], &threads[47], &threads[48], &threads[49], &threads[50], &threads[51], &threads[52], &threads[53], &threads[54], &threads[55], &threads[56], &threads[57], &threads[58], &threads[59], &threads[60], &threads[61], &threads[62], &threads[63], &threads[64])
    Swag.require(completed.load() == LinuxBatchThreadCount)
    for &thread in threads do
        Swag.require(not thread.isValid())
}
