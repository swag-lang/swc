#global private

// Policy is deterministic and does not start the synthetic host's worker threads.
#test
{
    Swag.assert(Swag.schedulerWorkerTarget(0, 1) == 1)
    Swag.assert(Swag.schedulerWorkerTarget(0, 0) == 1)
    Swag.assert(Swag.schedulerWorkerTarget(0, 22) == 21)
    Swag.assert(Swag.schedulerWorkerTarget(0, 128) == Swag.MaxWorkers)
    Swag.assert(Swag.schedulerWorkerTarget(1, 22) == 1)
    Swag.assert(Swag.schedulerWorkerTarget(6, 22) == 6)
    Swag.assert(Swag.schedulerWorkerTarget(1024, 22) == 22)
    Swag.assert(Swag.schedulerWorkerTarget(1024, 128) == Swag.MaxWorkers)
    Swag.assert(Swag.schedulerWorkerTarget(6, 1) == 1)
}
