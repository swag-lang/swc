#pragma once
#include "Backend/Micro/MicroPass.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroBuilder;
class TaskContext;
struct MicroInstr;
struct MicroInstrOperand;
class MicroStackAdjustNormalizePass;
class MicroLegalizePass;
class MicroRegisterAllocationPass;
class MicroPrologEpilogPass;
class MicroPrologEpilogSanitizePass;
class MicroEmitPass;

class MicroPassManager
{
public:
    MicroPassManager();
    ~MicroPassManager();

    MicroPassManager(const MicroPassManager&)            = delete;
    MicroPassManager& operator=(const MicroPassManager&) = delete;
    MicroPassManager(MicroPassManager&&) noexcept;
    MicroPassManager& operator=(MicroPassManager&&) noexcept;

    void clear();
    void configureDefaultPipeline(bool optimize);
    void addStartPass(MicroPass& pass) { startPasses_.push_back(&pass); }
    void addLoopPass(MicroPass& pass) { loopPasses_.push_back(&pass); }
    void addFinalPass(MicroPass& pass) { finalPasses_.push_back(&pass); }

    Result run(MicroPassContext& context) const;

private:
    std::vector<MicroPass*> startPasses_;
    std::vector<MicroPass*> loopPasses_;
    std::vector<MicroPass*> finalPasses_;

    std::unique_ptr<MicroStackAdjustNormalizePass> stackAdjustNormalizePass_;
    std::unique_ptr<MicroLegalizePass>             legalizePass_;
    std::unique_ptr<MicroRegisterAllocationPass>   regAllocPass_;
    std::unique_ptr<MicroPrologEpilogPass>         prologEpilogPass_;
    std::unique_ptr<MicroPrologEpilogSanitizePass> prologEpilogSanitizePass_;
    std::unique_ptr<MicroEmitPass>                 emitPass_;
};

SWC_END_NAMESPACE();
