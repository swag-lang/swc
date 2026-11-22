#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// File metadata describes the exact file and directory entries requested.
#test
{
    let root = CoreTests.makeFilesystemTestPath("core_fileinfo")
    let file = Path.combine(root, "payload.bin")
    defer discard catch Directory.delete(root, recurse: true)

    expect Directory.create(root)
    let payload: [3] u8 = [0x10, 0x20, 0x30]
    discard expect File.writeAllBytes(file.toString(), payload)

    let fileInfo = expect File.info(file.toString())
    Swag.require(fileInfo.fullName == file.toString())
    Swag.require(fileInfo.size == payload.count)
    Swag.require(not fileInfo.isDirectory())
    Swag.require(fileInfo.lastWriteTime.isValid())

    let directoryInfo = expect File.info(root.toString())
    Swag.require(directoryInfo.fullName == root.toString())
    Swag.require(directoryInfo.size == 0)
    Swag.require(directoryInfo.isDirectory())

    let relativeInfo = expect File.info(".")
    Swag.require(relativeInfo.fullName == ".")
    Swag.require(relativeInfo.isDirectory())
}
