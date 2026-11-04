#include "pch.h"

#if SWC_HAS_UNITTEST && defined(__linux__)
#include "Backend/JIT/JITThreadStorage.Linux.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct Slot
    {
        pthread_key_t key = 0;
        bool allocated = false;
        ~Slot() { if (allocated) JITThreadStorage::erase(key); }
        int create(void (*callback)(void*))
        {
            const int status = JITThreadStorage::create(&key, callback);
            allocated = status == 0;
            return status;
        }
        int erase()
        {
            const int status = JITThreadStorage::erase(key);
            if (!status)
                allocated = false;
            return status;
        }
    };

    void countCleanup(void* value)
    {
        ++*static_cast<std::atomic<uint32_t>*>(value);
    }

    struct RearmState
    {
        Slot* slot = nullptr;
        uint32_t calls = 0;
        bool correct = true;
    };

    void rearmCleanup(void* value)
    {
        auto& state = *static_cast<RearmState*>(value);
        state.correct &= pthread_getspecific(state.slot->key) == nullptr;
        if (++state.calls < 3)
            state.correct &= JITThreadStorage::set(state.slot->key, value) == 0;
        else
            state.correct &= state.slot->erase() == 0;
    }

    struct RetireState
    {
        Slot* slot = nullptr;
        std::atomic<uint32_t> calls = 0;
        int rearmStatus = 0;
        int createStatus = 0;
    };

    void retiringCleanup(void* value)
    {
        auto& state = *static_cast<RetireState*>(value);
        ++state.calls;
        state.rearmStatus = JITThreadStorage::set(state.slot->key, value);
        Slot replacement;
        state.createStatus = replacement.create(&retiringCleanup);
    }

    struct BlockingState
    {
        Slot* slot = nullptr;
        Slot replacement;
        std::atomic<uint32_t> replacementCalls = 0;
        bool reusedKey = false;
        std::mutex mutex;
        std::condition_variable changed;
        bool setupFinished = false;
        bool installed = false;
        bool entered = false;
        bool deleted = false;
        bool ownerSeen = false;
        bool allowExit = false;
        bool releaseFinished = false;
        uint32_t calls = 0;
    };

    void blockingCleanup(void* value)
    {
        auto& state = *static_cast<BlockingState*>(value);
        // Removing the native key must not hide an in-flight generated callback
        // from the owner waiting to unmap its code.
        const bool deleted = state.slot->erase() == 0;
        const bool created = state.replacement.create(&countCleanup) == 0;
        if (created)
            state.reusedKey = state.replacement.key == state.slot->key && JITThreadStorage::set(state.replacement.key, &state.replacementCalls) == 0;
        std::unique_lock lock(state.mutex);
        state.deleted = deleted;
        state.entered = true;
        state.changed.notify_all();
        state.changed.wait(lock, [&] { return state.allowExit; });
        ++state.calls;
    }
}

SWC_TEST_BEGIN(JIT_ThreadStoragePreservesRawValuesAndExplicitDeletion)
{
    std::atomic<uint32_t> calls = 0;
    Slot slot;
    if (slot.create(&countCleanup) || JITThreadStorage::set(slot.key, &calls) || pthread_getspecific(slot.key) != &calls)
        return Result::Error;
    JITThreadStorage::release([](const void*) { return false; });
    if (pthread_getspecific(slot.key) != &calls || calls != 0)
        return Result::Error;
    if (JITThreadStorage::set(slot.key, nullptr) || pthread_getspecific(slot.key) || slot.erase() || calls != 0)
        return Result::Error;
    if (slot.create(&countCleanup) || JITThreadStorage::set(slot.key, &calls) || slot.erase() || calls != 0)
        return Result::Error;
    if (slot.create(nullptr) || JITThreadStorage::set(slot.key, &calls) || pthread_getspecific(slot.key) != &calls)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_ThreadStorageRunsRearmedExitCallbacks)
{
    Slot slot;
    if (slot.create(&rearmCleanup))
        return Result::Error;
    RearmState state{.slot = &slot};
    bool installed = false;
    std::jthread worker([&] { installed = JITThreadStorage::set(slot.key, &state) == 0; });
    worker.join();
    return installed && state.correct && state.calls == 3 && !slot.allocated ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_ThreadStorageRetirementDrainsLiveThreadsOnce)
{
    Slot slot;
    if (slot.create(&retiringCleanup))
        return Result::Error;
    RetireState state{.slot = &slot};
    std::latch installed(1), leave(1);
    bool ready = false;
    std::jthread worker([&] {
        ready = JITThreadStorage::set(slot.key, &state) == 0;
        installed.count_down();
        leave.wait();
    });
    installed.wait();
    JITThreadStorage::release([](const void* callback) { return callback == reinterpret_cast<const void*>(&retiringCleanup); });
    slot.allocated = false;
    leave.count_down();
    worker.join();
    return ready && state.calls == 1 && state.rearmStatus == EINVAL && state.createStatus == EINVAL ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_ThreadStorageRetirementWaitsForDeletedActiveCallbacks)
{
    Slot slot;
    if (slot.create(&blockingCleanup))
        return Result::Error;
    BlockingState state{.slot = &slot};
    std::jthread worker([&] {
        const bool installed = JITThreadStorage::set(slot.key, &state) == 0;
        const std::scoped_lock lock(state.mutex);
        state.installed = installed;
        state.setupFinished = true;
        state.changed.notify_all();
    });
    bool entered = false;
    {
        std::unique_lock lock(state.mutex);
        entered = state.changed.wait_for(lock, std::chrono::seconds(2), [&] { return state.entered || (state.setupFinished && !state.installed); }) && state.entered;
    }
    std::jthread releaser([&] {
        JITThreadStorage::release([&](const void* callback) {
            if (callback != reinterpret_cast<const void*>(&blockingCleanup))
                return false;
            const std::scoped_lock lock(state.mutex);
            state.ownerSeen = true;
            state.changed.notify_all();
            return true;
        });
        const std::scoped_lock lock(state.mutex);
        state.releaseFinished = true;
        state.changed.notify_all();
    });
    bool waited = false;
    {
        std::unique_lock lock(state.mutex);
        const bool started = state.changed.wait_for(lock, std::chrono::seconds(2), [&] { return state.ownerSeen || state.releaseFinished; });
        waited = started && state.ownerSeen && !state.changed.wait_for(lock, std::chrono::milliseconds(30), [&] { return state.releaseFinished; });
        state.allowExit = true;
        state.changed.notify_all();
    }
    worker.join();
    releaser.join();
    return entered && waited && state.installed && state.deleted && state.calls == 1 && state.releaseFinished && state.reusedKey && state.replacementCalls == 1 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
