#global namespace Sync

// Locks `syncObj` exclusively until the end of the calling scope.
#[Swag.Mixin]
public func(T) scopedLock(syncObj: *T)
{
    syncObj.lock()
    defer syncObj.unlock()
}

// Locks `syncObj` for shared access until the end of the calling scope.
#[Swag.Mixin]
public func(T) sharedLock(syncObj: *T)
{
    syncObj.lockShared()
    defer syncObj.unlockShared()
}
