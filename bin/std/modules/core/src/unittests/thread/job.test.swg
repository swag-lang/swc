#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
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

func reusedJobEntry(data: #null *void)
{
    let jobData = cast(*ReusedJobData) (notnull data)
    let executionIndex = Atomic.add(&jobData.executionCount, 1) + 1
    if executionIndex == 2
    {
        jobData.startedSecondRun.signal()
        jobData.allowSecondRun.wait()
    }
}

func waitJobThread(th: Threading.Thread)
{
    let data = cast(*WaitJobThreadData) (notnull th.userParam)
    Jobs.waitJob(data.job)
    Atomic.add(data.waitReturned, 1)
}

#test
{
    if Jobs.getNumWorkers() == 0
    {
        discard catch Jobs.setNumWorkers(1)
        @assert(@err == null)
    }

    var jobData: ReusedJobData
    jobData.startedSecondRun.init(true)
    jobData.allowSecondRun.init(true)

    var job: Job
    job.lambda = &reusedJobEntry
    job.data   = &jobData

    Jobs.scheduleJob(&job)
    Jobs.waitJob(&job)
    @assert(Atomic.get(&jobData.executionCount) == 1)

    Jobs.scheduleJob(&job)
    jobData.startedSecondRun.wait()

    var waitReturned: s32 = 0
    var waitData = WaitJobThreadData{job: &job, waitReturned: &waitReturned}
    var waitThread: Threading.Thread

    discard catch waitThread.init(&waitJobThread, &waitData)
    @assert(@err == null)
    discard catch waitThread.start()
    @assert(@err == null)

    for 50
    {
        if Atomic.get(&waitReturned) != 0 do
            break
        Sleep(1)
    }

    let returnedWhileBlocked = Atomic.get(&waitReturned)

    jobData.allowSecondRun.signal()
    waitThread.wait()
    Jobs.waitDone()

    @assert(returnedWhileBlocked == 0)
    @assert(Atomic.get(&jobData.executionCount) == 2)
}
