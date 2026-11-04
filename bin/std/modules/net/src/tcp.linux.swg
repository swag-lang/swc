#global if #os == Swag.TargetOs.Linux
#global export

using Core

private func nativeAddress(endpoint: Endpoint)->Linux.sockaddr_in
{
    let bytes = endpoint.address
    let bits  = (cast(u32, bytes[0]) << 24) | (cast(u32, bytes[1]) << 16) |
                (cast(u32, bytes[2]) << 8) | cast(u32, bytes[3])
    return {sin_family: cast(u16, Linux.AF_INET), sin_port: Linux.htons(endpoint.port),
            sin_addr: {s_addr: Linux.htonl(bits)}}
}

private func newSocket()->s32 fail
{
    let handle = Linux.socket(Linux.AF_INET, Linux.SOCK_STREAM | Linux.SOCK_CLOEXEC, Linux.IPPROTO_TCP)
    if handle < 0 do
        fail NetworkError{code: Linux.errno()}
    return handle
}

internal func closeTcpSocket(handle: u64)
{
    // Linux retires the descriptor even when close reports EINTR; retrying could close a new owner.
    discard Linux.close(cast(s32, handle))
}

private func finishInterruptedConnect(handle: s32) fail
{
    var descriptor = Linux.pollfd{fd: handle, events: Linux.POLLOUT}
    for
    {
        if Linux.poll(&descriptor, 1, -1) >= 0 do
            break
        let code = Linux.errno()
        if code != Linux.EINTR do
            fail NetworkError{code: code}
    }

    var code: s32
    var size = cast(u32, #sizeof(s32))
    if Linux.getsockopt(handle, Linux.SOL_SOCKET, Linux.SO_ERROR, &code, &size) < 0 do
        fail NetworkError{code: Linux.errno()}
    if code != 0 do
        fail NetworkError{code: code}
}

impl TcpStream
{
    // Connects to an IPv4 endpoint, returning an owned blocking stream.
    func connect(endpoint: Endpoint)->TcpStream fail
    {
        let handle = try newSocket()
        defer #fail closeTcpSocket(cast(u64, handle))
        let address = nativeAddress(endpoint)
        if Linux.connect(handle, cast(const *Linux.sockaddr, cast(const *void, &address)), #sizeof(Linux.sockaddr_in)) < 0
        {
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}

            // A blocking connect keeps progressing after EINTR. Reissuing it loses that state.
            try finishInterruptedConnect(handle)
        }

        return {handle: cast(u64, handle), open: true}
    }

    // Reads up to `buffer.count` bytes; zero indicates EOF or an empty buffer.
    mtd read(buffer: [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if buffer.count == 0 do
            return 0
        let count = Math.min(buffer.count, cast(u64, Swag.S64.Max))
        for
        {
            let result = Linux.recv(cast(s32, .handle), buffer.buffer, count, 0)
            if result >= 0 do
                return cast(u64, result)
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }

    // Writes up to `buffer.count` bytes and returns the amount accepted by the host.
    //
    // A closed peer reports [[Net.NetworkError]] without raising SIGPIPE in the process.
    mtd write(buffer: const [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if buffer.count == 0 do
            return 0
        let count = Math.min(buffer.count, cast(u64, Swag.S64.Max))
        for
        {
            let result = Linux.send(cast(s32, .handle), buffer.buffer, count, Linux.MSG_NOSIGNAL)
            if result >= 0 do
                return cast(u64, result)
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }
}

impl TcpListener
{
    // Binds an IPv4 endpoint and starts listening for connections.
    //
    // Port zero selects an available port, which [[Net.TcpListener.localEndpoint]] returns.
    func listen(endpoint: Endpoint, backlog = 16)->TcpListener fail
    {
        if backlog <= 0 do
            fail Errors.BadParameterError{}
        let handle  = try newSocket()
        let address = nativeAddress(endpoint)
        if Linux.bind(handle, cast(const *Linux.sockaddr, cast(const *void, &address)), #sizeof(Linux.sockaddr_in)) < 0 or
           Linux.listen(handle, backlog) < 0
        {
            let code = Linux.errno()
            closeTcpSocket(cast(u64, handle))
            fail NetworkError{code: code}
        }

        return {handle: cast(u64, handle), open: true}
    }

    // Returns the bound local address and port.
    mtd localEndpoint()->Endpoint fail
    {
        Swag.assert(.open)
        var address: Linux.sockaddr_in
        var size = cast(u32, #sizeof(Linux.sockaddr_in))
        if Linux.getsockname(cast(s32, .handle), cast(*Linux.sockaddr, cast(*void, &address)), &size) < 0 do
            fail NetworkError{code: Linux.errno()}
        let bits = Linux.ntohl(address.sin_addr.s_addr)
        return {address: [cast(u8, bits >> 24), cast(u8, (bits >> 16) & 0xFF),
                          cast(u8, (bits >> 8) & 0xFF), cast(u8, bits & 0xFF)], port: Linux.ntohs(address.sin_port)}
    }

    // Blocks until a peer connects and returns an independently owned stream.
    mtd accept()->TcpStream fail
    {
        Swag.assert(.open)
        for
        {
            let handle = Linux.accept4(cast(s32, .handle), null, null, Linux.SOCK_CLOEXEC)
            if handle >= 0 do
                return {handle: cast(u64, handle), open: true}
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }
}
