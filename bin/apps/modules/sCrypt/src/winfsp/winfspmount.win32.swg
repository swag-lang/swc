#global if WINDOWS

using Core

namespace WinFsp
{
    // Bits of `FSP_FSCTL_VOLUME_PARAMS.Flags`, which WinFsp declares as a bitfield and therefore
    // gives no names an importer can use. The positions are the declaration order of that
    // bitfield; they are part of the driver ABI and move only with a new WinFsp version.
    const VolumeCasePreservedNames  = 1'u32 << 1
    const VolumeUnicodeOnDisk       = 1'u32 << 2
    const VolumePersistentAcls      = 1'u32 << 3
    const VolumeReadOnly            = 1'u32 << 9
    const VolumePostCleanupModified = 1'u32 << 10
    const VolumePassDirectoryName   = 1'u32 << 13

    #[Swag.NoCopy]
    struct WinFspMount
    {
        fileSystem:   #null *FspFileSystem
        context:      #null *NativeMountContext
        holdsRuntime: bool     // Whether this mount counts towards `g_WinFsp.mountCount`.
    }

    impl WinFspMount
    {
        mtd start(volume: *Volume, mountPoint: string) fail
        {
            try loadWinFsp()

            // The reference is taken the moment the runtime is up, before anything that can
            // fail: every failure below unwinds through `stop`, and that is what releases it.
            .holdsRuntime       = true
            g_WinFsp.mountCount += 1

            discard catch registerPortableWinFsp() as registerError
            if registerError != null
            {
                .stop()
                fail registerError
            }

            traceWinFspStage("portable driver registration complete")

            if !g_FspInterfaceReady
            {
                traceWinFspStage("building FSP_FILE_SYSTEM_INTERFACE")
                g_FspInterface      = makeInterface()
                g_FspInterfaceReady = true
                traceWinFspStage("FSP_FILE_SYSTEM_INTERFACE ready")
            }

            .context        = Memory.new'NativeMountContext()
            .context.volume = volume
            let sddl = Utf16.toZeroTerminated("O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FA;;;WD)")
            if !ConvertStringSecurityDescriptorToSecurityDescriptorW(@dataof(sddl), SddlRevisionOne, &.context.defaultSecurity, null)
            {
                .stop()
                failWith("Windows could not create the volume security descriptor.")
            }

            traceWinFspStage("default security descriptor created")

            traceWinFspStage("initializing FSP_FSCTL_VOLUME_PARAMS")
            var params: FspVolumeParams
            params.version                  = cast(u16) #sizeof(params)
            params.sectorSize               = 512
            params.sectorsPerAllocationUnit = 8
            params.maxComponentLength       = 255
            traceWinFspStage("volume geometry initialized")
            params.volumeCreationTime = volumeTimeNow()
            params.volumeSerialNumber = volumeSerialNumber(params.volumeCreationTime)
            traceWinFspStage("volume identity initialized")
            params.fileInfoTimeout = 1000
            params.flags           = VolumeCasePreservedNames | VolumeUnicodeOnDisk | VolumePersistentAcls | VolumePostCleanupModified | VolumePassDirectoryName

            // Saying it here is what makes Explorer, and every program that asks Windows before
            // it tries, treat the drive as read only. The volume refuses the write on its own
            // too — see [[Volume.open]] — but a refusal that arrives as a failed write is a
            // program reporting an error, where this one is a drive that never offered.
            if volume.readOnly do
                params.flags |= VolumeReadOnly
            traceWinFspStage("volume flags initialized")
            let fileSystemName = Utf16.toZeroTerminated("sCrypt")
            traceWinFspStage("copying filesystem name")
            @memcpy(@dataof(params.fileSystemName), @dataof(fileSystemName), @countof(fileSystemName) * #sizeof(u16))
            traceWinFspStage("FSP_FSCTL_VOLUME_PARAMS ready")

            let deviceName = Utf16.toZeroTerminated(WinFspDiskName)
            let fsCreate   = g_WinFsp.fsCreate
            traceWinFspStage("calling FspFileSystemCreate")
            let createStatus = fsCreate(@dataof(deviceName), &params, &g_FspInterface, &.fileSystem)
            traceWinFspStage(Format.toString("FspFileSystemCreate returned %{X}", cast(u32) createStatus))
            if createStatus != StatusSuccess
            {
                .stop()
                failWith(Format.toString("WinFsp could not create the volume (NTSTATUS %{X}).", cast(u32) createStatus))
            }

            let fileSystem = .fileSystem!
            fileSystem.userContext = .context
            (g_WinFsp.setGuard)(fileSystem, 1)
            let mountPoint16 = Utf16.toZeroTerminated(mountPoint)
            traceWinFspStage("calling FspFileSystemSetMountPoint")
            var status = (g_WinFsp.setMountPoint)(fileSystem, @dataof(mountPoint16))
            traceWinFspStage(Format.toString("FspFileSystemSetMountPoint returned %{X}", cast(u32) status))
            if status == StatusSuccess
            {
                traceWinFspStage("calling FspFileSystemStartDispatcher")
                status = (g_WinFsp.startDispatcher)(fileSystem, 0)
                traceWinFspStage(Format.toString("FspFileSystemStartDispatcher returned %{X}", cast(u32) status))
            }

            if status != StatusSuccess
            {
                .stop()
                failWith(Format.toString("WinFsp could not mount drive % (NTSTATUS %{X}).", mountPoint, cast(u32) status))
            }

            traceWinFspStage("WinFspMount initialized in place")
        }

        mtd stop()
        {
            if .fileSystem
            {
                @assert(.fileSystem != null)
                (g_WinFsp.stopDispatcher)(.fileSystem)
                (g_WinFsp.removeMountPoint)(.fileSystem)
                (g_WinFsp.destroy)(.fileSystem)
                .fileSystem = null
            }

            if .context
            {
                if .context.defaultSecurity do
                    discard LocalFree(.context.defaultSecurity)
                Memory.delete(.context!)
                .context = null
            }

            // The library, the driver registration and the staged runtime tree are shared, so
            // only the mount that turns the count to zero may take them down. Unloading them
            // under a drive that is still exposed would take that drive with them.
            if .holdsRuntime
            {
                .holdsRuntime = false
                Debug.assert(g_WinFsp.mountCount != 0)
                g_WinFsp.mountCount -= 1
                if !g_WinFsp.mountCount do
                    unloadWinFsp()
            }
        }

        mtd opDrop() { .stop() }
    }
}
