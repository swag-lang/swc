#global if #os == Swag.TargetOs.Linux
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

private func openDescriptorCount()->u64
{
    let directory = unwrap Linux.opendir("/proc/self/fd".buffer)
    defer discard Linux.closedir(directory)
    var count = 0'u64
    while Linux.readdir(directory) do
        count += 1
    return count
}

private func sharedMappingCount()->u64 fail
{
    let maps = try File.readAllLines("/proc/self/maps")
    var count = 0'u64
    for line in maps where line.contains("/SYSV") do
        count += 1
    return count
}

private func sharedSegmentCount()->u64 fail
{
    let segments = try File.readAllLines("/proc/sysvipc/shm")
    return segments.count - 1
}

// Runs against an X11 server such as Xvfb, including its shared-memory path.
#[Swag.TestTag("integration.host.linux")]
#test
{
    var source = expect Source.open({0, 0, 320, 240, false})
    var image: Image
    discard expect source.grabInto(&image)
    Swag.require(image.width == 320 and image.height == 240)
    Swag.require(image.pixelFormat == .BGRA8 and image.byteCount == 320 * 240 * 4)
    expect source.reopen()
    discard expect source.grabInto(&image)
    Swag.require(image.width == 320 and image.height == 240)
}

// A broken XCB socket reconnects without keeping its old descriptor or SysV mapping.
#[Swag.TestTag("integration.host.linux")]
#test
{
    let descriptors = openDescriptorCount()
    let mappings = expect sharedMappingCount()
    let segments = expect sharedSegmentCount()
    var usedSharedMemory = false
    for 4
    {
        scope
        {
            var source = expect Source.open({0, 0, 64, 48, false})
            var image: Image
            discard expect source.grabInto(&image)
            let storage = image.pixels.storage()
            let capture = &source.sources[0].capture
            if capture.shmData
            {
                usedSharedMemory = true
                Swag.require((expect sharedMappingCount()) == mappings + 1)
            }
            let fileDescriptor = expect X11Capture.symbol'Linux.xcb_get_file_descriptor_fn(
                unwrap capture.library, "xcb_get_file_descriptor")
            let socket = fileDescriptor(unwrap capture.connection)
            Swag.require(socket >= 0 and Linux.shutdown(socket, 0) == 0)
            var failure: Swag.Error
            discard catch source.grabInto(&image) as failure
            Swag.require(failure.value() is Swag.SystemError)
            expect source.reopen()
            discard expect source.grabInto(&image)
            Swag.require(image.pixels.storage() == storage)
        }
        Swag.require(openDescriptorCount() == descriptors)
        Swag.require((expect sharedMappingCount()) == mappings)
    }
    for 100
    {
        if (expect sharedSegmentCount()) == segments do
            break
        Threading.Thread.sleep(1'ms)
    }
    Swag.require((expect sharedSegmentCount()) == segments)
    Console.println("X11 socket recovery: shared memory=", usedSharedMemory)
}
