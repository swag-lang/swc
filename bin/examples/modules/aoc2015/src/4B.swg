/*
--- Part Two ---
Now find one that starts with six zeroes.
*/

using Core

internal var best: u64 = Swag.U64.Max

func day4B()
{
    #if #cfg == "release"
    {
        if @jit do
            return

        //Time.Stopwatch.scopeMeasure()
        assume Jobs.setNumWorkers()

        struct ForJob
        {
            using base:     Jobs.Job
            start:          u64
            result:         u64 = Swag.U64.Max
        }

        var sliceJobs: Array'ForJob
        sliceJobs.resize(Jobs.getNumWorkers())

        func jobEntry(jobData: #null *void)
        {
            let oneJob = cast(*ForJob) notnull jobData
            var index  = oneJob.start
            let offset = Jobs.getNumWorkers()
            var buffer: [16] u8
            day4InitBuffer(&buffer)
            for
            {
                // Another job is better than us, just quit
                if Atomic.get(&best) < index do
                    return

                let v = Hash.Md5.compute(day4BuildInput(&buffer, index))
                if v[0] == 0 and v[1] == 0 and v[2] == 0
                {
                    discard Atomic.exchange(&best, index)
                    oneJob.result = index
                    return
                }

                index += offset
            }
        }

        for &j in sliceJobs
        {
            j.base.lambda = &jobEntry
            j.data        = j
            j.start       = @index
            Jobs.scheduleJob(j)
        }

        var total: u64 = Swag.U64.Max
        for &j in sliceJobs
        {
            Jobs.waitJob(j)
            total = Math.min(total, j.result)
        }

        //Console.print("total: ", total)
        @assert(total == 9962624)
    }
}
