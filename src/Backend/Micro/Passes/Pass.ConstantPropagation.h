#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroConstantPropagationPass final : public MicroPass
{
public:
    MicroConstantPropagationPass();
    ~MicroConstantPropagationPass();

    std::string_view name() const override { return "const-prop"; }
    Result           run(MicroPassContext& context) override;

private:
    struct RunState;
    std::unique_ptr<RunState> runState_;
};

SWC_END_NAMESPACE();
