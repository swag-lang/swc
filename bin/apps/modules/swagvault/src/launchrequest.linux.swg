#global if #os == Swag.TargetOs.Linux

using Core

private func launchRequestName(token: u64)->String
{
    return Format.toString("/swag.vault.launch.%.%", Linux.getuid(), token)
}

func forwardVaultLaunch(surfaceId, path: string)->bool fail
{
    func sharedMemoryError()->Swag.SystemError
    {
        return {"cannot allocate shared memory for the Swag Vault launch", errorID: cast(u64, Linux.errno())}
    }

    let token = Guid64.random().value
    let name  = launchRequestName(token)
    let flags = Linux.O_RDWR | Linux.O_CREAT | Linux.O_EXCL | Linux.O_CLOEXEC
    let fd    = Linux.shm_open(name.storage(), flags, 0x180)
    if fd < 0 do
        fail sharedMemoryError()
    defer
    {
        discard Linux.shm_unlink(name.storage())
        discard Linux.close(fd)
    }

    if Linux.ftruncate(fd, #sizeof(LaunchRequest)) != 0 do
        fail sharedMemoryError()
    let view = Linux.mmap(null, #sizeof(LaunchRequest), Linux.PROT_READ | Linux.PROT_WRITE, Linux.MAP_SHARED, fd, 0)
    if not view or cast(s64, view) == -1 do
        fail sharedMemoryError()
    defer discard Linux.munmap(view, #sizeof(LaunchRequest))
    return (assume cast(*LaunchRequest, view)).send(surfaceId, token, path)
}

func receiveVaultLaunch(token: u64)->String
{
    let name = launchRequestName(token)
    let fd   = Linux.shm_open(name.storage(), Linux.O_RDWR | Linux.O_CLOEXEC, 0)
    if fd < 0 do
        return {}
    defer discard Linux.close(fd)

    var info: Linux.stat
    if Linux.fstat(fd, &info) != 0 or
       info.st_uid != Linux.getuid() or
       (info.st_mode & 0x3F) != 0 or
       info.st_size != #sizeof(LaunchRequest) do
        return {}
    let view = Linux.mmap(null, #sizeof(LaunchRequest), Linux.PROT_READ | Linux.PROT_WRITE, Linux.MAP_SHARED, fd, 0)
    if not view or cast(s64, view) == -1 do
        return {}
    defer discard Linux.munmap(view, #sizeof(LaunchRequest))
    discard Linux.shm_unlink(name.storage())
    return (assume cast(*LaunchRequest, view)).receive()
}
