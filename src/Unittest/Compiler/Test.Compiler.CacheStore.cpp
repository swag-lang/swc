#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/CompilerCacheStore.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

struct CompilerCacheStoreTestAccess
{
    using Archive   = CompilerCacheStore::Archive;
    using EntryView = CompilerCacheStore::EntryView;

    static Archive makeArchive(const std::vector<std::pair<std::string, uint8_t>>& records)
    {
        auto    bytes = std::make_shared<ByteArray>();
        Archive archive;
        bytes->resize(16);
        for (const auto& record : records)
        {
            archive.offsets.push_back(static_cast<uint32_t>(16 + records.size() * (64 + 4) + archive.offsets.size()));
            bytes->append(record.first);
            bytes->appendLe32(1);
        }
        for (const auto& record : records)
            bytes->pushBack(static_cast<std::byte>(record.second));
        archive.record = {bytes, ByteView(bytes->span())};
        return archive;
    }

    static std::vector<EntryView> merge(std::span<const Archive* const> oldestFirst)
    {
        return CompilerCacheStore::mergeSegments(oldestFirst);
    }

    static bool measure(const std::vector<EntryView>& entries, size_t& extent, const size_t limit)
    {
        return CompilerCacheStore::measureExtent(entries, extent, limit);
    }

    static std::unique_ptr<CompilerCacheStore> open(const fs::path& directory)
    {
        return std::unique_ptr<CompilerCacheStore>(new CompilerCacheStore(directory));
    }

    static void   flush(CompilerCacheStore& store) { store.flush(); }
    static void   invalidate(CompilerCacheStore& store) { store.invalidateOnce(); }
    static size_t segmentCount(const CompilerCacheStore& store) { return store.listSegments().size(); }
};

namespace
{
    struct CacheStoreTestDirectory
    {
        fs::path path = Os::getTemporaryPath() / "swc_unittest" / std::format("cache_store_p{}", Os::currentProcessId());

        CacheStoreTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path, ec);
        }

        ~CacheStoreTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path, ec);
        }
    };

    Utf8 testKey(const size_t index)
    {
        return Utf8(std::format("{:064x}", index));
    }
}

SWC_TEST_BEGIN(CompilerCacheStore_MergesSegmentsKeepingNewestRecord)
{
    const std::string keyA(64, 'a');
    const std::string keyB(64, 'b');
    const std::string keyC(64, 'c');
    const auto        older    = CompilerCacheStoreTestAccess::makeArchive({{keyA, 1}, {keyB, 2}});
    const auto        newer    = CompilerCacheStoreTestAccess::makeArchive({{keyB, 20}, {keyC, 3}});
    const std::array  segments = {&older, &newer};

    const auto merged = CompilerCacheStoreTestAccess::merge(segments);
    if (merged.size() != 3 || merged[0].key != keyA || merged[1].key != keyB || merged[2].key != keyC)
        return Result::Error;
    if (merged[0].bytes.data()[0] != std::byte{1} || merged[1].bytes.data()[0] != std::byte{20} || merged[2].bytes.data()[0] != std::byte{3})
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A publication adds a segment holding what it produced and leaves every earlier
// segment as it was.
SWC_FILESYSTEM_TEST_BEGIN(CompilerCacheStore_RetainsEveryPublication)
{
    CacheStoreTestDirectory directory;
    const Utf8              firstKey(std::string(64, 'a'));
    const Utf8              secondKey(std::string(64, 'b'));
    const Utf8              thirdKey(std::string(64, 'c'));
    constexpr size_t        K_RECORD_SIZE = 34 * 1024 * 1024;

    {
        auto store = CompilerCacheStoreTestAccess::open(directory.path);
        store->write(firstKey, ByteArray(K_RECORD_SIZE, std::byte{1}));
        CompilerCacheStoreTestAccess::flush(*store);
        store->write(secondKey, ByteArray(K_RECORD_SIZE, std::byte{2}));
        CompilerCacheStoreTestAccess::flush(*store);
        if (CompilerCacheStoreTestAccess::segmentCount(*store) != 2)
            return Result::Error;
    }

    {
        auto       firstProcess = CompilerCacheStoreTestAccess::open(directory.path);
        const auto retained     = firstProcess->read(firstKey);
        const auto second       = firstProcess->read(secondKey);
        if (!retained || !second || retained.bytes.size() != K_RECORD_SIZE || second.bytes.size() != K_RECORD_SIZE)
            return Result::Error;
        if (retained.bytes.data()[K_RECORD_SIZE - 1] != std::byte{1} || second.bytes.data()[K_RECORD_SIZE - 1] != std::byte{2})
            return Result::Error;

        // A separately opened writer leaves both segments alone, and a mapped record
        // stays valid while newer records for its key are published.
        auto secondProcess = CompilerCacheStoreTestAccess::open(directory.path);
        secondProcess->write(firstKey, ByteArray{std::byte{3}});
        secondProcess->write(thirdKey, ByteArray{std::byte{4}});
        CompilerCacheStoreTestAccess::flush(*secondProcess);
        if (retained.bytes.data()[K_RECORD_SIZE - 1] != std::byte{1})
            return Result::Error;

        auto       reopened = CompilerCacheStoreTestAccess::open(directory.path);
        const auto replaced = reopened->read(firstKey);
        if (!replaced || replaced.bytes.data()[0] != std::byte{3} || !reopened->read(secondKey) || !reopened->read(thirdKey))
            return Result::Error;
    }

    {
        auto rebuilding = CompilerCacheStoreTestAccess::open(directory.path);
        CompilerCacheStoreTestAccess::invalidate(*rebuilding);
        CompilerCacheStoreTestAccess::flush(*rebuilding);
    }
    auto cleared = CompilerCacheStoreTestAccess::open(directory.path);
    if (cleared->read(firstKey) || cleared->read(secondKey) || cleared->read(thirdKey) || CompilerCacheStoreTestAccess::segmentCount(*cleared))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(CompilerCacheStore_PublishedRecordOutlivesWriterAndInvalidation)
{
    CacheStoreTestDirectory    directory;
    const Utf8                 key = testKey(1);
    CompilerCacheStore::Record retained;
    {
        auto writer = CompilerCacheStoreTestAccess::open(directory.path);
        writer->write(key, ByteArray(4096, std::byte{17}));
        CompilerCacheStoreTestAccess::flush(*writer);
        retained = writer->read(key);
        if (!retained)
            return Result::Error;
    }
    {
        auto writer = CompilerCacheStoreTestAccess::open(directory.path);
        writer->write(key, ByteArray{std::byte{23}});
        CompilerCacheStoreTestAccess::flush(*writer);
        const auto replacement = writer->read(key);
        if (!replacement || replacement.bytes.size() != 1 || replacement.bytes.data()[0] != std::byte{23})
            return Result::Error;
        CompilerCacheStoreTestAccess::invalidate(*writer);
        CompilerCacheStoreTestAccess::flush(*writer);
    }
    if (retained.bytes.size() != 4096 ||
        !std::ranges::all_of(retained.bytes.span(), [](std::byte value) { return value == std::byte{17}; }))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Small publications accumulate until a fold merges them; the large first segment
// stays untouched and every record stays readable.
SWC_FILESYSTEM_TEST_BEGIN(CompilerCacheStore_FoldsSmallSegments)
{
    CacheStoreTestDirectory directory;
    constexpr size_t        K_PUBLICATIONS = 12;
    {
        auto store = CompilerCacheStoreTestAccess::open(directory.path);
        store->write(testKey(0), ByteArray(4096, std::byte{7}));
        CompilerCacheStoreTestAccess::flush(*store);
    }
    for (size_t index = 1; index < K_PUBLICATIONS; ++index)
    {
        auto store = CompilerCacheStoreTestAccess::open(directory.path);
        store->write(testKey(index), ByteArray{static_cast<std::byte>(index)});
        CompilerCacheStoreTestAccess::flush(*store);
    }

    auto store = CompilerCacheStoreTestAccess::open(directory.path);
    if (CompilerCacheStoreTestAccess::segmentCount(*store) > 8)
        return Result::Error;
    const auto base = store->read(testKey(0));
    if (!base || base.bytes.size() != 4096)
        return Result::Error;
    for (size_t index = 1; index < K_PUBLICATIONS; ++index)
    {
        const auto record = store->read(testKey(index));
        if (!record || record.bytes.size() != 1 || record.bytes.data()[0] != static_cast<std::byte>(index))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(CompilerCacheStore_RejectsSegmentExtentOverflow)
{
    constexpr size_t                                           K_LIMIT = 4096;
    const std::string                                          key(64, 'a');
    const ByteArray                                            bytes(K_LIMIT - 151, std::byte{0});
    const std::vector<CompilerCacheStoreTestAccess::EntryView> entries = {{key, ByteView(bytes.span())}, {key, ByteView{}}};
    size_t                                                     extent;
    if (CompilerCacheStoreTestAccess::measure(entries, extent, K_LIMIT))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
