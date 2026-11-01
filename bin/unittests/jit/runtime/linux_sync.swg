#global if #os == Swag.TargetOs.Linux
#global private

#run
{
    var mutex: Swag.Mutex
    Swag.assert(mutex.tryLock())
    Swag.assert(not mutex.tryLock())
    mutex.unlock()
    mutex.lock()
    var condition: Swag.Condition
    Swag.assert(not condition.waitFor(&mutex, 0))
    Swag.assert(not mutex.tryLock())
    Swag.assert(not condition.waitFor(&mutex, 2))
    Swag.assert(not mutex.tryLock())
    mutex.unlock()

    var readers: Swag.RWLock
    Swag.assert(readers.tryLockShared())
    Swag.assert(readers.tryLockShared())
    Swag.assert(not readers.tryLock())
    readers.unlockShared()
    Swag.assert(not readers.tryLock())
    readers.unlockShared()
    Swag.assert(readers.tryLock())
    Swag.assert(not readers.tryLockShared())
    readers.unlock()
}
