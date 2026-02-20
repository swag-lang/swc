#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroLoadStoreForwardingPass final : public MicroPass
{
public:
    // Forward immediately preceding stores into following loads from the same address.
    MicroPassKind kind() const override { return MicroPassKind::LoadStoreForwarding; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
