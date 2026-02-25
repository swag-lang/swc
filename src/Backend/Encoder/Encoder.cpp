#include "pch.h"
#include "Backend/Encoder/Encoder.h"

SWC_BEGIN_NAMESPACE();

const uint8_t* Encoder::data() const
{
    if (!store_.size())
        return nullptr;
    return store_.ptr<uint8_t>(0);
}

uint8_t Encoder::byteAt(uint32_t index) const
{
    SWC_ASSERT(index < store_.size());
    return *SWC_NOT_NULL(store_.ptr<uint8_t>(index));
}

void Encoder::copyTo(ByteSpanRW dst) const
{
    store_.copyTo(dst);
}

void Encoder::addDebugSourceRange(const uint32_t codeStartOffset, const uint32_t codeEndOffset, const SourceCodeRef& sourceCodeRef)
{
    SWC_ASSERT(codeEndOffset >= codeStartOffset);
    if (codeEndOffset <= codeStartOffset)
        return;

    if (!sourceCodeRef.isValid())
        return;

    debugSourceRanges_.push_back({
        .codeStartOffset = codeStartOffset,
        .codeEndOffset   = codeEndOffset,
        .sourceCodeRef   = sourceCodeRef,
    });
}

std::string Encoder::formatRegisterName(MicroReg reg) const
{
    if (!reg.isValid())
        return "inv";

    if (reg.isInstructionPointer())
        return "ip";
    if (reg.isNoBase())
        return "nobase";

    if (reg.isInt())
        return std::format("r{}", reg.index());
    if (reg.isFloat())
        return std::format("f{}", reg.index());
    if (reg.isVirtualInt())
        return std::format("v{}", reg.index());
    if (reg.isVirtualFloat())
        return std::format("vf{}", reg.index());

    return std::format("reg#{}", reg.packed);
}

Encoder::Encoder(TaskContext& ctx) :
    ctx_(&ctx)
{
}

void Encoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
