#global if WINDOWS

using Core

namespace WinFsp
{
    alias HKEY = #null *void

    const KEY_READ             = 0x0002_0019'u32
    const ERROR_FILE_NOT_FOUND = 2'u32

    #[Swag.Foreign("advapi32")]
    {
        func RegOpenCurrentUser(access: u32, result: *HKEY)->u32
        func RegOpenKeyExW(key: HKEY, subkey: const [*] u16, options: u32, access: u32, result: *HKEY)->u32
        func RegCloseKey(key: HKEY)->u32
    }

    #[Swag.Foreign("kernel32")]
    func GetLogicalDrives()->u32

    private func rememberedNetworkDriveMask()->u32
    {
        var currentUser: HKEY = null
        if RegOpenCurrentUser(KEY_READ, &currentUser) != 0 do
            return Swag.U32.Max
        defer discard RegCloseKey(currentUser)

        var result = 0'u32
        for index in 26
        {
            let subkey        = Utf16.toZeroTerminated(Format.toString("Network\\%", cast(rune) ('A' + index)))
            var mapping: HKEY = null
            let status        = RegOpenKeyExW(currentUser, @dataof(subkey)!, 0, KEY_READ, &mapping)
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

    // Returns the uppercase drive letters available for a new WinFsp mount point.
    //
    // Letters used by a logical drive or a remembered network mapping are omitted. An empty
    // array means Windows could not enumerate one of those sources reliably.
    func availableDriveLetters()->Array'rune
    {
        var result: retval
        let logical = GetLogicalDrives()
        if !logical do
            return result
        let unavailable = logical | rememberedNetworkDriveMask()
        result.reserve(26)
        for index in 26 where (unavailable & (1'u32 << index)) == 0 do
            result.add(cast(rune) ('A' + index))
        return result
    }
}

// Maps the available Windows drive letters to the host-neutral destination contract.
func availableMountDestinationsNative()->Array'MountDestination
{
    var result: retval
    let available = WinFsp.availableDriveLetters()
    result.reserve(available.count)

    // Windows keeps A and B for floppies and C for the system disk, so the letters a user
    // normally expects come first and the unusual ones remain available at the end.
    for letter in available where letter >= 'D'
    {
        let name = Format.toString("%:", letter)
        result.add({name, name})
    }

    for letter in available where letter < 'D'
    {
        let name = Format.toString("%:", letter)
        result.add({name, name})
    }

    return result
}
