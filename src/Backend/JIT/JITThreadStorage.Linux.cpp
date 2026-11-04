#include "pch.h"
#include "Backend/JIT/JITThreadStorage.Linux.h"

#ifdef __linux__
#include "Support/Report/Assert.h"
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    using OwnsCallback = std::function<bool(const void*)>;

    struct Key
    {
        pthread_key_t slot = 0;
        void (*callback)(void*) = nullptr;
        uint32_t activeCalls = 0;
        bool allocated = false;
        bool retiring = false;
    };

    struct Value
    {
        std::shared_ptr<Key> key;
        void* data = nullptr;
    };

    struct ThreadValues
    {
        std::vector<Value> values;
    };

    struct Registry
    {
        std::mutex mutex;
        std::condition_variable completed;
        pthread_key_t anchor = 0;
        bool anchorReady = false;
        std::vector<std::shared_ptr<Key>> keys;
        std::vector<std::unique_ptr<ThreadValues>> threads;
        std::vector<const OwnsCallback*> retiringOwners;
    };

    Registry& registry()
    {
        // pthread may run the host destructor after ordinary static destructors.
        // Only this process anchor survives; retired keys and exited threads do not.
        static Registry* instance = new Registry;
        return *instance;
    }

    void pruneKeys(Registry& state)
    {
        std::erase_if(state.keys, [](const auto& key) { return !key->allocated && !key->activeCalls; });
    }

    std::shared_ptr<Key> findKey(const Registry& state, pthread_key_t slot)
    {
        for (const auto& key : state.keys)
            if (key->allocated && key->slot == slot)
                return key;
        return {};
    }

    void invokeCleanup(const Value& value)
    {
        struct CompleteCall
        {
            std::shared_ptr<Key> key;
            ~CompleteCall()
            {
                Registry& state = registry();
                {
                    const std::scoped_lock lock(state.mutex);
                    SWC_ASSERT(key->activeCalls);
                    --key->activeCalls;
                    pruneKeys(state);
                }
                state.completed.notify_all();
            }
        } completed{value.key};
        bool invoke = false;
        {
            const std::scoped_lock lock(registry().mutex);
            invoke = value.key->allocated;
        }
        // An earlier destructor may explicitly delete another pending key.
        if (invoke)
            value.key->callback(value.data);
    }

    void retireThread(void* pointer)
    {
        auto* thread = static_cast<ThreadValues*>(pointer);
        Registry& state = registry();
        // Reentrant sets during a callback join this same thread record. The native
        // keys contain raw user values, so unwrapped C readers retain POSIX semantics.
        SWC_FORCE_ASSERT(pthread_setspecific(state.anchor, thread) == 0);
        const long iterations = sysconf(_SC_THREAD_DESTRUCTOR_ITERATIONS);
        SWC_FORCE_ASSERT(iterations > 0);
        for (long iteration = 0; iteration < iterations; ++iteration)
        {
            std::vector<Value> pending;
            {
                const std::scoped_lock lock(state.mutex);
                pending.swap(thread->values);
                for (Value& value : pending)
                {
                    if (!value.key->allocated || value.key->retiring)
                    {
                        value.data = nullptr;
                        continue;
                    }
                    SWC_FORCE_ASSERT(pthread_setspecific(value.key->slot, nullptr) == 0);
                    ++value.key->activeCalls;
                }
            }
            for (const Value& value : pending)
                if (value.data)
                    invokeCleanup(value);
            const std::scoped_lock lock(state.mutex);
            if (thread->values.empty())
                break;
        }
        const std::scoped_lock lock(state.mutex);
        SWC_FORCE_ASSERT(pthread_setspecific(state.anchor, nullptr) == 0);
        std::erase_if(state.threads, [thread](const auto& entry) { return entry.get() == thread; });
    }

    int currentThread(ThreadValues*& result, Registry& state)
    {
        result = static_cast<ThreadValues*>(pthread_getspecific(state.anchor));
        if (result)
            return 0;
        auto thread = std::make_unique<ThreadValues>();
        result = thread.get();
        state.threads.push_back(std::move(thread));
        const int status = pthread_setspecific(state.anchor, result);
        if (status)
        {
            state.threads.pop_back();
            result = nullptr;
        }
        return status;
    }
}

int JITThreadStorage::create(pthread_key_t* slot, void (*callback)(void*))
{
    if (!callback)
        return pthread_key_create(slot, nullptr);
    try
    {
        Registry& state = registry();
        const std::scoped_lock lock(state.mutex);
        for (const OwnsCallback* owner : state.retiringOwners)
            if ((*owner)(reinterpret_cast<const void*>(callback)))
                return EINVAL;
        if (!state.anchorReady)
        {
            const int status = pthread_key_create(&state.anchor, &retireThread);
            if (status)
                return status;
            state.anchorReady = true;
        }
        auto key = std::make_shared<Key>();
        key->callback = callback;
        state.keys.push_back(key);
        // The only kernel callback is the process-owned anchor, never generated code.
        const int status = pthread_key_create(&key->slot, nullptr);
        if (status)
        {
            state.keys.pop_back();
            return status;
        }
        key->allocated = true;
        *slot = key->slot;
        return 0;
    }
    catch (const std::bad_alloc&)
    {
        return ENOMEM;
    }
}

int JITThreadStorage::erase(pthread_key_t slot)
{
    Registry& state = registry();
    const std::scoped_lock lock(state.mutex);
    const auto key = findKey(state, slot);
    const int status = pthread_key_delete(slot);
    if (!key || status)
        return status;
    // Explicit pthread_key_delete never calls destructors. Keep an already active
    // callback registered until it finishes so compiler teardown can still wait for it.
    key->allocated = false;
    key->retiring = true;
    for (const auto& thread : state.threads)
        std::erase_if(thread->values, [&](const Value& value) { return value.key == key; });
    pruneKeys(state);
    return 0;
}

int JITThreadStorage::set(pthread_key_t slot, const void* data)
{
    try
    {
        Registry& state = registry();
        const std::scoped_lock lock(state.mutex);
        const auto key = findKey(state, slot);
        if (!key)
            return pthread_setspecific(slot, data);
        if (key->retiring)
            return EINVAL;
        auto* thread = static_cast<ThreadValues*>(pthread_getspecific(state.anchor));
        if (!data)
        {
            const int status = pthread_setspecific(slot, nullptr);
            if (!status && thread)
                std::erase_if(thread->values, [&](const Value& value) { return value.key == key; });
            return status;
        }
        const int threadStatus = currentThread(thread, state);
        if (threadStatus)
            return threadStatus;
        auto entry = std::ranges::find_if(thread->values, [&](const Value& value) { return value.key == key; });
        const bool inserted = entry == thread->values.end();
        if (inserted)
        {
            thread->values.push_back({key, nullptr});
            entry = thread->values.end() - 1;
        }
        const int status = pthread_setspecific(slot, data);
        if (!status)
            entry->data = const_cast<void*>(data);
        else if (inserted)
            thread->values.pop_back();
        return status;
    }
    catch (const std::bad_alloc&)
    {
        return ENOMEM;
    }
}

void JITThreadStorage::release(const OwnsCallback& ownsCallback)
{
    Registry& state = registry();
    struct RetiringOwner
    {
        const OwnsCallback* owner;
        ~RetiringOwner()
        {
            Registry& state = registry();
            const std::scoped_lock lock(state.mutex);
            std::erase(state.retiringOwners, owner);
        }
    } retiring{&ownsCallback};
    std::vector<std::shared_ptr<Key>> selected;
    std::vector<Value> pending;
    {
        const std::scoped_lock lock(state.mutex);
        state.retiringOwners.push_back(&ownsCallback);
        for (const auto& key : state.keys)
        {
            if (!ownsCallback(reinterpret_cast<const void*>(key->callback)))
                continue;
            key->retiring = true;
            selected.push_back(key);
        }
        ThreadValues* current = state.anchorReady ? static_cast<ThreadValues*>(pthread_getspecific(state.anchor)) : nullptr;
        for (const auto& thread : state.threads)
        {
            std::erase_if(thread->values, [&](const Value& value) {
                if (std::ranges::find(selected, value.key) == selected.end())
                    return false;
                pending.push_back(value);
                ++value.key->activeCalls;
                if (thread.get() == current && value.key->allocated)
                    SWC_FORCE_ASSERT(pthread_setspecific(value.key->slot, nullptr) == 0);
                return true;
            });
        }
    }
    // Claim values under the lock, then run arbitrary cleanup outside it. A thread
    // exit and compiler teardown cannot claim the same value. Retiring slots reject
    // rearming, and retiring owners cannot register another callback into dead code.
    for (const Value& value : pending)
        invokeCleanup(value);
    {
        std::unique_lock lock(state.mutex);
        state.completed.wait(lock, [&] { return std::ranges::all_of(selected, [](const auto& key) { return key->activeCalls == 0; }); });
        for (const auto& key : selected)
        {
            if (!key->allocated)
                continue;
            SWC_FORCE_ASSERT(pthread_key_delete(key->slot) == 0);
            key->allocated = false;
        }
        pruneKeys(state);
    }
}

SWC_END_NAMESPACE();
#endif
