#global private

// A leading dot names a member of the innermost subject. Reaching past it to the enclosing
// receiver is the classic 'with' capture, so it is reported instead of resolved.
struct NotInnermostReading
{
    tag: s32
}

struct NotInnermostRecorder
{
    total: s32
}

impl NotInnermostRecorder
{
    mtd record(reading: *NotInnermostReading)
    {
        with reading
        {
            .tag   = 1
            .total = 2     // swc-expected-error {{sema_err_auto_scope_not_innermost}}
        }
    }
}

#test
{
    var reading:  NotInnermostReading
    var recorder: NotInnermostRecorder
    recorder.record(&reading)
}
