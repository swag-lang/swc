#global if WINDOWS

using Core

namespace WinFsp
{
    #[Swag.NoCopy]
    struct MountedVolume
    {
        volume:     Volume
        volumeOpen: bool
        mount:      WinFspMount
    }

    impl MountedVolume
    {
        mtd open(path: string, password: const [..] u8, mountPoint: string) fail
        {
            .volume     = Volume.open(path, password)
            .volumeOpen = true
            traceWinFspStage("calling WinFspMount.start from MountedVolume.open")
            discard catch .mount.start(&.volume, mountPoint) as mountError
            if mountError != null
            {
                discard catch .close()
                fail mountError
            }

            traceWinFspStage("WinFspMount.start returned to MountedVolume.open")
            traceWinFspStage("MountedVolume initialized in place")
        }

        mtd close() fail
        {
            .mount.stop()
            if .volumeOpen
            {
                defer
                {
                    .volume.close()
                    .volumeOpen = false
                }

                if .volume.dirty do
                    .volume.commit()
            }
        }

        mtd opDrop() { discard catch .close() }
    }
}
