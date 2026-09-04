#global internal
#global namespace Pdf

using Core

// The text of every page of a document, extracted on a worker so a search never waits for a
// page to decode on the GUI thread.
//
// The worker opens its own reader on the file: a reader is single-threaded, and the one a view
// turns pages with stays on the GUI thread. Pages are extracted in order through
// [[Gui.Pdf.Reader.loadPageText]], and a page's text is readable as soon as `readyCount` passes
// its index. The worker borrows the value until `stop` or `wait` returns, so its owner stops it
// before releasing it.
//
// The type identity is part of the exported widget layout, so it is public, but it carries no
// public contract of its own.
#[Swag.NoDoc, Swag.NoCopy]
public struct DocumentText
{
    job:      Jobs.Job
    fileName: String
    pages:    Array'String     // One entry per page, written once by the worker before it is published.
    ready:    u32              // Pages published so far, from the first; read and written atomically.
    cancel:   u32              // Asks the worker to stop after the page it is on; read and written atomically.
    started:  bool
}

impl DocumentText
{
    // Starts extracting the `pageCount` pages of `fileName` on a worker.
    mtd start(fileName: string, pageCount: u64)
    {
        Debug.assert(!.started)
        .fileName = fileName
        .pages.resize(pageCount)
        .ready      = 0
        .cancel     = 0
        .job.lambda = func(data: *void?)
        {
            let text = cast(*DocumentText) data!
            text.extract()
        }
        .job.data = me
        .started  = true
        Jobs.schedule(&.job)

        // Without workers a job only runs inside a wait, and a poll would never see it progress.
        if Jobs.isSynchronous() do
            Jobs.wait(&.job)
    }

    // Returns how many pages, from the first, have their text published.
    mtd readyCount()->u64 => cast(u64) Atomic.get(&.ready)

    // Reports whether every page has its text published.
    mtd isComplete()->bool => .started and .readyCount() == .pages.count

    // Returns the text of one published page.
    mtd pageText(index: u64)->string
    {
        Debug.assert(index < .readyCount())
        return .pages[index].toString()
    }

    // Blocks until every page is published.
    mtd wait()
    {
        if .started do
            Jobs.wait(&.job)
    }

    // Stops the worker after the page it is on and releases everything extracted.
    mtd stop()
    {
        if !.started do
            return
        Atomic.exchange(&.cancel, 1)
        Jobs.wait(&.job)
        .started = false
        .pages.clear()
        .ready  = 0
        .cancel = 0
    }

    mtd opDrop()
    {
        .stop()
    }

    // Runs on the worker: opens the file and publishes each page's text in order.
    //
    // A file that cannot be reopened, or a page that cannot be decoded, publishes empty text
    // rather than leaving a search waiting for it.
    private mtd extract()
    {
        var reader = catch Reader.open(.fileName.toString()) as openError
        if openError == null
        {
            let count = Math.min(reader.pageCount(), .pages.count)
            for index in count
            {
                if Atomic.get(&.cancel) != 0 do
                    return
                var text = catch reader.loadPageText(index) as pageError
                if pageError == null do
                    .pages[index] = #move text
                Atomic.exchange(&.ready, cast(u32) (index + 1))
            }
        }

        Atomic.exchange(&.ready, cast(u32) .pages.count)
    }
}
