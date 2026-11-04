#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/ObjectWriter.elf.h"
#include "Backend/Native/NativeFunctionCache.elf.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ByteArray leafObject(const bool external = false)
    {
        LinkImage   image;
        LinkSection code;
        code.name  = ".text";
        code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;
        code.bytes.appendLe64(0);
        if (external)
            code.relocs.push_back({.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = "foreign"});
        image.sections.push_back(std::move(code));
        image.symbols.push_back({.name = "leaf", .sectionIndex = 0});
        ByteArray  bytes;
        Diagnostic error;
        if (!buildElfObject(bytes, error, image))
            return {};
        return bytes;
    }
}

SWC_TEST_BEGIN(ElfFunctionCache_RoundTripsOwnedObjectsAndRejectsIncompatibleIdentity)
{
    const ByteArray               object = leafObject();
    const std::string             key(64, 'a'), fingerprint(64, 'b');
    const NativeElfCachedFunction entry{.key = key, .fingerprint = fingerprint, .symbolName = "leaf", .callClobbers = 0x1234, .objectBytes = object.span()};
    NativeElfFunctionCache        writer("compiler-one");
    ByteArray                     bytes;
    if (object.empty() || !writer.build(bytes, std::span(&entry, 1)))
        return Result::Error;
    NativeElfFunctionCache reader("compiler-one");
    if (!reader.load(bytes))
        return Result::Error;
    const auto* found = reader.find(key);
    if (!found || found->fingerprint != fingerprint || found->symbolName != "leaf" || found->callClobbers != 0x1234 || !std::ranges::equal(found->objectBytes, object.span()) || reader.find(fingerprint))
        return Result::Error;
    NativeElfFunctionCache differentCompiler("compiler-two");
    if (differentCompiler.load(bytes) || differentCompiler.find(key))
        return Result::Error;
    if (!writer.build(bytes, {}) || !reader.load(std::move(bytes)) || reader.find(key))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfFunctionCache_CorruptionRetiresPriorEntries)
{
    const ByteArray               object = leafObject();
    const std::string             key(64, 'a'), fingerprint(64, 'b');
    const NativeElfCachedFunction entry{.key = key, .fingerprint = fingerprint, .symbolName = "leaf", .objectBytes = object.span()};
    NativeElfFunctionCache        cache("compiler");
    ByteArray                     bytes;
    if (!cache.build(bytes, std::span(&entry, 1)))
        return Result::Error;
    for (size_t size = 0; size < bytes.size(); ++size)
    {
        ByteArray truncated;
        truncated.append(bytes.span().first(size));
        if (!cache.load(bytes) || cache.load(std::move(truncated)) || cache.find(key))
            return Result::Error;
    }
    for (size_t offset = 0; offset < bytes.size(); ++offset)
    {
        ByteArray corrupt = bytes;
        corrupt[offset] ^= std::byte{0x80};
        if (cache.load(std::move(corrupt)) || cache.find(key))
            return Result::Error;
    }
    const std::array duplicates = {entry, entry};
    if (cache.build(bytes, duplicates) || !bytes.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ElfFunctionCache_RejectsForeignRelocationsAndMalformedObjects)
{
    const ByteArray object = leafObject();
    if (!isSelfContainedElfObject(object.span(), "leaf") || isSelfContainedElfObject(object.span(), "missing") || isSelfContainedElfObject(leafObject(true).span(), "leaf"))
        return Result::Error;
    for (size_t size = 0; size < object.size(); ++size)
        if (isSelfContainedElfObject(object.span().first(size), "leaf"))
            return Result::Error;
    ByteArray wrongTarget = object;
    wrongTarget.writeLe16(18, 183); // AArch64 must not be reused as x86-64.
    if (isSelfContainedElfObject(wrongTarget.span(), "leaf"))
        return Result::Error;
    ByteArray badSections = object;
    badSections.writeLe64(40, UINT64_MAX);
    if (isSelfContainedElfObject(badSections.span(), "leaf"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
