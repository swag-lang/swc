#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

#ifdef __linux__
#include <pthread.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

uint64_t Os::tlsAlloc()
{
    pthread_key_t key;
    SWC_FORCE_ASSERT(pthread_key_create(&key, nullptr) == 0);
    return key;
}

void Os::tlsSetValue(const uint64_t id, void* value)
{
    SWC_FORCE_ASSERT(id <= std::numeric_limits<pthread_key_t>::max());
    SWC_FORCE_ASSERT(pthread_setspecific(static_cast<pthread_key_t>(id), value) == 0);
}

void* Os::tlsGetValue(const uint64_t id)
{
    SWC_FORCE_ASSERT(id <= std::numeric_limits<pthread_key_t>::max());
    return pthread_getspecific(static_cast<pthread_key_t>(id));
}

uint32_t Os::tlsSlotsInUse()
{
    const long maximum = sysconf(_SC_THREAD_KEYS_MAX);
    SWC_FORCE_ASSERT(maximum > 0 && static_cast<uint64_t>(maximum) <= std::numeric_limits<uint32_t>::max());
    std::vector<pthread_key_t> borrowed;
    borrowed.reserve(static_cast<size_t>(maximum));
    pthread_key_t key;
    int           result;
    while ((result = pthread_key_create(&key, nullptr)) == 0)
        borrowed.push_back(key);
    for (const auto borrowedKey : borrowed)
        pthread_key_delete(borrowedKey);
    SWC_FORCE_ASSERT(result == EAGAIN);
    return static_cast<uint32_t>(maximum - borrowed.size());
}

SWC_END_NAMESPACE();
#endif
