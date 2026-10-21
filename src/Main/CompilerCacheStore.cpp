#include "pch.h"
#include "Main/CompilerCacheStore.h"
#include "Main/CompilerCache.h"
#include "Main/FileSystem.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"
#include "Support/Os/ReadOnlyFileMapping.h"

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

CompilerCacheStore::CompilerCacheStore(const bool rebuild) :
    rebuilding_(rebuild),
    replace_(rebuild)
{
    const auto&    compiler = compilerCacheIdentity();
    const auto     bytes    = std::as_bytes(std::span{compiler.data(), compiler.size()});
    const fs::path root     = WorkspaceLayout::machineCacheRoot();
    path_                   = root / std::format("{}.bin", Utf8Helper::toLowerHex(sha256(bytes)).view());
    if (!rebuild)
        archive_ = load();
    activeStore.store(this, std::memory_order_release);
}

CompilerCacheStore::~CompilerCacheStore()
{
    activeStore.store(nullptr, std::memory_order_release);
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
    const std::unique_lock lock(mutex_);
    if (rebuilding_)
        return;
    archive_ = {};
    pending_.clear();
    rebuilding_ = true;
    replace_    = true;
}

CompilerCacheStore::Record CompilerCacheStore::read(const Utf8& key) const
{
    const std::shared_lock lock(mutex_);
    const auto             found = pending_.find(key);
    return found == pending_.end() ? archive_.read(key) : found->second;
}

void CompilerCacheStore::write(const Utf8& key, ByteArray bytes)
{
    const auto             owner = std::make_shared<const ByteArray>(std::move(bytes));
    const Record           entry{owner, ByteView(owner->span())};
    const std::unique_lock lock(mutex_);
    pending_.insert_or_assign(key, entry);
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
    const std::unique_lock lock(mutex_);
    if (pending_.empty() && !replace_)
        return;
    std::error_code ec;
    fs::create_directories(path_.parent_path(), ec);
    if (ec)
        return;
    Os::DirectoryLock publication;
    Utf8              because;
    if (!publication.lock(because, path_.parent_path()))
        return;
    if (replace_ && pending_.empty())
    {
        fs::remove(path_, ec);
        if (!ec)
            replace_ = false;
        return;
    }
    Entries merged;
    if (!replace_)
        load().appendTo(merged);
    for (const auto& [key, bytes] : pending_)
        merged.insert_or_assign(key, bytes);
    size_t extent = K_HEADER_SIZE;
    for (const auto& [key, bytes] : merged)
        extent += K_INDEX_ENTRY_SIZE + bytes.bytes.size();
    // Keep the newest working set when the archive reaches its size bound.
    if (extent > K_MAX_ARCHIVE_SIZE)
    {
        merged = pending_;
        extent = K_HEADER_SIZE;
        for (const auto& [key, bytes] : merged)
            extent += K_INDEX_ENTRY_SIZE + bytes.bytes.size();
    }
    if (extent > K_MAX_ARCHIVE_SIZE)
        return;
    std::vector<Utf8> keys;
    keys.reserve(merged.size());
    for (const auto& [key, bytes] : merged)
        keys.push_back(key);
    std::ranges::sort(keys);
    ByteArray archive;
    archive.reserve(std::min(extent, K_MAX_ARCHIVE_SIZE));
    archive.appendLe64(K_STORE_MAGIC);
    archive.appendLe32(static_cast<uint32_t>(keys.size()));
    archive.appendLe32(0);
    for (const Utf8& key : keys)
    {
        const auto& bytes = merged.at(key).bytes;
        archive.append(key.view());
        archive.appendLe32(static_cast<uint32_t>(bytes.size()));
    }
    for (const Utf8& key : keys)
        archive.append(merged.at(key).bytes.span());

    // Retain this generation in memory before replacing the file. Releasing our
    // previous mappings lets the ordinary rename succeed when no other compiler
    // is still reading that generation. Outstanding reader records keep it alive.
    const auto published = std::make_shared<const ByteArray>(std::move(archive));
    archive_             = Archive::decode(Record{published, ByteView(published->span())});
    merged.clear();
    FileSystem::IoErrorInfo error;
    if (published->size() <= K_MAX_ARCHIVE_SIZE && FileSystem::writeBinaryFileAtomic(path_, published->data(), published->size(), error, FileSystem::FileReplacement::Mapped) == Result::Continue)
    {
        pending_.clear();
        replace_ = false;
    }
}

CompilerCacheStore::Archive CompilerCacheStore::load() const
{
    const auto mapping = std::make_shared<Os::ReadOnlyFileMapping>();
    if (!mapping->open(path_, K_MAX_ARCHIVE_SIZE))
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

void CompilerCacheStore::Archive::appendTo(Entries& out) const
{
    out.reserve(out.size() + offsets.size());
    for (size_t index = 0; index < offsets.size(); ++index)
    {
        const size_t keyOffset = K_HEADER_SIZE + index * K_INDEX_ENTRY_SIZE;
        Utf8         key(std::string_view(reinterpret_cast<const char*>(record.bytes.data() + keyOffset), K_KEY_SIZE));
        const auto   length = record.bytes.readLe32(keyOffset + K_KEY_SIZE);
        out.insert_or_assign(std::move(key), Record{record.owner, ByteView(record.bytes.span().subspan(offsets[index], length))});
    }
}

SWC_END_NAMESPACE();
