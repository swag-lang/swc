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
        load(entries_);
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
    entries_.clear();
    pending_.clear();
    rebuilding_ = true;
    replace_    = true;
}

CompilerCacheStore::Record CompilerCacheStore::read(const Utf8& key) const
{
    const std::shared_lock lock(mutex_);
    const auto             found = entries_.find(key);
    return found == entries_.end() ? Record{} : found->second;
}

void CompilerCacheStore::write(const Utf8& key, ByteArray bytes)
{
    const auto             owner = std::make_shared<const ByteArray>(std::move(bytes));
    const Record           entry{owner, ByteView(owner->span())};
    const std::unique_lock lock(mutex_);
    entries_.insert_or_assign(key, entry);
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
        load(merged);
    for (const auto& [key, bytes] : pending_)
        merged.insert_or_assign(key, bytes);
    size_t extent = 16;
    for (const auto& [key, bytes] : merged)
        extent += 68 + bytes.bytes.size();
    // Keep the newest working set when the archive reaches its size bound.
    if (extent > K_MAX_ARCHIVE_SIZE)
    {
        merged = pending_;
        extent = 16;
        for (const auto& [key, bytes] : merged)
            extent += 68 + bytes.bytes.size();
    }
    if (extent > K_MAX_ARCHIVE_SIZE)
        return;
    std::vector<Utf8> keys;
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
    const auto published  = std::make_shared<const ByteArray>(std::move(archive));
    size_t     bodyCursor = 16 + keys.size() * 68;
    for (const Utf8& key : keys)
    {
        auto&        record = merged.at(key);
        const size_t length = record.bytes.size();
        record              = Record{published, ByteView(published->span().subspan(bodyCursor, length))};
        bodyCursor += length;
    }
    entries_ = std::move(merged);
    FileSystem::IoErrorInfo error;
    if (published->size() <= K_MAX_ARCHIVE_SIZE && FileSystem::writeBinaryFileAtomic(path_, published->data(), published->size(), error, FileSystem::FileReplacement::Mapped) == Result::Continue)
    {
        pending_.clear();
        replace_ = false;
    }
}

void CompilerCacheStore::load(Entries& out) const
{
    const auto mapping = std::make_shared<Os::ReadOnlyFileMapping>();
    if (!mapping->open(path_, K_MAX_ARCHIVE_SIZE))
        return;
    const ByteView archive(mapping->bytes());
    if (archive.size() < 16 || archive.readLe64(0) != K_STORE_MAGIC)
        return;
    const uint32_t count = archive.readLe32(8);
    if (count > (archive.size() - 16) / 69)
        return;
    Entries entries;
    // Keep the index contiguous so lookup does not fault pages from unused bodies.
    size_t cursor     = 16;
    size_t bodyCursor = 16 + static_cast<size_t>(count) * 68;
    for (uint32_t index = 0; index < count; ++index)
    {
        if (!archive.containsRange(cursor, 68))
            return;
        Utf8           key(std::string_view(reinterpret_cast<const char*>(archive.data() + cursor), 64));
        const uint32_t length = archive.readLe32(cursor + 64);
        cursor += 68;
        if (!length || !archive.containsRange(bodyCursor, length))
            return;
        const Record record{mapping, ByteView(archive.span().subspan(bodyCursor, length))};
        if (!entries.emplace(std::move(key), record).second)
            return;
        bodyCursor += length;
    }
    if (bodyCursor == archive.size())
        out = std::move(entries);
}

SWC_END_NAMESPACE();
