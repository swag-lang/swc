#global internal
#global namespace Pipeline

using Core

// Dropping one viewer does not cancel a compilation another viewer still needs.
#[Swag.NoCopy]
struct BuildLease
{
    cache:    *CompilationCache?
    artifact: *BuildArtifact?
    reused:   bool
}

impl BuildLease
{
    mtd opDrop()
    {
        if .artifact do
            .cache!.release(.artifact!)
    }

    mtd wait(cancelled: *u32)->bool
    {
        while !.artifact!.task.isDone()
        {
            if Atomic.get(cancelled) do
                return false
            Threading.Thread.sleep(1'ms)
        }

        return !Atomic.get(cancelled)
    }
}

// Small, process-local cache of complete requests, including in-flight compilations.
// Requester threads hold leases; only unleased completed entries may be evicted.
#[Swag.NoCopy]
struct CompilationCache
{
    mutex:      Sync.Mutex
    entries:    Array'*BuildArtifact
    generation: u64
    buildCount: u64
}

impl CompilationCache
{
    const Capacity = 12

    mtd opDrop() { .close() }

    mtd invalidate()
    {
        .mutex.lock()
        defer .mutex.unlock()
        .generation += 1
    }

    mtd acquire(request: BuildRequest)->BuildLease
    {
        .mutex.lock()
        defer .mutex.unlock()
        for entry in .entries
        {
            if entry.generation == .generation and !Atomic.get(&entry.cancelled) and entry.request.satisfies(request)
            {
                entry.users += 1
                return {cache: me, artifact: entry, reused: true}
            }
        }

        // Existing executables remain pinned while their child processes are running.
        while .entries.count >= Capacity
        {
            var removed = false
            for entry, index in .entries where entry.users == 0 and entry.task.isDone()
            {
                .entries.removeAtOrdered(index)
                Memory.delete(entry)
                removed = true
                break
            }

            if !removed do
                break
        }

        let entry = Memory.new'BuildArtifact()
        entry.request    = request
        entry.generation = .generation
        entry.users      = 1
        .buildCount      += 1
        entry.id         = .buildCount
        .entries.add(entry)
        entry.task.submit(func|entry|()
        {
            catch entry.run() as error
            if error != null do
                entry.result = {text: String.from("The compiler could not complete the build."), failed: true}
        })
        return {cache: me, artifact: entry}
    }

    mtd release(entry: *BuildArtifact)
    {
        .mutex.lock()
        defer .mutex.unlock()
        Swag.assert(entry.users != 0)
        entry.users -= 1
        if !entry.users and !entry.task.isDone() do
            Atomic.exchange(&entry.cancelled, 1)
    }

    // All viewer tasks have joined before the owning window closes this cache.
    mtd close()
    {
        for entry in .entries
        {
            Swag.assert(entry.users == 0)
            Atomic.exchange(&entry.cancelled, 1)
            entry.task.wait()
            Memory.delete(entry)
        }

        .entries.clear()
    }
}
