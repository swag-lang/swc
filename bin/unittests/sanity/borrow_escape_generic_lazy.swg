#global private

// A typed generic method still needs its deferred body before a caller can use
// its borrow summary. Otherwise the local writer escapes without a diagnostic.
interface BorrowLazyWriter
{
    mtd print(text: string)
}

struct(T) BorrowLazyBuffer
{
    data: [*] T?
    count, capacity: u64
}

impl BorrowLazyBuffer
{
    mtd opDrop() { .release() }

    mtd release()
    {
        var request: Swag.AllocatorRequest
        request.address = .data
        request.size    = .capacity * #sizeof(T)
        Swag.getContext().allocator!.free(&request)
    }

    mtd reserve()
    {
        var request: Swag.AllocatorRequest
        request.address = .data
        request.size    = (.capacity + 1) * #sizeof(T)
        request.oldSize = .capacity * #sizeof(T)
        Swag.getContext().allocator!.realloc(&request)
        .data = cast() request.address
        .capacity += 1
    }

    mtd add(value: #fwd T)
    {
        .reserve()
        let buffer = .data!
        buffer[.count] = #nodrop #fwd value
        .count += 1
    }
}

struct BorrowLazyLog
{
    writers: BorrowLazyBuffer'BorrowLazyWriter
}

impl BorrowLazyLog
{
    mtd addWriter(writer: BorrowLazyWriter)
    {
        .writers.add(writer)
    }
}

struct BorrowLazyLocalWriter { value: s32 }

impl BorrowLazyWriter for BorrowLazyLocalWriter
{
    mtd print(text: string) {}
}

var borrowLazySavedLog: BorrowLazyLog

func borrowLazySaveLocalWriter()
{
    var writer: BorrowLazyLocalWriter // swc-expected-note {{sema_note_borrow_source_declared_here}}
    borrowLazySavedLog.addWriter(cast(BorrowLazyWriter) writer) // swc-expected-error {{sanity_err_borrow_escape}}
}
