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
        // Opens the container and exposes it on `mountPoint`.
        //
        // `readOnly` travels no further than [[Volume.open]] and the volume parameters WinFsp is
        // given: the drive is what carries the state, so nothing here has to remember it.
        mtd open(path: string, password: const [..] u8, mountPoint: string, readOnly = false) fail
        {
            .volume     = Volume.open(path, password, readOnly)
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

                if .volume.dirty and !.volume.readOnly do
                    .volume.commit()
            }
        }

        mtd opDrop() { discard catch .close() }
    }
}
