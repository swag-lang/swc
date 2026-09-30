#pragma once
#include "Backend/Micro/MicroPass.h"

SWC_BEGIN_NAMESPACE();

// Separate independent scalar-double webs when reusing a stored value's
// register blocks a later load from forwarding. Live joins and destructive
// updates retain a common name; mixed-width and constrained registers stay put.
class MicroWebRenamePass final : public MicroPass
{
public:
    std::string_view name() const override { return "web-rename"; }
    Result           run(MicroPassContext& context) override;
};

SWC_END_NAMESPACE();
