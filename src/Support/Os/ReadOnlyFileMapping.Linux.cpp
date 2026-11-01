#include "pch.h"
#include "Support/Os/ReadOnlyFileMapping.h"
#include "Support/Report/Assert.h"

#ifdef __linux__
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

Os::ReadOnlyFileMapping::~ReadOnlyFileMapping()
{
    if (view_)
        munmap(const_cast<std::byte*>(view_), size_);
}

bool Os::ReadOnlyFileMapping::open(const fs::path& path, const uint64_t maxBytes)
{
    SWC_ASSERT(!view_);

    // O_NONBLOCK keeps a FIFO or device supplied as a cache path from blocking before
    // fstat can reject it. The mapping owns the inode after the descriptor is closed.
    const int file = ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (file < 0)
        return false;

    struct stat info{};
    if (fstat(file, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size <= 0 || static_cast<uint64_t>(info.st_size) > maxBytes || static_cast<uint64_t>(info.st_size) > std::numeric_limits<size_t>::max())
    {
        close(file);
        return false;
    }

    const size_t size = static_cast<size_t>(info.st_size);
    void*        view = mmap(nullptr, size, PROT_READ, MAP_PRIVATE, file, 0);
    close(file);
    if (view == MAP_FAILED)
        return false;

    view_ = static_cast<const std::byte*>(view);
    size_ = size;
    return true;
}

SWC_END_NAMESPACE();
#endif
