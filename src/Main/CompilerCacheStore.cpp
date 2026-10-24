#include "pch.h"
#include "Main/CompilerCacheStore.h"
#include "Main/CompilerCache.h"
#include "Main/FileSystem.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"
#include "Support/Os/ReadOnlyFileMapping.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t               K_STORE_MAGIC      = 0x32544553434d5753; // SWMCSET2
    constexpr size_t                 K_MAX_ARCHIVE_SIZE = 64 * 1024 * 1024;
    constexpr size_t                 K_HEADER_SIZE      = 16;
    constexpr size_t                 K_KEY_SIZE         = 64;
    constexpr size_t                 K_INDEX_ENTRY_SIZE = K_KEY_SIZE + 4;
    std::atomic<CompilerCacheStore*> activeStore        = nullptr;
}

CompilerCacheStore::CompilerCacheStore(fs::path directory) :
    directory_(std::move(directory))
{
}

CompilerCacheStore::CompilerCacheStore(const bool rebuild)
{
    const auto&    compiler = compilerCacheIdentity();
    const auto     bytes    = std::as_bytes(std::span{compiler.data(), compiler.size()});
    const fs::path root     = WorkspaceLayout::machineCacheRoot();
    directory_              = root / std::format("{}", Utf8Helper::toLowerHex(sha256(bytes)).view());
    if (rebuild)
        invalidateOnce();
    activeStore.store(this, std::memory_order_release);
}

CompilerCacheStore::~CompilerCacheStore()
{
    CompilerCacheStore* expected = this;
    activeStore.compare_exchange_strong(expected, nullptr, std::memory_order_acq_rel);
}

CompilerCacheStore& CompilerCacheStore::get(const bool rebuild)
{
    static CompilerCacheStore cache(rebuild);
    if (rebuild)
        cache.invalidateOnce();
    return cache;
}

void CompilerCacheStore::invalidateOnce()
{
    std::call_once(invalidated_, [this] {
        for (auto& shard : shards_)
        {
            // Close lazy loading before clearing a partition so a later reader
            // cannot restore the invalidated file generation.
            std::call_once(shard.loaded, [] {});
            const std::unique_lock lock(shard.mutex);
            shard.archive = {};
            shard.pending.clear();
            shard.replace = true;
        }
    });
}

fs::path CompilerCacheStore::shardPath(const size_t index) const
{
    return directory_ / std::format("{:x}", index) / "code.bin";
}

CompilerCacheStore::Shard& CompilerCacheStore::shardFor(const Utf8& key) const
{
    // Keys are lowercase hexadecimal SHA-256 digests. Their first nibble gives
    // uniform partitions without hashing the text again.
    SWC_ASSERT(key.size() == K_KEY_SIZE);
    const uint32_t digit = static_cast<uint8_t>(key[0]);
    const size_t   index = digit <= '9' ? digit - '0' : digit - 'a' + 10;
    SWC_ASSERT(index < K_SHARD_COUNT);
    Shard& shard = shards_[index];
    std::call_once(shard.loaded, [this, &shard, index] { shard.archive = load(shardPath(index)); });
    return shard;
}

CompilerCacheStore::Record CompilerCacheStore::read(const Utf8& key) const
{
    Shard&                 shard = shardFor(key);
    const std::shared_lock lock(shard.mutex);
    const auto             found = shard.pending.find(key);
    return found == shard.pending.end() ? shard.archive.read(key) : found->second;
}

void CompilerCacheStore::write(const Utf8& key, ByteArray bytes)
{
    const auto             owner = std::make_shared<const ByteArray>(std::move(bytes));
    const Record           entry{owner, ByteView(owner->span())};
    Shard&                 shard = shardFor(key);
    const std::unique_lock lock(shard.mutex);
    shard.pending.insert_or_assign(key, entry);
}

void CompilerCacheStore::flushAll()
{
    if (CompilerCacheStore* cache = activeStore.load(std::memory_order_acquire))
        cache->flush();
}

void CompilerCacheStore::invalidateAll()
{
    get(true);
    flushAll();
}

void CompilerCacheStore::flush()
{
    for (size_t index = 0; index < K_SHARD_COUNT; ++index)
        flushShard(index);
}

void CompilerCacheStore::flushShard(const size_t index)
{
    Shard&                 shard = shards_[index];
    const std::unique_lock lock(shard.mutex);
    if (shard.pending.empty() && !shard.replace)
        return;
    const fs::path  path = shardPath(index);
    std::error_code ec;
    fs::create_directories(path.parent_path(), ec);
    if (ec)
        return;
    Os::DirectoryLock publication;
    Utf8              because;
    if (!publication.lock(because, path.parent_path()))
        return;
    if (shard.replace && shard.pending.empty())
    {
        fs::remove(path, ec);
        if (!ec)
            shard.replace = false;
        return;
    }
    const Archive          current = shard.replace ? Archive{} : load(path);
    std::vector<EntryView> merged  = mergeEntries(current, shard.pending);
    size_t                 extent;
    bool                   fitsArchive = measureExtent(merged, extent);
    // Keep the newest working set when the archive reaches its size bound.
    if (!fitsArchive)
    {
        std::vector<EntryView> recent;
        recent.reserve(shard.pending.size());
        for (const auto& [key, record] : shard.pending)
            recent.push_back({key.view(), record.bytes});
        std::ranges::sort(recent, {}, &EntryView::key);
        merged      = std::move(recent);
        fitsArchive = measureExtent(merged, extent);
    }
    if (!fitsArchive)
        return;

    ByteArray archive;
    archive.reserve(extent);
    archive.appendLe64(K_STORE_MAGIC);
    archive.appendLe32(static_cast<uint32_t>(merged.size()));
    archive.appendLe32(0);
    for (const EntryView& entry : merged)
    {
        archive.append(entry.key);
        archive.appendLe32(static_cast<uint32_t>(entry.bytes.size()));
    }
    for (const EntryView& entry : merged)
        archive.append(entry.bytes.span());

    // Retain this generation in memory before replacing the file. Releasing our
    // previous mappings lets the ordinary rename succeed when no other compiler
    // is still reading that generation. Outstanding reader records keep it alive.
    const auto published = std::make_shared<const ByteArray>(std::move(archive));
    shard.archive        = Archive::decode(Record{published, ByteView(published->span())});
    FileSystem::IoErrorInfo error;
    if (published->size() <= K_MAX_ARCHIVE_SIZE && FileSystem::writeBinaryFileAtomic(path, published->data(), published->size(), error, FileSystem::FileReplacement::Mapped) == Result::Continue)
    {
        shard.pending.clear();
        shard.replace = false;
    }
}

std::vector<CompilerCacheStore::EntryView> CompilerCacheStore::mergeEntries(const Archive& archive, const Entries& pendingEntries)
{
    // Keep archived keys mapped and sort only the pending delta before the linear merge.
    std::vector<const Entries::value_type*> pending;
    pending.reserve(pendingEntries.size());
    for (const auto& entry : pendingEntries)
        pending.push_back(&entry);
    std::ranges::sort(pending, [](const auto* left, const auto* right) { return left->first < right->first; });

    std::vector<EntryView> merged;
    merged.reserve(archive.offsets.size() + pending.size());
    size_t archiveIndex = 0;
    size_t pendingIndex = 0;
    while (archiveIndex < archive.offsets.size() || pendingIndex < pending.size())
    {
        const size_t           archiveKeyOffset = K_HEADER_SIZE + archiveIndex * K_INDEX_ENTRY_SIZE;
        const std::string_view archiveKey       = archiveIndex < archive.offsets.size()
                                                      ? std::string_view(reinterpret_cast<const char*>(archive.record.bytes.data() + archiveKeyOffset), K_KEY_SIZE)
                                                      : std::string_view{};
        if (pendingIndex == pending.size() || (archiveIndex < archive.offsets.size() && archiveKey < pending[pendingIndex]->first.view()))
        {
            const uint32_t length = archive.record.bytes.readLe32(archiveKeyOffset + K_KEY_SIZE);
            merged.push_back({archiveKey, ByteView(archive.record.bytes.span().subspan(archive.offsets[archiveIndex], length))});
            ++archiveIndex;
        }
        else if (archiveIndex == archive.offsets.size() || pending[pendingIndex]->first.view() < archiveKey)
        {
            const auto& [key, record] = *pending[pendingIndex++];
            merged.push_back({key.view(), record.bytes});
        }
        else
        {
            const auto& [key, record] = *pending[pendingIndex++];
            merged.push_back({key.view(), record.bytes});
            ++archiveIndex;
        }
    }
    return merged;
}

bool CompilerCacheStore::measureExtent(const std::vector<EntryView>& entries, size_t& extent)
{
    extent = K_HEADER_SIZE;
    for (const EntryView& entry : entries)
    {
        if (extent > K_MAX_ARCHIVE_SIZE - K_INDEX_ENTRY_SIZE || entry.bytes.size() > K_MAX_ARCHIVE_SIZE - extent - K_INDEX_ENTRY_SIZE)
            return false;
        extent += K_INDEX_ENTRY_SIZE + entry.bytes.size();
    }
    return true;
}

CompilerCacheStore::Archive CompilerCacheStore::load(const fs::path& path)
{
    const auto mapping = std::make_shared<Os::ReadOnlyFileMapping>();
    if (!mapping->open(path, K_MAX_ARCHIVE_SIZE))
        return {};
    return Archive::decode(Record{mapping, ByteView(mapping->bytes())});
}

CompilerCacheStore::Archive CompilerCacheStore::Archive::decode(Record record)
{
    const ByteView bytes = record.bytes;
    if (bytes.size() < K_HEADER_SIZE || bytes.readLe64(0) != K_STORE_MAGIC)
        return {};
    const uint32_t count = bytes.readLe32(8);
    if (count > (bytes.size() - K_HEADER_SIZE) / (K_INDEX_ENTRY_SIZE + 1))
        return {};

    Archive archive;
    archive.offsets.reserve(count);
    size_t cursor     = K_HEADER_SIZE;
    size_t bodyCursor = K_HEADER_SIZE + static_cast<size_t>(count) * K_INDEX_ENTRY_SIZE;
    for (uint32_t index = 0; index < count; ++index)
    {
        // Publications already sort keys. Validate that order before binary lookup;
        // retain only body offsets instead of allocating a string and hash node per key.
        if (index && std::memcmp(bytes.data() + cursor - K_INDEX_ENTRY_SIZE, bytes.data() + cursor, K_KEY_SIZE) >= 0)
            return {};
        const uint32_t length = bytes.readLe32(cursor + K_KEY_SIZE);
        cursor += K_INDEX_ENTRY_SIZE;
        if (!length || !bytes.containsRange(bodyCursor, length))
            return {};
        archive.offsets.push_back(static_cast<uint32_t>(bodyCursor));
        bodyCursor += length;
    }
    if (bodyCursor != bytes.size())
        return {};
    archive.record = std::move(record);
    return archive;
}

CompilerCacheStore::Record CompilerCacheStore::Archive::read(const Utf8& key) const
{
    if (key.size() != K_KEY_SIZE)
        return {};
    size_t first = 0, last = offsets.size();
    while (first < last)
    {
        const size_t cursor     = first + (last - first) / 2;
        const size_t keyOffset  = K_HEADER_SIZE + cursor * K_INDEX_ENTRY_SIZE;
        const int    comparison = std::memcmp(key.data(), record.bytes.data() + keyOffset, K_KEY_SIZE);
        if (!comparison)
        {
            const uint32_t length = record.bytes.readLe32(keyOffset + K_KEY_SIZE);
            return Record{record.owner, ByteView(record.bytes.span().subspan(offsets[cursor], length))};
        }
        if (comparison < 0)
            last = cursor;
        else
            first = cursor + 1;
    }
    return {};
}

SWC_END_NAMESPACE();
