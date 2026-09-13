#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct Rewrite
    {
        uint64_t from;
        uint64_t to;
    };

    class ImmediateRewritePass final : public MicroPass
    {
    public:
        ImmediateRewritePass(MicroInstrRef ref, std::span<const Rewrite> rewrites, bool laterSweepsOnly = false) :
            ref_(ref),
            rewrites_(rewrites),
            laterSweepsOnly_(laterSweepsOnly)
        {
        }

        std::string_view name() const override { return "test-immediate-rewrite"; }

        Result run(MicroPassContext& context) override
        {
            ++calls;
            if (laterSweepsOnly_ && context.isFirstOptimizationSweep)
                return Result::Continue;
            auto* ops = context.instructions->ptr(ref_)->ops(*context.operands);
            for (const auto& rewrite : rewrites_)
            {
                if (ops[2].immediateValue().as64() != rewrite.from)
                    continue;
                ops[2].setImmediateValue(ApInt(rewrite.to, 64));
                context.passChanged = true;
                break;
            }
            return Result::Continue;
        }

        uint32_t calls = 0;

    private:
        MicroInstrRef            ref_;
        std::span<const Rewrite> rewrites_;
        bool                     laterSweepsOnly_;
    };
}

SWC_TEST_BEGIN(MicroPassManager_PostRa_RechecksSuffixAfterEachMutation)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
    const auto value = builder.instructions().lastInstructionRef();
    builder.emitRet();

    constexpr Rewrite    steps[] = {{0, 1}, {1, 2}, {2, 3}};
    ImmediateRewritePass prefix(value, steps);
    ImmediateRewritePass suffix(value, {});
    MicroPassManager     manager;
    manager.addPostRaOptimPass(prefix);
    manager.addPostRaOptimPass(suffix);
    MicroPassContext passContext;
    passContext.callConvKind               = CallConvKind::Swag;
    passContext.optimizationIterationLimit = 8;
    SWC_RESULT(builder.runPasses(manager, nullptr, passContext));

    if (builder.instructions().ptr(value)->ops(builder.operands())[2].immediateValue().as64() != 3)
        return Result::Error;
    // Every mutation reactivates the suffix; only the final unchanged sweep skips it.
    if (prefix.calls != 4 || suffix.calls != 3)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPassManager_PostRa_RechecksSuffixWhenFirstSweepPolicyChanges)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
    const auto value = builder.instructions().lastInstructionRef();
    builder.emitRet();

    constexpr Rewrite    first[] = {{0, 1}};
    constexpr Rewrite    later[] = {{1, 2}};
    ImmediateRewritePass prefix(value, first);
    ImmediateRewritePass suffix(value, later, true);
    MicroPassManager     manager;
    manager.addPostRaOptimPass(prefix);
    manager.addPostRaOptimPass(suffix);
    MicroPassContext passContext;
    passContext.callConvKind               = CallConvKind::Swag;
    passContext.optimizationIterationLimit = 8;
    SWC_RESULT(builder.runPasses(manager, nullptr, passContext));

    if (builder.instructions().ptr(value)->ops(builder.operands())[2].immediateValue().as64() != 2)
        return Result::Error;
    if (prefix.calls != 3 || suffix.calls != 3)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroBuilder_PruneRelocationsBeforeRecyclingSlots)
{
    MicroBuilder builder(ctx);
    builder.emitNop();
    const auto first = builder.instructions().lastInstructionRef();
    builder.emitNop();
    const auto dead = builder.instructions().lastInstructionRef();
    builder.emitNop();
    const auto       last = builder.instructions().lastInstructionRef();
    const std::array refs{first, dead, MicroInstrRef::invalid(), first, last, MicroInstrRef(1000)};
    for (uint32_t i = 0; i < refs.size(); ++i)
    {
        MicroRelocation reloc;
        reloc.instructionRef = refs[i];
        reloc.targetAddress  = i;
        builder.codeRelocations().push_back(reloc);
    }

    builder.instructions().erase(dead);
    builder.emitNop();
    if (builder.instructions().lastInstructionRef() == dead)
        return Result::Error;
    if (!builder.pruneDeadRelocations())
        return Result::Error;
    const auto& relocs = builder.codeRelocations();
    if (relocs.size() != 3 || relocs[0].targetAddress != 0 || relocs[1].targetAddress != 3 || relocs[2].targetAddress != 4)
        return Result::Error;
    if (builder.pruneDeadRelocations())
        return Result::Error;

    builder.emitNop();
    if (builder.instructions().lastInstructionRef() != dead)
        return Result::Error;
    for (const auto& reloc : relocs)
    {
        if (reloc.instructionRef == dead)
            return Result::Error;
    }
    builder.instructions().erase(first);
    builder.instructions().erase(last);
    if (!builder.pruneDeadRelocations() || !relocs.empty())
        return Result::Error;

    // Even an empty relocation list must release newly quarantined slots.
    builder.instructions().erase(dead);
    if (builder.pruneDeadRelocations())
        return Result::Error;
    builder.emitNop();
    if (builder.instructions().lastInstructionRef() != dead)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
