#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

// One bounded archive per compiler avoids opening a file for
// every source/function. Each consumer validates its own record before reuse.
class CompilerCacheStore
{
public:
    struct Record
    {
        std::shared_ptr<const void> owner;
        ByteView                    bytes;
        explicit                    operator bool() const { return owner != nullptr; }
    };

    ~CompilerCacheStore();
    Record                     read(const Utf8& key) const;
    void                       write(const Utf8& key, ByteArray bytes);
    static CompilerCacheStore& get(bool rebuild);
    static void                invalidateAll();
    static void                flushAll();

private:
    using Entries = std::unordered_map<Utf8, Record>;
    struct Archive
    {
        Record                record;
        std::vector<uint32_t> offsets;

        Record         read(const Utf8& key) const;
        void           appendTo(Entries& out) const;
        static Archive decode(Record record);
    };

    explicit CompilerCacheStore(bool rebuild);
    Archive load() const;
    void    invalidateOnce();
    void    flush();

    fs::path                  path_;
    mutable std::shared_mutex mutex_;
    Archive                   archive_;
    Entries                   pending_;
    bool                      rebuilding_ = false;
    bool                      replace_    = false;
};

SWC_END_NAMESPACE();
