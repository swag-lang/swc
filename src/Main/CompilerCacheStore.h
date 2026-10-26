#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

// Every publication adds one immutable segment holding only the records it produced, so
// a build pays for what it adds and never rewrites what earlier builds stored. Readers
// consult every segment; once segments accumulate, a publication folds the small ones
// together. Each consumer validates its own record before reuse.
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
    friend struct CompilerCacheStoreTestAccess;

    using Entries = std::unordered_map<Utf8, Record>;
    struct EntryView
    {
        std::string_view key;
        ByteView         bytes;
    };

    struct Archive
    {
        Record                record;
        std::vector<uint32_t> offsets;

        Record         read(const Utf8& key) const;
        EntryView      entry(size_t index) const;
        static Archive decode(Record record);
    };

    struct Segment
    {
        fs::path path;
        Archive  archive;
    };

    static constexpr size_t K_PENDING_SHARDS = 16;
    struct PendingShard
    {
        std::mutex mutex;
        Entries    entries;
    };

    static std::vector<EntryView> mergeSegments(std::span<const Archive* const> oldestFirst);
    static bool                   measureExtent(const std::vector<EntryView>& entries, size_t& extent, size_t limit);
    static Archive                load(const fs::path& path);
    static bool                   publish(Archive& outArchive, const fs::path& path, const std::vector<EntryView>& entries);

    explicit CompilerCacheStore(bool rebuild);
    explicit CompilerCacheStore(fs::path directory);
    std::vector<fs::path> listSegments() const;
    void                  ensureLoaded() const;
    PendingShard&         pendingFor(const Utf8& key) const;
    void                  invalidateOnce();
    void                  flush();
    void                  compact() const;

    fs::path                                           directory_;
    mutable std::once_flag                             loaded_;
    mutable std::shared_mutex                          segmentsMutex_;
    mutable std::vector<Segment>                       segments_;
    mutable std::array<PendingShard, K_PENDING_SHARDS> pending_;
    std::mutex                                         flushMutex_;
    std::once_flag                                     invalidated_;
    std::atomic<bool>                                  replace_ = false;
};

SWC_END_NAMESPACE();
