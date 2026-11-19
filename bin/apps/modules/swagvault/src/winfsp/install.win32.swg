#global if WINDOWS

using Core, Win32

const SupportsWinFspInstall = true

func hasInstalledWinFsp()->bool => not Env.isSandboxed() and not WinFsp.installedLibrary().isEmpty()

func installWinFspNative() fail { try WinFsp.install() }

namespace WinFsp
{
    const InstallerName = "winfsp.msi"

    // Windows Installer rejects the forward slashes used by Swag's path helpers.
    func installerPackagePath(directory: string)->String
    {
        var result = Path.combine(directory, InstallerName)
        result.replace("/", "\\")
        return result
    }

    // Use the same machine registration as the WinFsp loader, including custom install paths.
    func installedLibrary()->String
    {
        let keyName   = Utf16.toZeroTerminated("Software\\WinFsp")
        var key: HKEY = null
        if RegOpenKeyExW(HKEY_LOCAL_MACHINE, keyName.buffer, 0, KEY_READ | KEY_WOW64_32KEY, &key) != 0 do
            return ""
        defer discard RegCloseKey(key)

        let valueName = Utf16.toZeroTerminated("InstallDir")
        var directory: [MAX_PATH + 1] u16
        var size      = cast(u32, (MAX_PATH * #sizeof(u16)))
        var kind:      u32
        if RegQueryValueExW(key, valueName.buffer, null, &kind, cast(*u8, directory.buffer), &size) != 0 or kind != REG_SZ do
            return ""
        let root = stringFromWide(directory.buffer)
        if not Path.isRooted(root) do
            return ""
        let path = Path.combine(root, "bin", WinFspDllName)
        return File.exists(path) ? path : String{}
    }

    // Windows Installer owns the elevation and waits for the user's answer in its own UI.
    func install() fail
    {
        if Env.isSandboxed() do
            fail volumeError(.DriverUnavailable)
        if not installedLibrary().isEmpty() do
            return

        let executable = try Env.Process.currentExecutablePath()
        let directory  = unwrap Path.directoryName(executable)
        let package    = installerPackagePath(directory)
        if not File.exists(package) do
            fail volumeError(.DriverUnavailable)

        var system: [MAX_PATH] u16
        try SHGetSpecialFolderPathW(null, system.buffer, CSIDL_SYSTEM, FALSE)
        let installer = Path.combine(stringFromWide(system.buffer), "msiexec.exe")
        var process   = try Env.startProcess({fileName: installer, arguments: ["/i", package, "/norestart"],
                                              workingDirectory: directory, consoleWindow: false})
        let status = try process.waitForExit()

        // These installer results are distinct from failure. A requested restart belongs to Windows.
        const UserCanceled   = 1602
        const RestartStarted = 1641
        const RestartNeeded  = 3010
        switch status
        {
        case UserCanceled:
            fail volumeError(.Canceled)

        case RestartStarted, RestartNeeded:
            fail volumeError(.DriverRestartRequired)

        case 0:
            if installedLibrary().isEmpty() do
                fail volumeError(.DriverUnavailable)

        default:
            fail volumeError(.DriverUnavailable, cast #bit (u32, status))
        }
    }
}
