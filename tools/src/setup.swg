#global namespace Tool.Setup

#import("win32", location: "swag@std")

using Core, Win32

// The unexpanded user PATH and its registry string type.
struct PathValue
{
    text:    String
    expands: bool = true
}

// The persistent user-environment boundary; tests supply an in-memory store.
interface IEnvironmentStore
{
    mtd readUserPath()->PathValue fail
    mtd writeUserPath(value: PathValue) fail
    mtd writeSwagPath(directory: string) fail
    mtd notifyChanges()
}

private func comparableDirectory(directory: string)->String
{
    var result = String.from(Tokenize.eatQuotes(Latin1.trim(directory)))
    Path.normalize(&result)
    while result.count > 3 and result.endsWith("/") do
        result.removeBack()
    return result
}

// Compares complete entries while preserving the original PATH text and variable references.
func pathContainsDirectory(path, directory: string)->bool
{
    let wanted = Utf16.toZeroTerminated(comparableDirectory(directory).toString())
    for entry in Tokenize.split(path, ";")
    {
        let normalized = Utf16.toZeroTerminated(comparableDirectory(entry).toString())

        // Windows ordinal casing preserves Unicode identity; bytewise folding does not.
        if CompareStringOrdinal(normalized.buffer, -1, wanted.buffer, -1, TRUE) == CSTR_EQUAL do
            return true
    }

    return false
}

// Registers one directory in the persisted user PATH, never in a process-environment snapshot.
// Returns whether PATH changed. A later error can leave an earlier successful write in place.
func configureEnvironment(store: IEnvironmentStore, directory: string)->bool fail
{
    var path    = try store.readUserPath()
    let changed = not pathContainsDirectory(path.text.toString(), directory)
    var wrote   = false
    defer
    {
        if wrote do
            store.notifyChanges()
    }

    if changed
    {
        if not path.text.isEmpty() do
            path.text += ";"
        path.text += directory
        try store.writeUserPath(path)
        wrote = true
    }

    try store.writeSwagPath(directory)
    wrote = true
    return changed
}

// Reads and writes only HKCU\Environment. It never expands stored variable references.
struct WindowsEnvironmentStore {}

private func checkRegistry(status: LSTATUS, operation: string) fail
{
    if status == ERROR_SUCCESS do
        return
    let message = Format.toString("cannot % (Windows error %)", operation, status)
    fail Swag.SystemError{Errors.mkString(message.toString()), errorID: cast(u32) status}
}

private func writeUserEnvironment(name, value: string, kind: DWORD) fail
{
    let nativeKey = Utf16.toZeroTerminated("Environment")
    var key: HKEY
    try checkRegistry(RegCreateKeyExW(HKEY_CURRENT_USER, nativeKey.buffer, 0, null, 0, KEY_SET_VALUE, null, &key, null), "open the user environment for writing")
    defer RegCloseKey(key)

    let nativeName  = Utf16.toZeroTerminated(name)
    let nativeValue = Utf16.toZeroTerminated(value)
    let bytes       = cast(u32) (nativeValue.count * #sizeof(u16))
    try checkRegistry(RegSetValueExW(key, nativeName.buffer, 0, kind, cast(const *u8?) nativeValue.buffer, bytes), Format.toString("write user environment variable '%'", name).toString())
}

impl IEnvironmentStore for WindowsEnvironmentStore
{
    mtd impl readUserPath()->PathValue fail
    {
        let nativeKey = Utf16.toZeroTerminated("Environment")
        var key: HKEY
        let opened    = RegOpenKeyExW(HKEY_CURRENT_USER, nativeKey.buffer, 0, KEY_QUERY_VALUE, &key)
        if opened == ERROR_FILE_NOT_FOUND do
            return {}
        try checkRegistry(opened, "open the user environment for reading")
        defer RegCloseKey(key)

        let name = Utf16.toZeroTerminated("PATH")

        // The value can grow between the size query and the read. Retry with its new size.
        for 4
        {
            var kind, bytes: DWORD
            let queried = RegQueryValueExW(key, name.buffer, null, &kind, null, &bytes)
            if queried == ERROR_FILE_NOT_FOUND do
                return {}
            try checkRegistry(queried, "read the size of user PATH")

            var data: Array'u16
            data.resize(cast(u64) bytes / #sizeof(u16) + 1)
            let read = RegQueryValueExW(key, name.buffer, null, &kind, cast(*u8?) data.buffer, &bytes)
            if read == ERROR_MORE_DATA do
                continue
            if read == ERROR_FILE_NOT_FOUND do
                return {}
            try checkRegistry(read, "read user PATH")
            if kind != REG_SZ and kind != REG_EXPAND_SZ do
                fail Swag.SystemError{"user PATH is not stored as a registry string"}
            if bytes % #sizeof(u16) != 0 do
                fail Swag.SystemError{"user PATH has an incomplete UTF-16 code unit"}

            // RegQueryValueExW does not promise a terminator, even for a registry string.
            let units = cast(u64) bytes / #sizeof(u16)
            data[units] = 0
            let length = Utf16.lengthUntilZero(data.toSlice()[0 until units])
            return {Utf8.fromUtf16(data.toSlice()[0 until length]), kind == REG_EXPAND_SZ}
        }

        fail Swag.SystemError{"user PATH kept changing while setup read it"}
    }

    mtd impl writeUserPath(value: PathValue) fail
    {
        try writeUserEnvironment("PATH", value.text.toString(), value.expands ? REG_EXPAND_SZ : REG_SZ)
    }

    mtd impl writeSwagPath(directory: string) fail
    {
        try writeUserEnvironment("SWAG_PATH", directory, REG_SZ)
    }

    mtd impl notifyChanges()
    {
        let name = Utf16.toZeroTerminated("Environment")
        discard SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, cast #bit (LPARAM) cast(u64) name.buffer, SMTO_ABORTIFHUNG, 1000, null)
    }
}
