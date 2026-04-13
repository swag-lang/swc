#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Pre-RA copy elimination on virtual registers.
// Propagates register aliases and removes redundant copies.

class MicroCopyEliminationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "copy-elim"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
