#global private

// Policy is deterministic and does not start the synthetic host's worker threads.
#test
{
    Swag.require(Swag.schedulerWorkerTarget(0, 1) == 1)
    Swag.require(Swag.schedulerWorkerTarget(0, 0) == 1)
    Swag.require(Swag.schedulerWorkerTarget(0, 22) == 21)
    Swag.require(Swag.schedulerWorkerTarget(0, 128) == Swag.MaxWorkers)
    Swag.require(Swag.schedulerWorkerTarget(1, 22) == 1)
    Swag.require(Swag.schedulerWorkerTarget(6, 22) == 6)
    Swag.require(Swag.schedulerWorkerTarget(1024, 22) == 22)
    Swag.require(Swag.schedulerWorkerTarget(1024, 128) == Swag.MaxWorkers)
    Swag.require(Swag.schedulerWorkerTarget(6, 1) == 1)
    Swag.require(Swag.schedulerWorkerTarget(0, 22, 3) == 3)
    Swag.require(Swag.schedulerWorkerTarget(1, 22, 3) == 1)
    Swag.require(Swag.schedulerWorkerTarget(6, 22, 3) == 3)
    Swag.require(Swag.schedulerWorkerTarget(0, 0, 3) == 1)
    Swag.require(Swag.schedulerWorkerTarget(6, 2, 3) == 2)
    Swag.require(Swag.schedulerWorkerTarget(1024, 128, 100) == Swag.MaxWorkers)
}

func checkThreadLimit(value: string, expected: u32, valid = true)
{
    let (count, parsed) = Swag.parseRuntimeThreadLimit(value)
    Swag.assert(count == expected and parsed == valid)
}

#test
{
    checkThreadLimit("", 0)
    checkThreadLimit("0", 0)
    checkThreadLimit("1", 1)
    checkThreadLimit("003", 3)
    checkThreadLimit("4294967295", 0xFFFF_FFFF'u32)
    checkThreadLimit("4294967296", 0, valid: false)
    checkThreadLimit("99999999999999999999999", 0, valid: false)
    checkThreadLimit("00000000000", 0, valid: false)
    checkThreadLimit("-1", 0, valid: false)
    checkThreadLimit("+3", 0, valid: false)
    checkThreadLimit(" 3", 0, valid: false)
    checkThreadLimit("3 ", 0, valid: false)
    checkThreadLimit("3x", 0, valid: false)
}
