#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    func GetTempFileNameA(path, prefix: LPCSTR, unique: UINT, fileName: LPSTR)->UINT
    func DeviceIoControl(handle: HANDLE, code: DWORD, input: LPVOID, inputSize: DWORD, output: LPVOID, outputSize: DWORD, returned: LPDWORD, overlapped: LPOVERLAPPED)->BOOL
}

// Both legacy file APIs can return 0xffffffff on success. A sparse temporary file proves
// the size case without allocating four gigabytes of disk space or writing a large payload.
#test
{
    var directory: [1024] u8
    var fileName:  [1024] u8
    let length = expect GetTempPathA(cast(u32) directory.count, directory.buffer)
    Swag.assert(length > 0 and length < directory.count)
    Swag.assert(GetTempFileNameA(directory.buffer, "swc".buffer, 0, fileName.buffer) != 0)
    defer catch DeleteFileA(fileName.buffer)

    let file = expect CreateFileA(fileName.buffer, GENERIC_READ | GENERIC_WRITE, 0, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null)
    defer CloseHandle(file)
    var returned: DWORD
    const SetSparse = 0x000900C4'u32
    Swag.assert(DeviceIoControl(file, SetSparse, null, 0, null, 0, &returned, null) != 0)

    var high = 0's32
    let low  = expect SetFilePointer(file, -1, &high, FILE_BEGIN)
    Swag.assert(low == INVALID_SET_FILE_POINTER and high == 0)
    expect SetEndOfFile(file)
    var sizeHigh: DWORD
    let sizeLow = expect GetFileSize(file, &sizeHigh)
    Swag.assert(sizeLow == INVALID_FILE_SIZE and sizeHigh == 0)

    discard catch SetFilePointer(INVALID_HANDLE_VALUE, 0, &high, FILE_BEGIN) as seekError
    Swag.assert(seekError is SystemError)
    discard catch GetFileSize(INVALID_HANDLE_VALUE, &sizeHigh) as sizeError
    Swag.assert(sizeError is SystemError)
}
