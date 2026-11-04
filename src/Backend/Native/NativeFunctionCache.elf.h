#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

struct NativeElfCachedFunction
{
    std::string_view           key;
    std::string_view           fingerprint;
    std::string_view           symbolName;
    uint64_t                   callClobbers = 0;
    std::span<const std::byte> objectBytes;
};

// One atomic, checksummed output-local cache. Its views borrow the owned immutable image;
// no COFF archive directory or persisted process address participates in ELF reuse.
class NativeElfFunctionCache
{
public:
    explicit NativeElfFunctionCache(Utf8 identity) :
        identity_(std::move(identity))
    {
    }
    NativeElfFunctionCache(const NativeElfFunctionCache&)            = delete;
    NativeElfFunctionCache& operator=(const NativeElfFunctionCache&) = delete;

    bool                           load(ByteArray bytes);
    const NativeElfCachedFunction* find(std::string_view key) const;
    bool                           build(ByteArray& out, std::span<const NativeElfCachedFunction> functions) const;

private:
    Utf8                                                          identity_;
    ByteArray                                                     bytes_;
    std::unordered_map<std::string_view, NativeElfCachedFunction> functions_;
};

SWC_END_NAMESPACE();
