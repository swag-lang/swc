#global if #os == Swag.TargetOs.Linux

using Core

impl VolumeStorage
{
    // POSIX FileShare flags cannot exclude another writer. Keep an advisory inode lock on
    // the stream itself, before reading metadata; moving a hidden view keeps the same lock.
    // Multiple readers may coexist, but writable opens exclude every other Vault handle.
    mtd acquireLock(readOnly: bool) fail
    {
        let operation = (readOnly ? Linux.LOCK_SH : Linux.LOCK_EX) | Linux.LOCK_NB
        if Linux.flock(try .stream.nativeFileDescriptor(), operation) != 0 do
            fail volumeError(.AccessDenied, cast(u64, Linux.errno()))
    }
}
