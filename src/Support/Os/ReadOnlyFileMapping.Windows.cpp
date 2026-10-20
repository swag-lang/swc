#include "pch.h"
#include "Support/Os/ReadOnlyFileMapping.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

#ifdef _WIN32

SWC_BEGIN_NAMESPACE();

Os::ReadOnlyFileMapping::~ReadOnlyFileMapping()
{
    if (view_)
        UnmapViewOfFile(view_);
    if (mapping_)
        CloseHandle(mapping_);
    if (file_)
        CloseHandle(file_);
}

bool Os::ReadOnlyFileMapping::open(const fs::path& path, const uint64_t maxBytes)
{
    SWC_ASSERT(!file_ && !mapping_ && !view_);
    const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;
    LARGE_INTEGER size;
    if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || static_cast<uint64_t>(size.QuadPart) > maxBytes)
    {
        CloseHandle(file);
        return false;
    }
    const HANDLE mapping = CreateFileMappingW(file, nullptr, PAGE_READONLY, 0, 0, nullptr);
    if (!mapping)
    {
        CloseHandle(file);
        return false;
    }
    const auto* view = static_cast<const std::byte*>(MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0));
    if (!view)
    {
        CloseHandle(mapping);
        CloseHandle(file);
        return false;
    }
    file_    = file;
    mapping_ = mapping;
    view_    = view;
    size_    = static_cast<size_t>(size.QuadPart);
    return true;
}

SWC_END_NAMESPACE();

#endif
