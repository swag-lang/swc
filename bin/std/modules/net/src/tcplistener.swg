#global export

// Owns a blocking TCP listener; it cannot be copied.
#[Swag.NoCopy]
struct TcpListener
{
    handle: u64
    open:   bool
}
