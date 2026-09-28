#pragma once
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class MicroStackAdjustNormalizePass final : public MicroPass
{
public:
    struct InstructionDepth
    {
        MicroInstrRef instRef;
        uint64_t      depth = 0;
    };

    struct AnalyzeResult
    {
        std::vector<InstructionDepth> instructionDepths;
        std::vector<MicroInstrRef>    stackAdjustRefs;
        uint64_t                      frameSize    = 0;
        uint64_t                      minCallDepth = std::numeric_limits<uint64_t>::max();
    };

    std::string_view name() const override { return "stack-adjust-normalize"; }
    Result           run(MicroPassContext& context) override;

private:
    AnalyzeResult analysisResult_;
};

SWC_END_NAMESPACE();
