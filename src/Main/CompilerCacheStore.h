#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

// Hash-partitioned archives retain independent module working sets and publish
// only dirty partitions. Each consumer validates its own record before reuse.
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
        static Archive decode(Record record);
    };

    static constexpr size_t K_SHARD_COUNT = 16;
    struct Shard
    {
        std::once_flag    loaded;
        std::shared_mutex mutex;
        Archive           archive;
        Entries           pending;
        bool              replace = false;
    };

    static std::vector<EntryView> mergeEntries(const Archive& archive, const Entries& pending);
    static bool                   measureExtent(const std::vector<EntryView>& entries, size_t& extent);

    explicit CompilerCacheStore(bool rebuild);
    explicit CompilerCacheStore(fs::path directory);
    static Archive load(const fs::path& path);
    fs::path       shardPath(size_t index) const;
    Shard&         shardFor(const Utf8& key) const;
    void           invalidateOnce();
    void           flush();
    void           flushShard(size_t index);

    fs::path                                 directory_;
    mutable std::array<Shard, K_SHARD_COUNT> shards_;
    std::once_flag                           invalidated_;
};

SWC_END_NAMESPACE();
