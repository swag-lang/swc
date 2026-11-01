#pragma once

#ifdef __linux__
#include <pthread.h>

SWC_BEGIN_NAMESPACE();

namespace JITThreadStorage
{
    int create(pthread_key_t* key, void (*callback)(void*));
    int erase(pthread_key_t key);
    int set(pthread_key_t key, const void* value);
    void release(const std::function<bool(const void*)>& ownsCallback);
}

SWC_END_NAMESPACE();
#endif
