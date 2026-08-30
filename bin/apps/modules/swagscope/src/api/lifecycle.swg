#global public
#global namespace Viewer

using Core, Gui

// How often a viewer polls one of its own background operations for completion.
const BackgroundPollInterval: Time.Duration = 16'ms

// Reports whether a view is still doing work whose result has not reached the screen.
alias IsLoading = func(*Wnd)->bool

// Reports whether unfinished work has left the viewer with no useful content to present.
alias NeedsLoadingOverlay = func(*Wnd)->bool

// Requests release of a viewer's external resources without blocking the GUI thread.
//
// A false result asks the host to poll again. The host destroys the document and its contributed
// chrome only after this callback returns true.
alias Retire = func(*Wnd)->bool

// Configures optional progressive-loading and retirement behavior.
struct LifecycleApi
{
    public
    {
        isLoading:           #null IsLoading               // Reports unfinished viewer work.
        needsLoadingOverlay: #null NeedsLoadingOverlay     // Reports whether useful content is unavailable.
        retire:              #null Retire                  // Releases external resources before destruction.
    }
}

// The half of a background operation that does not depend on what it produces.
//
// Whether work is running, and waiting for it to end, are the same questions whatever the worker
// loads. Naming them separately lets the host presentation and a deterministic test hold an
// operation without naming the value behind it.
struct BackgroundOperation
{
    job:     Jobs.Job     // The scheduled work; borrowed by the worker until it completes.
    started: bool         // Whether a worker currently owns this operation.
}

impl BackgroundOperation
{
    mtd const isDone()->bool => .started and Jobs.isDone(&.job)

    // Blocks until the worker has released the operation.
    //
    // The GUI thread polls [[Viewer.BackgroundOperation.isDone]] instead; this is for a caller
    // that has nothing to do until the result exists, such as teardown or a test.
    mtd wait()
    {
        if !.started do
            return
        Jobs.wait(&.job)
        .started = false
    }
}

// Owns one value-producing operation that must not run on the GUI thread.
//
// The worker borrows this object until `isDone` answers true. Its owner therefore exposes the
// operation through [[Viewer.Retire]] and is destroyed only after `retire` succeeds.
struct(T) BackgroundLoad
{
    using operation: BackgroundOperation
    fileName:        String
    value:           T
    error:           #null any
    load:            func(string)->T fail = undefined
}

impl BackgroundLoad
{
    mtd start(fileName: string, load: func(string)->T fail)
    {
        Debug.assert(!.started)
        .fileName   = fileName
        .load       = load
        .job.lambda = func(data: #null *void)
        {
            let operation = cast(*BackgroundLoad'T) data!
            operation.value = catch operation.load(operation.fileName.toString()) as loadError
            operation.error = loadError
        }
        .job.data = me
        .started  = true
        Jobs.schedule(&.job)
    }

    // Publishes the loaded value and returns the captured failure message.
    mtd finish(value: *T)->String
    {
        Debug.assert(.isDone())
        .wait()
        value[] = #move .value
        let result = Errors.message(.error)
        .error = null
        return result
    }

    // Reports when the borrowed worker state may be destroyed without waiting on the GUI thread.
    mtd retire()->bool
    {
        if !.started do
            return true
        if !.isDone() do
            return false
        .wait()
        return true
    }

    mtd opDrop()
    {
        .wait()
    }
}
