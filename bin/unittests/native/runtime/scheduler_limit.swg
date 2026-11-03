#global private

// Run with SWAG_RUNTIME_THREADS=1, 2, or 3 to check cold startup and later growth requests.
#test
{
    if Swag.jit() do
        return

    // A focused run tests the supplied launch ceiling; an ordinary suite run stays modest.
    var expectedLimit    = 0'u32
    var hasExpectedLimit = false
    let args = Swag.args()
    for arg, index in args where arg == "--expect-runtime-threads"
    {
        Swag.require(index + 1 < args.count)
        let (expected, valid) = Swag.parseRuntimeThreadLimit(args[index + 1])
        Swag.require(valid)
        expectedLimit    = expected
        hasExpectedLimit = true
    }
    if expectedLimit == 0 do
        Swag.setWorkerCount(3)

    let initial = Swag.workerCount()
    let limit   = Swag.schedulerInstance().threadLimit
    if hasExpectedLimit do
        Swag.require(limit == expectedLimit)
    Swag.require(initial >= 1)
    if limit != 0
    {
        Swag.require(initial <= limit)
        Swag.setWorkerCount(0xFFFF_FFFF)
        let grown = Swag.workerCount()
        Swag.require(grown >= initial and grown <= limit)
        Swag.setWorkerCount(0)
        Swag.require(Swag.workerCount() == grown)
    }

    // Nested parallel work and both task priorities must still complete with a one-thread pool.
    var completed: Swag.AtomicValue'u32
    var tasks:     [8] Swag.Task
    let run = func|&completed|()
    {
        parallel for |&completed| 32
        {
            parallel for |&completed| 16 do
                completed.add(1)
        }
    }
    for index in tasks.count do
        tasks[index].submit(run, priority: index % 2 == 0 ? Swag.TaskPriority.Normal : Swag.TaskPriority.Background)
    for &task in tasks do
        task.wait()
    Swag.require(completed.load() == 8 * 32 * 16)
    if limit != 0 do
        Swag.require(Swag.workerCount() <= limit)
}
