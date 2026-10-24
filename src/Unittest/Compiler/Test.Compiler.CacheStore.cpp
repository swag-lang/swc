#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/CompilerCacheStore.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

struct CompilerCacheStoreTestAccess
{
    using Archive   = CompilerCacheStore::Archive;
    using Entries   = CompilerCacheStore::Entries;
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

    static void addPending(Entries& entries, const std::string_view key, const uint8_t value)
    {
        auto bytes = std::make_shared<const ByteArray>(ByteArray{static_cast<std::byte>(value)});
        entries.insert_or_assign(Utf8(key), CompilerCacheStore::Record{bytes, ByteView(bytes->span())});
    }

    static std::vector<EntryView> merge(const Archive& archive, const Entries& pending)
    {
        return CompilerCacheStore::mergeEntries(archive, pending);
    }

    static bool measure(const std::vector<EntryView>& entries, size_t& extent)
    {
        return CompilerCacheStore::measureExtent(entries, extent);
    }

    static std::unique_ptr<CompilerCacheStore> open(const fs::path& directory)
    {
        return std::unique_ptr<CompilerCacheStore>(new CompilerCacheStore(directory));
    }

    static void flush(CompilerCacheStore& store) { store.flush(); }
    static void invalidate(CompilerCacheStore& store) { store.invalidateOnce(); }
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
}

SWC_TEST_BEGIN(CompilerCacheStore_MergesSortedArchiveAndPendingRecords)
{
    const std::string                     keyA(64, 'a');
    const std::string                     keyB(64, 'b');
    const std::string                     keyC(64, 'c');
    const auto                            archive = CompilerCacheStoreTestAccess::makeArchive({{keyA, 1}, {keyB, 2}});
    CompilerCacheStoreTestAccess::Entries pending;
    CompilerCacheStoreTestAccess::addPending(pending, keyB, 20);
    CompilerCacheStoreTestAccess::addPending(pending, keyC, 3);

    const auto merged = CompilerCacheStoreTestAccess::merge(archive, pending);
    if (merged.size() != 3 || merged[0].key != keyA || merged[1].key != keyB || merged[2].key != keyC)
        return Result::Error;
    if (merged[0].bytes.data()[0] != std::byte{1} || merged[1].bytes.data()[0] != std::byte{20} || merged[2].bytes.data()[0] != std::byte{3})
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(CompilerCacheStore_RetainsMoreThanOneModuleWorkingSet)
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
        // Two successive module builds must coexist even beyond the old
        // whole-compiler archive limit of 64 MiB.
        store->write(secondKey, ByteArray(K_RECORD_SIZE, std::byte{2}));
        CompilerCacheStoreTestAccess::flush(*store);
    }

    auto       firstProcess = CompilerCacheStoreTestAccess::open(directory.path);
    const auto retained     = firstProcess->read(firstKey);
    const auto second       = firstProcess->read(secondKey);
    if (!retained || !second || retained.bytes.size() != K_RECORD_SIZE || second.bytes.size() != K_RECORD_SIZE)
        return Result::Error;
    if (retained.bytes.data()[K_RECORD_SIZE - 1] != std::byte{1} || second.bytes.data()[K_RECORD_SIZE - 1] != std::byte{2})
        return Result::Error;

    // A separately opened writer must preserve both existing partitions, and
    // an outstanding mapped record must remain valid after replacement.
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

    CompilerCacheStoreTestAccess::invalidate(*reopened);
    CompilerCacheStoreTestAccess::flush(*reopened);
    auto cleared = CompilerCacheStoreTestAccess::open(directory.path);
    if (cleared->read(firstKey) || cleared->read(secondKey) || cleared->read(thirdKey))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(CompilerCacheStore_RejectsArchiveExtentOverflow)
{
    constexpr size_t                                           K_MAX_ARCHIVE_SIZE = 64 * 1024 * 1024;
    const std::string                                          key(64, 'a');
    const ByteArray                                            bytes(K_MAX_ARCHIVE_SIZE - 151, std::byte{0});
    const std::vector<CompilerCacheStoreTestAccess::EntryView> entries = {{key, ByteView(bytes.span())}, {key, ByteView{}}};
    size_t                                                     extent;
    if (CompilerCacheStoreTestAccess::measure(entries, extent))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
