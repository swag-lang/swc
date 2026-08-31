#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;

namespace PreRaPeephole
{
    struct Action
    {
        static constexpr uint8_t K_MAX_OPS = 8;

        MicroInstrRef     ref            = MicroInstrRef::invalid();
        MicroInstrOpcode  newOp          = MicroInstrOpcode::Nop;
        uint8_t           numOps         = 0;
        MicroInstrOperand ops[K_MAX_OPS] = {};
        bool              erase          = false;
        bool              allocOps       = false;
    };

    struct Context : MicroPeephole::RewriteQueue<Action>
    {
        MicroBuilder* builder = nullptr;
        // Instructions carrying a relocation: rewriting or consuming one
        // would leave the relocation unbound, so claimAll refuses them.
        std::unordered_set<uint32_t> relocated;

        bool isRelocated(MicroInstrRef ref) const { return relocated.contains(ref.get()); }
        bool claimAll(std::initializer_list<MicroInstrRef> refs);
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    using PatternRegistry = MicroPeephole::PatternRegistry<PatternFn>;

    bool     hasVirtualForbiddenPhysRegs(const Context& ctx, MicroReg reg);
    void     mergeVirtualForbiddenRegs(const Context& ctx, MicroReg fromReg, MicroReg toReg);
    bool     buildUseOnlyRegRewrite(Action& outAction, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg fromReg, MicroReg toReg);
    uint64_t extendBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits, bool isSigned);
    void     setMaskedImmediateValue(MicroInstrOperand& op, uint64_t value, MicroOpBits bits);

    // Folds an instruction and its immediate successor into one, when 'buildRewrite' recognizes the
    // pair. The flags check is what makes that safe: the survivor carries the first instruction's
    // flag effect, so nothing downstream may still be reading the second's.
    template<typename BUILD>
    bool tryFoldAdjacentPair(Context& ctx, MicroInstrRef firstRef, const MicroInstr& firstInst, BUILD buildRewrite)
    {
        if (ctx.isClaimed(firstRef))
            return false;

        const MicroInstrRef secondRef = ctx.nextRef(firstRef);
        if (!secondRef.isValid() || ctx.isClaimed(secondRef))
            return false;

        const MicroInstr* secondInst = ctx.instruction(secondRef);
        if (!secondInst)
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, secondRef))
            return false;

        Action rewrite;
        if (!buildRewrite(rewrite, firstInst, ctx.operandsFor(firstRef), *secondInst, ctx.operandsFor(secondRef)))
            return false;

        if (!ctx.claimAll({firstRef, secondRef}))
            return false;

        rewrite.ref = firstRef;
        ctx.actions.push_back(rewrite);
        ctx.emitErase(secondRef);
        return true;
    }

    bool tryForwardConstantLike(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyAddIntoLoadAddress(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardLoadAddr(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryForwardLoadAddrAmc(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryCombineAdjacentRegImm(Context& ctx, MicroInstrRef firstRef, const MicroInstr& firstInst);
}

SWC_END_NAMESPACE();
