#global public
#global namespace Viewer

using Core, Gui

// How often a viewer polls a background operation that does not tell it when it ends.
const BackgroundPollInterval: Time.Duration = 16'ms

// Reports whether a view is still doing work whose result has not reached the screen.
alias IsLoading = func||()->bool

// Reports whether unfinished work has left the viewer with no useful content to present.
alias NeedsLoadingOverlay = func||()->bool

// Requests release of a viewer's external resources without blocking the GUI thread.
//
// A false result means work is still stopping. That work must end with a [[Gui.TaskEvent]]
// delivered to the view or to one of its windows: the host asks again once such an event has
// been delivered, and never polls. The host destroys the document and its contributed chrome
// only after this callback returns true.
alias Retire = func||()->bool

// Configures optional progressive-loading and retirement behavior.
//
// Capture the concrete viewer pointer by value in each callback. The capture borrows the
// attached view; the host stops invoking these callbacks before destroying that view.
struct LifecycleApi
{
    public
    {
        isLoading: IsLoading?     // Reports unfinished viewer work.
        needsLoadingOverlay: NeedsLoadingOverlay?     // Reports whether useful content is unavailable.
        retire:    Retire?        // Releases external resources before destruction.
    }
}

// Returns the lifecycle of a viewer whose background work is its one polled `load`.
//
// The viewer is loading, and has nothing to show yet, while that load is pending; it retires
// through its own `retire`, which must retire the load.
func(T) loadLifecycle(view: *T)->LifecycleApi
{
    with var result: #returntype
    {
        .isLoading = func|view|()->bool => view.load.isPending()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    return result
}

// The half of a background operation that does not depend on what it produces.
//
// Whether work is running, and waiting for it to end, are the same questions whatever the worker
// loads. Naming them separately lets the host presentation and a deterministic test hold an
// operation without naming the value behind it.
//
// An operation submitted for an owner window tells that window when the work ends: the window
// receives a [[Gui.TaskEvent]], which [[Viewer.BackgroundOperation.claim]] recognizes. Nothing
// polls.
struct BackgroundOperation
{
    task:    Swag.Task     // The scheduled work; borrowed by the runtime until it completes.
    started: bool          // Whether the runtime owns this operation, or its result is not collected yet.
    owner:   *Wnd?         // The window waiting for the end of the work; null when nobody waits for it.
}

impl BackgroundOperation
{
    // Submits `body`. When `owner` is given, it receives a [[Gui.TaskEvent]] once the work ends.
    //
    // `Background` priority shares the runtime's adaptive admission budget; use it for speculative
    // work such as thumbnails. Work the reader explicitly requested keeps normal priority.
    mtd submit(body: func||(), owner: *Wnd? = null, priority = Swag.TaskPriority.Normal)
    {
        Swag.assert(not .started)
        .started = true
        .owner   = owner
        .task.submit(body, owner ? owner.taskNotifier(&.task) : null, priority: priority)
    }

    // Reports whether a started operation has finished running on its worker.
    mtd const isDone()->bool => .started and .task.isDone()

    // Blocks until the worker has released the operation.
    //
    // The owner window waits for its [[Gui.TaskEvent]] instead; this is for a caller that has
    // nothing to do until the result exists, such as teardown or a test.
    mtd wait()
    {
        if not .started do
            return
        .task.wait()
        .started = false
    }

    // Reports whether the owner still waits for the operation, which is what a viewer reports as
    // loading.
    mtd const isPending()->bool => .owner != null

    // Returns whether `evt` reports the end of this operation; the owner then stops waiting for it.
    mtd claim(evt: *TaskEvent)->bool
    {
        if evt.task != &.task or .owner == null or not .isDone() do
            return false
        .owner = null
        return true
    }

    // Stops waiting for the operation, whatever the worker still does.
    mtd abandon()
    {
        .owner = null
    }
}

// Owns the result of one scheduled value-producing operation.
//
// The worker borrows this object until the work is done. Its owner therefore exposes the
// operation through [[Viewer.Retire]] and is destroyed only after `retire` succeeds.
// [[Swag.Task]] may run the work during submission or while waiting; a separate worker
// thread is not guaranteed.
struct(T) BackgroundLoad
{
    task:      Swag.Task'T     // The scheduled work and its outcome.
    started:   bool            // Whether the runtime owns this load, or its result is not collected yet.
    owner:     *Wnd?           // The window waiting for the end of the load; null when nobody waits for it.
    fileName:  String
    late load: func(string)->T fail
}

impl BackgroundLoad
{
    // Starts `load` for `fileName` after any previous load has been collected.
    //
    // When `owner` is given, it receives a [[Gui.TaskEvent]] once the load ends, which
    // [[Viewer.BackgroundLoad.claim]] recognizes. [[Viewer.BackgroundLoad.finish]] then hands over
    // the value, or the failure as a message.
    mtd start(fileName: string, load: func(string)->T fail, owner: *Wnd? = null)
    {
        Swag.assert(not .started)
        .fileName = fileName
        .load     = load
        .started  = true
        .owner    = owner

        let operation = me
        .task.submit(func|operation|()->T fail => try operation.load(operation.fileName), owner ? owner.taskNotifier(&.task) : null)
    }

    // Reports whether a started load has finished running on its worker.
    mtd const isDone()->bool => .started and .task.isDone()

    // Reports whether the owner still waits for the load, which is what a viewer reports as loading.
    mtd const isPending()->bool => .owner != null

    // Returns whether `evt` reports the end of this load; the owner then stops waiting for it.
    mtd claim(evt: *TaskEvent)->bool
    {
        if evt.task != &.task or .owner == null or not .isDone() do
            return false
        .owner = null
        return true
    }

    // Moves the loaded value into `value` and returns the failure message.
    //
    // The load must be done. The message is empty when the load succeeded.
    mtd finish(value: *T)->String
    {
        Swag.assert(.isDone())
        .started = false
        .owner   = null
        var loadErrorOutcome: Swag.Error
        catch { value[] = try .task.take() } as loadErrorOutcome
        let loadError = loadErrorOutcome.value()
        return Viewer.failureText(loadError)
    }

    // Asks the load to stop, and reports when the worker has let go of this object so it can be
    // destroyed without waiting on the GUI thread.
    //
    // A retired load is no longer waited for.
    mtd retire()->bool
    {
        .task.cancel()
        if .task.isPending() do
            return false
        .started = false
        .owner   = null
        return true
    }

    mtd opDrop()
    {
        .task.cancel()
        .task.wait()
    }
}
