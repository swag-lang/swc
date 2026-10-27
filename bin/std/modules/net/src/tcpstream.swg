#global export

// Owns a blocking TCP connection; it cannot be copied.
#[Swag.NoCopy]
struct TcpStream
{
    handle: u64
    open:   bool
}
