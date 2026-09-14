#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

namespace Os
{
    // Coordinates processes accessing the same directory, including through path aliases.
    // The lock does not create a file, so readers can consume read-only installed APIs.
    class DirectoryLock
    {
    public:
        DirectoryLock() = default;
        ~DirectoryLock();
        DirectoryLock(const DirectoryLock&)            = delete;
        DirectoryLock& operator=(const DirectoryLock&) = delete;

        bool lock(Utf8& outBecause, const fs::path& directory);

    private:
        void* directory_ = nullptr;
        void* mutex_     = nullptr;
    };
}

SWC_END_NAMESPACE();
