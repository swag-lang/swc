#include "pch.h"
#include "Backend/CodeGen/Encoder/Encoder.h"

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
    return *SWC_CHECK_NOT_NULL(store_.ptr<uint8_t>(index));
}

void Encoder::copyTo(std::span<std::byte> dst) const
{
    store_.copyTo(dst);
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

EncoderSymbol* Encoder::getOrAddSymbol(IdentifierRef name, EncoderSymbolKind kind)
{
    symbols_.push_back(EncoderSymbol{name, kind, 0, static_cast<uint32_t>(symbols_.size())});
    return &symbols_.back();
}

void Encoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
