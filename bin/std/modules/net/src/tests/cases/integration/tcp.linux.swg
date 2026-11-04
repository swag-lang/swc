#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

#[Swag.TestTag("integration.network")]
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    Swag.require(endpoint.address == [127, 0, 0, 1])
    let listening = cast(s32, listener.handle)
    Swag.require(Linux.fcntl(listening, Linux.F_GETFD) & Linux.FD_CLOEXEC != 0)

    var client   = expect TcpStream.connect(endpoint)
    var accepted = -1's32
    scope
    {
        var server = expect listener.accept()
        accepted = cast(s32, server.handle)
        Swag.require(Linux.fcntl(accepted, Linux.F_GETFD) & Linux.FD_CLOEXEC != 0)
        Swag.require(Linux.fcntl(cast(s32, client.handle), Linux.F_GETFD) & Linux.FD_CLOEXEC != 0)
    }

    Swag.require(Linux.fcntl(accepted, Linux.F_GETFD) == -1 and Linux.errno() == Linux.EBADF)
    var byte: [1] u8
    Swag.require(expect client.read(byte) == 0)
    let connected = cast(s32, client.handle)
    client.close()
    client.close()
    Swag.require(Linux.fcntl(connected, Linux.F_GETFD) == -1 and Linux.errno() == Linux.EBADF)
    listener.close()
    Swag.require(Linux.fcntl(listening, Linux.F_GETFD) == -1 and Linux.errno() == Linux.EBADF)
}

#[Swag.TestTag("integration.network")]
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let endpoint = expect listener.localEndpoint()
    var error: Swag.Error
    discard catch TcpListener.listen(endpoint) as error
    Swag.require(error.value() is NetworkError)

    for backlog in [0, -1]
    {
        var invalid: Swag.Error
        discard catch TcpListener.listen(endpoint, backlog) as invalid
        Swag.require(invalid.value() is Errors.BadParameterError)
    }

    // Failed binds and validation leave the existing listener usable.
    var client = expect TcpStream.connect(endpoint)
    var server = expect listener.accept()
    Swag.require(client.isOpen() and server.isOpen())
    var empty: TcpStream
    empty.close()
    Swag.require(not empty.isOpen())
}

#[Swag.TestTag("integration.network")]
#test
{
    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    var client   = expect TcpStream.connect(expect listener.localEndpoint())
    var server   = expect listener.accept()
    Swag.require(server.isOpen())

    // Block SIGPIPE on this thread to observe generation without risking process termination.
    var mask, previous, pending: Linux.sigset_t
    Swag.require(Linux.sigemptyset(&mask) == 0)
    Swag.require(Linux.sigaddset(&mask, Linux.SIGPIPE) == 0)
    Swag.require(Linux.pthread_sigmask(Linux.SIG_BLOCK, &mask, &previous) == 0)
    defer
    {
        var immediate: Linux.timespec
        discard Linux.sigtimedwait(&mask, null, &immediate)
        discard Linux.pthread_sigmask(Linux.SIG_SETMASK, &previous, null)
    }

    Swag.require(Linux.sigpending(&pending) == 0 and Linux.sigismember(&pending, Linux.SIGPIPE) == 0)
    Swag.require(Linux.shutdown(cast(s32, client.handle), Linux.SHUT_WR) == 0)
    var error: Swag.Error
    discard catch client.write(cast(const [..] u8, "closed")) as error
    Swag.require(error.value() is NetworkError)
    if error.value() is NetworkError as networkError do
        Swag.require(networkError.code == Linux.EPIPE)
    Swag.require(Linux.sigpending(&pending) == 0 and Linux.sigismember(&pending, Linux.SIGPIPE) == 0)
}

#[Swag.TestTag("integration.network")]
#test
{
    func sockets()->Array'String
    {
        let directory = unwrap Linux.opendir("/proc/self/fd".buffer)
        defer discard Linux.closedir(directory)
        let descriptor = Linux.dirfd(directory)
        Swag.require(descriptor >= 0)
        var result: Array'String
        for
        {
            Linux.errno(0)
            let entry = Linux.readdir(directory)
            if not entry
            {
                Swag.require(Linux.errno() == 0)
                break
            }

            var buffer: [256] u8
            let count = Linux.readlinkat(descriptor, &entry.d_name[0], &buffer[0], buffer.count)
            if count < 8 do
                continue
            let target = cast(string, buffer[until cast(u64, count)])
            if target[until 8] == "socket:[" do
                result.add(Format.toString("%:%", cast(string, cast(cstring, &entry.d_name[0])), target))
        }

        result.sort()
        return result
    }

    var listener = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let occupied = expect listener.localEndpoint()
    var closed   = expect TcpListener.listen({address: [127, 0, 0, 1], port: 0})
    let refused  = expect closed.localEndpoint()
    closed.close()

    func failAcquisition(occupied, refused: Endpoint)
    {
        var bindError, connectError: Swag.Error
        discard catch TcpListener.listen(occupied) as bindError
        discard catch TcpStream.connect(refused) as connectError
        Swag.require(bindError.value() is NetworkError and connectError.value() is NetworkError)
        if bindError.value() is NetworkError as error do
            Swag.require(error.code == Linux.EADDRINUSE)
        if connectError.value() is NetworkError as error do
            Swag.require(error.code == Linux.ECONNREFUSED)
    }

    failAcquisition(occupied, refused)
    let before = sockets()
    for 16 do
        failAcquisition(occupied, refused)
    let after = sockets()
    Swag.require(before.count == after.count)
    for index in before.count do
        Swag.require(before[index] == after[index])
}
