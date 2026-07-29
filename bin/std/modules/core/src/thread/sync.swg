#global namespace Sync

// Performs the scoped lock operation.
#[Swag.Mixin]
public func(T) scopedLock(syncObj: *T)
{
    syncObj.lock()
    defer syncObj.unlock()
}

// Performs the shared lock operation.
#[Swag.Mixin]
public func(T) sharedLock(syncObj: *T)
{
    syncObj.lockShared()
    defer syncObj.unlockShared()
}
