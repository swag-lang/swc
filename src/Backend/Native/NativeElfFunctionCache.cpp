#include "pch.h"
#include "Backend/Native/NativeElfFunctionCache.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Support/Core/ByteView.h"
#include "Support/Math/Sha256.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_MAGIC       = 0x3143464c45435753; // SWCELFC1
    constexpr size_t   K_HEADER_SIZE = 48;
    constexpr size_t   K_ENTRY_SIZE  = 144;

    bool isFingerprint(const std::string_view value)
    {
        return value.size() == 64 && value.find_first_not_of("0123456789abcdef") == std::string_view::npos;
    }
}

bool NativeElfFunctionCache::load(ByteArray bytes)
{
    functions_.clear();
    bytes_ = std::move(bytes);
    const ByteView view(bytes_.span());
    if (!view.containsRange(0, K_HEADER_SIZE) || view.readLe64(0) != K_MAGIC)
        return false;
    const auto checksum = sha256(bytes_.span().subspan(K_HEADER_SIZE));
    if (std::memcmp(bytes_.data() + 16, checksum.data(), checksum.size()) != 0)
        return false;
    const uint32_t count        = view.readLe32(8);
    const uint32_t identitySize = view.readLe32(12);
    size_t         cursor       = K_HEADER_SIZE;
    if (!view.containsRange(cursor, identitySize) || identitySize != identity_.size() ||
        std::memcmp(bytes_.data() + cursor, identity_.data(), identitySize) != 0)
        return false;
    cursor += identitySize;
    if (count > (bytes_.size() - cursor) / K_ENTRY_SIZE)
        return false;
    std::unordered_map<std::string_view, NativeElfCachedFunction> functions;
    functions.reserve(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        if (!view.containsRange(cursor, K_ENTRY_SIZE))
            return false;
        NativeElfCachedFunction entry;
        entry.key                 = {reinterpret_cast<const char*>(bytes_.data() + cursor), 64};
        entry.fingerprint         = {reinterpret_cast<const char*>(bytes_.data() + cursor + 64), 64};
        entry.callClobbers        = view.readLe64(cursor + 128);
        const uint32_t nameSize   = view.readLe32(cursor + 136);
        const uint32_t objectSize = view.readLe32(cursor + 140);
        cursor += K_ENTRY_SIZE;
        if (!isFingerprint(entry.key) || !isFingerprint(entry.fingerprint) || !nameSize || !view.containsRange(cursor, nameSize))
            return false;
        entry.symbolName = {reinterpret_cast<const char*>(bytes_.data() + cursor), nameSize};
        cursor += nameSize;
        if (!view.containsRange(cursor, objectSize))
            return false;
        entry.objectBytes = bytes_.span().subspan(cursor, objectSize);
        cursor += objectSize;
        if (!isSelfContainedElfObject(entry.objectBytes, entry.symbolName) || !functions.emplace(entry.key, entry).second)
            return false;
    }
    if (cursor != bytes_.size())
        return false;
    functions_ = std::move(functions);
    return true;
}

const NativeElfCachedFunction* NativeElfFunctionCache::find(const std::string_view key) const
{
    const auto entry = functions_.find(key);
    return entry == functions_.end() ? nullptr : &entry->second;
}

bool NativeElfFunctionCache::build(ByteArray& out, const std::span<const NativeElfCachedFunction> functions) const
{
    out.clear();
    if (identity_.size() > UINT32_MAX || functions.size() > UINT32_MAX)
        return false;
    out.appendLe64(K_MAGIC);
    out.appendLe32(static_cast<uint32_t>(functions.size()));
    out.appendLe32(static_cast<uint32_t>(identity_.size()));
    out.resize(K_HEADER_SIZE);
    out.append(identity_.view());
    std::unordered_set<std::string_view> keys;
    for (const auto& entry : functions)
    {
        if (!isFingerprint(entry.key) || !isFingerprint(entry.fingerprint) || entry.symbolName.empty() || entry.symbolName.size() > UINT32_MAX || entry.objectBytes.size() > UINT32_MAX ||
            !isSelfContainedElfObject(entry.objectBytes, entry.symbolName) || !keys.insert(entry.key).second)
        {
            out.clear();
            return false;
        }
        out.append(entry.key);
        out.append(entry.fingerprint);
        out.appendLe64(entry.callClobbers);
        out.appendLe32(static_cast<uint32_t>(entry.symbolName.size()));
        out.appendLe32(static_cast<uint32_t>(entry.objectBytes.size()));
        out.append(entry.symbolName);
        out.append(entry.objectBytes);
    }
    const auto checksum = sha256(out.span().subspan(K_HEADER_SIZE));
    std::memcpy(out.data() + 16, checksum.data(), checksum.size());
    return true;
}

SWC_END_NAMESPACE();
