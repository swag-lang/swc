#pragma once

SWC_BEGIN_NAMESPACE();

namespace Os
{
    // The mapping retains its file generation across atomic replacement. Readers
    // can keep a shared owner while a cache publisher replaces the directory entry.
    class ReadOnlyFileMapping
    {
    public:
        ReadOnlyFileMapping()                                      = default;
        ReadOnlyFileMapping(const ReadOnlyFileMapping&)            = delete;
        ReadOnlyFileMapping& operator=(const ReadOnlyFileMapping&) = delete;
        ~ReadOnlyFileMapping();
        bool                       open(const fs::path& path, uint64_t maxBytes);
        std::span<const std::byte> bytes() const { return {view_, size_}; }

    private:
        void*            file_    = nullptr;
        void*            mapping_ = nullptr;
        const std::byte* view_    = nullptr;
        size_t           size_    = 0;
    };
}

SWC_END_NAMESPACE();
