#global public
#global namespace Viewer

using Core, Gui

// How often a viewer polls one of its own background operations for completion.
const BackgroundPollInterval: Time.Duration = 16'ms

// Reports whether a view is still doing work whose result has not reached the screen.
alias IsLoading = func||()->bool

// Reports whether unfinished work has left the viewer with no useful content to present.
alias NeedsLoadingOverlay = func||()->bool

// Requests release of a viewer's external resources without blocking the GUI thread.
//
// A false result asks the host to poll again. The host destroys the document and its contributed
// chrome only after this callback returns true.
alias Retire = func||()->bool

// Configures optional progressive-loading and retirement behavior.
//
// Capture the concrete viewer pointer by value in each callback. The capture borrows the
// attached view; the host stops invoking these callbacks before destroying that view.
struct LifecycleApi
{
    public
    {
        isLoading: IsLoading?                         // Reports unfinished viewer work.
        needsLoadingOverlay: NeedsLoadingOverlay?     // Reports whether useful content is unavailable.
        retire:    Retire?                            // Releases external resources before destruction.
    }
}

// The half of a background operation that does not depend on what it produces.
//
// Whether work is running, and waiting for it to end, are the same questions whatever the worker
// loads. Naming them separately lets the host presentation and a deterministic test hold an
// operation without naming the value behind it.
struct BackgroundOperation
{
    task:    Swag.Task     // The scheduled work; borrowed by the runtime until it completes.
    started: bool          // Whether the runtime currently owns this operation.
}

impl BackgroundOperation
{
    // Reports whether a started operation has finished running on its worker.
    mtd const isDone()->bool => .started and .task.isDone()

    // Blocks until the worker has released the operation.
    //
    // The GUI thread polls [[Viewer.BackgroundOperation.isDone]] instead; this is for a caller
    // that has nothing to do until the result exists, such as teardown or a test.
    mtd wait()
    {
        if not .started do
            return
        .task.wait()
        .started = false
    }
}

// Owns the result of one scheduled value-producing operation.
//
// The worker borrows this object until `isDone` answers true. Its owner therefore exposes the
// operation through [[Viewer.Retire]] and is destroyed only after `retire` succeeds.
// [[Swag.Task]] may run the work during submission or while waiting; a separate worker
// thread is not guaranteed.
struct(T) BackgroundLoad
{
    using operation: BackgroundOperation
    fileName:        String
    value:           T
    error:           String
    late load:       func(string)->T fail
}

impl BackgroundLoad
{
    // Starts `load` for `fileName` after any previous operation has been joined.
    //
    // A failure of `load` is copied into an owned message before the worker returns, and
    // [[Viewer.BackgroundLoad.finish]] hands that message back to the caller.
    mtd start(fileName: string, load: func(string)->T fail)
    {
        Swag.assert(not .started)
        .fileName = fileName
        .load     = load
        .started  = true

        let operation = me
        .task.submit(func|operation|()
        {
            operation.value = catch operation.load(operation.fileName) as loadError
            operation.error = Errors.message(loadError)
        })
    }

    // Moves the loaded value into `value` and returns the captured failure message.
    //
    // The operation must be done. The message is empty when the load succeeded.
    // The returned message owns its text and survives reuse or destruction of this operation.
    mtd finish(value: *T)->String
    {
        Swag.assert(.isDone())
        .wait()
        value[] = #move .value
        return #move .error
    }

    // Reports when the borrowed worker state may be destroyed without waiting on the GUI thread.
    mtd retire()->bool
    {
        if not .started do
            return true
        if not .isDone() do
            return false
        .wait()
        return true
    }

    mtd opDrop()
    {
        .wait()
    }
}
