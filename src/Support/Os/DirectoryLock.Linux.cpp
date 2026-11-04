#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

#ifdef __linux__
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

Os::DirectoryLock::~DirectoryLock()
{
    if (directory_ >= 0)
        close(directory_);
}

bool Os::DirectoryLock::lock(Utf8& outBecause, const fs::path& directory)
{
    SWC_ASSERT(directory_ < 0);
    outBecause.clear();
    while (true)
    {
        const int descriptor = open(directory.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (descriptor < 0)
        {
            outBecause = systemError();
            return false;
        }

        int result;
        do
            result = flock(descriptor, LOCK_EX);
        while (result < 0 && errno == EINTR);

        struct stat locked{};
        struct stat current{};
        if (result < 0 || fstat(descriptor, &locked) != 0 || stat(directory.c_str(), &current) != 0)
        {
            outBecause = systemError();
            close(descriptor);
            return false;
        }

        // A waiter can hold the inode of a directory that was renamed/replaced while
        // it slept. Acquire the current generation before using path-based cache APIs.
        if (locked.st_dev != current.st_dev || locked.st_ino != current.st_ino)
        {
            close(descriptor);
            continue;
        }

        directory_ = descriptor;
        return true;
    }
}

SWC_END_NAMESPACE();
#endif
