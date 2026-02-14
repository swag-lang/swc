#include "pch.h"
#include "Backend/MachineCode/Encoder/Encoder.h"

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
    return *store_.ptr<uint8_t>(index);
}

void Encoder::copyTo(std::span<std::byte> dst) const
{
    store_.copyTo(dst);
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
