#global namespace Sync

#[Swag.Mixin]
public func(T) scopedLock(syncObj: #nonull *T)
{
    syncObj.lock()
    defer syncObj.unlock()
}

#[Swag.Mixin]
public func(T) sharedLock(syncObj: #nonull *T)
{
    syncObj.lockShared()
    defer syncObj.unlockShared()
}
