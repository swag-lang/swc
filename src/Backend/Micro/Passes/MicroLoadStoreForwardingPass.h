#pragma once
#include "Backend/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

class MicroLoadStoreForwardingPass final : public MicroPass
{
public:
    // Forward immediately preceding stores into following loads from the same address.
    std::string_view name() const override { return "load-store-forward"; }
    bool          run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
