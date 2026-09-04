#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Jobs, Win32

struct ReusedJobData
{
    startedSecondRun: Sync.Event
    allowSecondRun:   Sync.Event
    executionCount:   s32
}

struct WaitJobThreadData
{
    job:          *Job
    waitReturned: *s32
}

func reusedJobEntry(data: *void?)
{
    let jobData        = cast(*ReusedJobData) data!
    let executionIndex = Atomic.add(&jobData.executionCount, 1) + 1
    if executionIndex == 2
    {
        jobData.startedSecondRun.signal()
        jobData.allowSecondRun.wait()
    }
}

func waitJobThread(th: Threading.Thread)
{
    let data = cast(*WaitJobThreadData) th.userParam!
    Jobs.wait(data.job)
    Atomic.add(data.waitReturned, 1)
}

#test
{
    if Jobs.workerCount() == 0
    {
        discard expect Jobs.initialize(1)
    }

    var jobData: ReusedJobData
    jobData.startedSecondRun.init(true)
    jobData.allowSecondRun.init(true)

    var job: Job
    job.lambda = &reusedJobEntry
    job.data   = &jobData
    Swag.assert(!Jobs.isDone(&job))

    Jobs.schedule(&job)
    Jobs.wait(&job)
    Swag.assert(Jobs.isDone(&job))
    Swag.assert(Atomic.get(&jobData.executionCount) == 1)

    Jobs.schedule(&job)
    jobData.startedSecondRun.wait()
    Swag.assert(!Jobs.isDone(&job))

    var waitReturned: s32 = 0
    var waitData          = WaitJobThreadData{job: &job, waitReturned: &waitReturned}
    var waitThread:   Threading.Thread

    discard expect waitThread.init(&waitJobThread, &waitData)
    discard expect waitThread.start()
    for 50
    {
        if Atomic.get(&waitReturned) != 0 do
            break
        Sleep(1)
    }

    let returnedWhileBlocked = Atomic.get(&waitReturned)

    jobData.allowSecondRun.signal()
    waitThread.wait()
    Jobs.waitAll()

    Swag.assert(returnedWhileBlocked == 0)
    Swag.assert(Atomic.get(&jobData.executionCount) == 2)
    Swag.assert(Jobs.isDone(&job))
}
