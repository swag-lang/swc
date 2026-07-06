#global private
using Swag

struct BorrowEscapeOwner
{
    buffer: [8] u8
    length: u64
}

impl BorrowEscapeOwner
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string
    {
        return @mkstring(&.buffer[0], .length)
    }
}

struct BorrowEscapePayload
{
    text: string
}

func borrowEscapePayload()->BorrowEscapePayload
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1

    var payload = BorrowEscapePayload{text: owner}
    return payload // swc-expected-warning {{sema_warn_borrow_escape}}
}

// Returning stack-borrowed array data from a runtime function must warn.
func borrowEscapeArrayCast()->string
{
    var buf: [3] u8
    buf[0] = 'a''u8
    buf[1] = 'b''u8
    buf[2] = 'c''u8
    return cast(string) buf // swc-expected-warning {{sema_warn_borrow_escape}}
}

// Casting a scalar value to a pointer reinterprets the value: it does not
// borrow the variable storage and must not warn.
var borrowEscapeScalarSink: *void

func borrowEscapeScalarCast()->*void
{
    var idx: u64 = 42
    borrowEscapeScalarSink = cast(*void) idx
    return cast(*void) idx
}

// '#run' return payloads pointing into the local stack frame are persisted
// into the compiler segment, so no borrow can escape and no warning is expected.
const BorrowEscapeRunString: string = #run
{
    var buf: [3] u8
    buf[0] = 'r''u8
    buf[1] = 'u''u8
    buf[2] = 'n''u8
    return cast(string) buf
}

#assert(BorrowEscapeRunString == "run")
