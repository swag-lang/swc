#global if WINDOWS
#global public
#global namespace File

using Win32

private func rememberedNetworkDriveMask()->u32
{
    var currentUser: HKEY = null
    if RegOpenCurrentUser(KEY_READ, &currentUser) != 0 do
        return Swag.U32.Max
    defer discard RegCloseKey(currentUser)

    var result = 0'u32
    for [index] in 26
    {
        let subkey = Utf16.toZeroTerminated(Format.toString(
            "Network\\%", cast(rune) ('A' + index)))
        var mapping: HKEY = null
        let status = RegOpenKeyExW(currentUser, @dataof(subkey), 0, KEY_READ, &mapping)
        if status == 0
        {
            result |= 1'u32 << index
            discard RegCloseKey(mapping)
        }
        elif status != ERROR_FILE_NOT_FOUND do
            return Swag.U32.Max
    }
    return result
}

// Returns the uppercase drive letters currently available for a new Windows mount point.
//
// Letters used by a logical drive or a remembered network mapping are omitted. An empty array is
// returned when Windows cannot enumerate logical drives or the current user's remembered mappings.
func availableDriveLetters()->Array'rune
{
    var result: retval
    let logical = GetLogicalDrives()
    if !logical do
        return result
    let unavailable = logical | rememberedNetworkDriveMask()
    result.reserve(26)
    for [index] in 26 where (unavailable & (1'u32 << index)) == 0 do
        result.add(cast(rune) ('A' + index))
    return result
}
