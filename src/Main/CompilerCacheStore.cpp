#include "pch.h"
#include "Main/CompilerCacheStore.h"
#include "Main/CompilerCache.h"
#include "Main/FileSystem.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"
#include "Support/Os/DirectoryLock.h"
#include "Support/Os/Os.h"
#include "Support/Os/ReadOnlyFileMapping.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t               K_STORE_MAGIC       = 0x32544553434d5753; // SWMCSET2
    constexpr size_t                 K_MAX_SEGMENT_SIZE  = 512 * 1024 * 1024;
    constexpr size_t                 K_MAX_STORE_SIZE    = 1024 * 1024 * 1024;
    constexpr size_t                 K_MAX_SEGMENTS      = 8;
    constexpr size_t                 K_HEADER_SIZE       = 16;
    constexpr size_t                 K_KEY_SIZE          = 64;
    constexpr size_t                 K_INDEX_ENTRY_SIZE  = K_KEY_SIZE + 4;
    constexpr std::string_view       K_SEGMENT_EXTENSION = ".seg";
    std::atomic<CompilerCacheStore*> activeStore         = nullptr;

    // Segment names sort by publication time, so a listing orders segments oldest first.
    fs::path newSegmentPath(const fs::path& directory)
    {
        static std::atomic_uint32_t sequence = 0;
        const auto                  now      = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
        return directory / std::format("{:016x}-{:08x}-{:08x}{}", now, Os::currentProcessId(), sequence.fetch_add(1, std::memory_order_relaxed), K_SEGMENT_EXTENSION);
    }
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
        // Close lazy loading first so a later reader cannot bring back an invalidated segment.
        std::call_once(loaded_, [] {});
        {
            const std::unique_lock lock(segmentsMutex_);
            segments_.clear();
        }
        for (PendingShard& shard : pending_)
        {
            const std::scoped_lock lock(shard.mutex);
            shard.entries.clear();
        }
        replace_.store(true, std::memory_order_release);
    });
}

std::vector<fs::path> CompilerCacheStore::listSegments() const
{
    std::vector<fs::path> paths;
    std::error_code       ec;
    for (fs::directory_iterator it(directory_, fs::directory_options::skip_permission_denied, ec), end; !ec && it != end; it.increment(ec))
    {
        if (it->path().extension() == K_SEGMENT_EXTENSION)
            paths.push_back(it->path());
    }
    std::ranges::sort(paths, {}, [](const fs::path& path) { return path.filename(); });
    return paths;
}

void CompilerCacheStore::ensureLoaded() const
{
    std::call_once(loaded_, [this] {
        std::vector<Segment> loaded;
        for (fs::path& path : listSegments())
        {
            Archive archive = load(path);
            if (archive.record)
                loaded.push_back({std::move(path), std::move(archive)});
        }
        const std::unique_lock lock(segmentsMutex_);
        segments_ = std::move(loaded);
    });
}

CompilerCacheStore::PendingShard& CompilerCacheStore::pendingFor(const Utf8& key) const
{
    // Keys are lowercase hexadecimal SHA-256 digests. Their first nibble spreads
    // concurrent writers without hashing the text again.
    SWC_ASSERT(key.size() == K_KEY_SIZE);
    const uint32_t digit = static_cast<uint8_t>(key[0]);
    const size_t   index = digit <= '9' ? digit - '0' : digit - 'a' + 10;
    SWC_ASSERT(index < K_PENDING_SHARDS);
    return pending_[index];
}

CompilerCacheStore::Record CompilerCacheStore::read(const Utf8& key) const
{
    {
        PendingShard&          shard = pendingFor(key);
        const std::scoped_lock lock(shard.mutex);
        if (const auto found = shard.entries.find(key); found != shard.entries.end())
            return found->second;
    }

    ensureLoaded();
    const std::shared_lock lock(segmentsMutex_);
    for (auto it = segments_.rbegin(); it != segments_.rend(); ++it)
    {
        if (Record record = it->archive.read(key))
            return record;
    }
    return {};
}

void CompilerCacheStore::write(const Utf8& key, ByteArray bytes)
{
    const auto             owner = std::make_shared<const ByteArray>(std::move(bytes));
    PendingShard&          shard = pendingFor(key);
    const std::scoped_lock lock(shard.mutex);
    shard.entries.insert_or_assign(key, Record{owner, ByteView(owner->span())});
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
    const std::scoped_lock flushLock(flushMutex_);

    // Records written while this publication runs stay pending for the next one.
    Entries published;
    for (PendingShard& shard : pending_)
    {
        const std::scoped_lock lock(shard.mutex);
        for (const auto& [key, record] : shard.entries)
            published.insert_or_assign(key, record);
    }

    const bool replace = replace_.load(std::memory_order_acquire);
    if (published.empty() && !replace)
        return;

    std::error_code ec;
    fs::create_directories(directory_, ec);
    if (ec)
        return;
    const std::vector<fs::path> replaced = replace ? listSegments() : std::vector<fs::path>{};

    if (!published.empty())
    {
        std::vector<EntryView> entries;
        entries.reserve(published.size());
        for (const auto& [key, record] : published)
            entries.push_back({key.view(), record.bytes});
        std::ranges::sort(entries, {}, &EntryView::key);

        Archive        archive;
        const fs::path path = newSegmentPath(directory_);
        if (!publish(archive, path, entries))
            return;
        {
            const std::unique_lock lock(segmentsMutex_);
            segments_.push_back({path, std::move(archive)});
        }
        for (PendingShard& shard : pending_)
        {
            const std::scoped_lock lock(shard.mutex);
            std::erase_if(shard.entries, [&](const auto& entry) {
                const auto found = published.find(entry.first);
                return found != published.end() && found->second.owner == entry.second.owner;
            });
        }
    }

    if (replace)
    {
        for (const fs::path& path : replaced)
            fs::remove(path, ec);
        replace_.store(false, std::memory_order_release);
    }

    compact();
}

// Folds segments once they accumulate. The largest one, the working set a first build left,
// stays untouched while it outweighs the others together, so an edit-compile cycle rewrites
// only the small segments its own builds added. Past the store bound, the oldest segments go.
void CompilerCacheStore::compact() const
{
    if (listSegments().size() <= K_MAX_SEGMENTS)
        return;
    Os::DirectoryLock publication;
    Utf8              because;
    if (!publication.lock(because, directory_))
        return;

    // Another compiler may have folded the segments while this one waited.
    std::vector<Segment> segments;
    for (fs::path& path : listSegments())
    {
        Archive archive = load(path);
        if (archive.record)
            segments.push_back({std::move(path), std::move(archive)});
    }
    if (segments.size() <= K_MAX_SEGMENTS)
        return;

    std::error_code ec;
    size_t          total = 0;
    for (const Segment& segment : segments)
        total += segment.archive.record.bytes.size();
    while (total > K_MAX_STORE_SIZE && segments.size() > 1)
    {
        total -= segments.front().archive.record.bytes.size();
        fs::remove(segments.front().path, ec);
        segments.erase(segments.begin());
    }

    const auto                  largest = std::ranges::max_element(segments, {}, [](const Segment& segment) { return segment.archive.record.bytes.size(); });
    const bool                  keep    = largest->archive.record.bytes.size() * 2 >= total;
    std::vector<const Archive*> folded;
    std::vector<fs::path>       foldedPaths;
    for (const Segment& segment : segments)
    {
        if (keep && &segment == &*largest)
            continue;
        folded.push_back(&segment.archive);
        foldedPaths.push_back(segment.path);
    }
    if (folded.size() < 2)
        return;

    Archive archive;
    if (!publish(archive, newSegmentPath(directory_), mergeSegments(folded)))
        return;
    // A segment another compiler still maps stays until a later fold finds it free; its records
    // are duplicates of the folded ones by then.
    for (const fs::path& path : foldedPaths)
        fs::remove(path, ec);
}

std::vector<CompilerCacheStore::EntryView> CompilerCacheStore::mergeSegments(const std::span<const Archive* const> oldestFirst)
{
    struct Ranked
    {
        EntryView entry;
        size_t    age;
    };

    std::vector<Ranked> ranked;
    for (size_t age = 0; age < oldestFirst.size(); ++age)
    {
        const Archive& archive = *oldestFirst[age];
        for (size_t index = 0; index < archive.offsets.size(); ++index)
            ranked.push_back({archive.entry(index), age});
    }

    // The newest record of a key wins.
    std::ranges::sort(ranked, [](const Ranked& left, const Ranked& right) { return left.entry.key != right.entry.key ? left.entry.key < right.entry.key : left.age > right.age; });
    std::vector<EntryView> merged;
    merged.reserve(ranked.size());
    for (const Ranked& item : ranked)
    {
        if (merged.empty() || merged.back().key != item.entry.key)
            merged.push_back(item.entry);
    }
    return merged;
}

bool CompilerCacheStore::measureExtent(const std::vector<EntryView>& entries, size_t& extent, const size_t limit)
{
    extent = K_HEADER_SIZE;
    for (const EntryView& entry : entries)
    {
        if (extent > limit - K_INDEX_ENTRY_SIZE || entry.bytes.size() > limit - extent - K_INDEX_ENTRY_SIZE)
            return false;
        extent += K_INDEX_ENTRY_SIZE + entry.bytes.size();
    }
    return true;
}

// Writes sorted, distinct entries as a new segment. The segment is renamed into place under a
// name nothing else uses, so readers see it complete or not at all.
bool CompilerCacheStore::publish(Archive& outArchive, const fs::path& path, const std::vector<EntryView>& entries)
{
    size_t extent = 0;
    if (!measureExtent(entries, extent, K_MAX_SEGMENT_SIZE))
        return false;

    ByteArray bytes;
    bytes.reserve(extent);
    bytes.appendLe64(K_STORE_MAGIC);
    bytes.appendLe32(static_cast<uint32_t>(entries.size()));
    bytes.appendLe32(0);
    for (const EntryView& entry : entries)
    {
        bytes.append(entry.key);
        bytes.appendLe32(static_cast<uint32_t>(entry.bytes.size()));
    }
    for (const EntryView& entry : entries)
        bytes.append(entry.bytes.span());

    const auto              owner = std::make_shared<const ByteArray>(std::move(bytes));
    FileSystem::IoErrorInfo error;
    if (FileSystem::writeBinaryFileAtomic(path, owner->data(), owner->size(), error) != Result::Continue)
        return false;
    // Reuse the published file's backing instead of retaining a private copy
    // for the rest of this process. Another compiler may already have folded
    // the segment, so a failed mapping must preserve the successful publication.
    outArchive = load(path);
    if (!outArchive.record)
        outArchive = Archive::decode(Record{owner, ByteView(owner->span())});
    return true;
}

CompilerCacheStore::Archive CompilerCacheStore::load(const fs::path& path)
{
    const auto mapping = std::make_shared<Os::ReadOnlyFileMapping>();
    if (!mapping->open(path, K_MAX_SEGMENT_SIZE))
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

CompilerCacheStore::EntryView CompilerCacheStore::Archive::entry(const size_t index) const
{
    const size_t keyOffset = K_HEADER_SIZE + index * K_INDEX_ENTRY_SIZE;
    const auto   key       = std::string_view(reinterpret_cast<const char*>(record.bytes.data() + keyOffset), K_KEY_SIZE);
    const auto   length    = record.bytes.readLe32(keyOffset + K_KEY_SIZE);
    return {key, ByteView(record.bytes.span().subspan(offsets[index], length))};
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
