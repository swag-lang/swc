#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

// Fold the copy that legacy SSE forces in front of every float binary operation
// into the operation itself.
//
// SSE only writes its result back into one of its inputs, so `c = a * b` is
// built as `c = a` followed by `c *= b`. The copy is not an artifact of register
// allocation - no allocator can remove it, because the destination genuinely has
// to start out holding one of the operands - and it lands squarely in hot loops:
// raytrace's sphere-intersection loop spends 14 of its 102 instructions on them.
//
// AVX's VEX encoding names all three registers, so the copy disappears.

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool hasThreeOperandForm(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::FloatAdd:
                case MicroOp::FloatSubtract:
                case MicroOp::FloatMultiply:
                case MicroOp::FloatDivide:
                case MicroOp::FloatMin:
                case MicroOp::FloatMax:
                case MicroOp::FloatAnd:
                case MicroOp::FloatXor:
                    return true;
                default:
                    return false;
            }
        }

        // The 128-bit packed integer operations the vectorizer emits are in the
        // same position as the scalar float ones: legacy SSE writes the result
        // back into one of its inputs, VEX names all three registers. Their
        // three-operand forms are AVX1, like the float ones, so one encoder
        // capability covers both.
        bool foldableIntoThreeOperand(const MicroOp op, const MicroOpBits opBits)
        {
            if (opBits == MicroOpBits::B128)
                return isVecMicroOp(op);
            return (opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64) && hasThreeOperandForm(op);
        }

        // The integer operations whose two-operand form reads its source from
        // memory. The forms that name a fixed register - a multiply through
        // rax, a shift by cl, the one-operand byte multiply - would hand the
        // encoder a legalization nothing runs any more, so they keep the load.
        bool hasIntegerMemoryOperandForm(const MicroOp op, const MicroOpBits opBits)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                    return true;
                case MicroOp::MultiplySigned:
                    return opBits != MicroOpBits::B8;
                default:
                    return false;
            }
        }

        bool isStandardIntBits(const MicroOpBits opBits)
        {
            return opBits == MicroOpBits::B8 || opBits == MicroOpBits::B16 || opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64;
        }

        // Whether the encoder takes the rewritten form as it stands. The
        // legalization sweep already ran, so a form it would have to rewrite
        // again has nobody left to rewrite it.
        bool encoderAcceptsAsIs(const Context& ctx, const MicroInstrOpcode op, std::span<const MicroInstrOperand> ops)
        {
            MicroInstr probe;
            probe.op          = op;
            probe.numOperands = static_cast<uint8_t>(ops.size());

            MicroConformanceIssue issue;
            return !ctx.encoder->queryConformanceIssue(issue, probe, ops.data());
        }

        // The consumer a reload folds into: a binary operation reading the
        // loaded register as its source, or a compare reading it on the left,
        // which is the side `cmp [mem], reg` names.
        bool isFoldableConsumer(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg loaded, const bool isFloat)
        {
            if (!ops)
                return false;
            if (inst.op == MicroInstrOpcode::OpBinaryRegReg && inst.numOperands >= 4)
                return ops[1].reg == loaded && ops[0].reg != loaded;
            if (isFloat && inst.op == MicroInstrOpcode::OpBinaryRegRegReg && inst.numOperands >= 5)
            {
                if (ops[2].reg != loaded)
                    return false;
                return (ops[0].reg == ops[1].reg && ops[0].reg != loaded) ||
                       (ops[0].reg == loaded && ops[1].reg != loaded);
            }
            if (!isFloat && inst.op == MicroInstrOpcode::CmpRegReg && inst.numOperands >= 3)
                return ops[0].reg == loaded && ops[1].reg != loaded;
            return false;
        }

        struct FloatLaneDemand
        {
            // One bit per 32-bit lane. Unknown control flow preserves all lanes.
            std::array<uint8_t, 32> lanes;

            void reset() { lanes.fill(15); }

            static uint8_t mask(MicroOpBits bits)
            {
                if (bits == MicroOpBits::B32)
                    return 1;
                if (bits == MicroOpBits::B64)
                    return 3;
                return 15;
            }

            void read(MicroReg reg, uint8_t mask)
            {
                if (reg.isFloat())
                    lanes[reg.index()] |= mask;
            }

            void clear(MicroReg reg)
            {
                if (reg.isFloat())
                    lanes[reg.index()] = 0;
            }
        };

        void transferFloatLaneDemand(FloatLaneDemand& demand, const Context& ctx, MicroInstrRef ref)
        {
            const MicroInstr& inst = *ctx.storage->ptr(ref);
            const auto&       info = MicroInstr::info(inst.op);
            if (inst.op == MicroInstrOpcode::Ret && !ctx.isClaimed(ref) && ctx.passContext)
            {
                // Only return values and callee-saved registers survive a return.
                // Keep every lane of those values, including a vector return.
                demand.lanes.fill(0);
                const auto& conv = CallConv::get(ctx.passContext->callConvKind);
                if (ctx.passContext->usesFloatReturnRegOnRet)
                    demand.read(conv.floatReturn, 15);
                for (const MicroReg reg : conv.floatPersistentRegs)
                    demand.read(reg, 15);
                return;
            }
            if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) && !ctx.isClaimed(ref))
            {
                // The call replaces transient values and reads its argument widths.
                // Presence-only calls still preserve every argument lane.
                // Nonvolatile registers carry their actual later demand across it.
                const auto  useDef    = inst.collectUseDef(*ctx.operands, ctx.encoder);
                const auto  floatArgs = inst.callFloatArgs(*ctx.operands);
                const auto& conv      = CallConv::get(useDef.callConv);
                for (const MicroReg defined : useDef.defs)
                    demand.clear(defined);
                for (const MicroReg used : useDef.uses)
                {
                    if (!used.isFloat())
                        continue;
                    const auto    argument = std::ranges::find(conv.floatArgRegs, used);
                    const uint8_t lanes    = argument == conv.floatArgRegs.end() ? 15 : floatArgs.laneMask(static_cast<uint32_t>(argument - conv.floatArgRegs.begin()));
                    demand.read(used, lanes);
                }
                return;
            }
            if (ctx.isClaimed(ref) ||
                (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) && !info.flags.has(MicroInstrFlagsE::JumpInstruction)))
            {
                demand.reset();
                return;
            }
            const auto* ops = inst.ops(*ctx.operands);
            if (!ops)
                return;

            if (inst.op == MicroInstrOpcode::LoadRegReg)
            {
                const uint8_t mask = FloatLaneDemand::mask(ops[2].opBits);
                if (ops[0].reg.isFloat() && ops[1].reg.isFloat())
                {
                    const uint8_t needed = demand.lanes[ops[0].reg.index()];
                    demand.lanes[ops[0].reg.index()] &= ~mask;
                    demand.read(ops[1].reg, needed & mask);
                }
                else
                {
                    demand.clear(ops[0].reg);
                    demand.read(ops[1].reg, mask);
                }
                return;
            }

            if (inst.op == MicroInstrOpcode::ClearReg || inst.op == MicroInstrOpcode::LoadRegMem ||
                inst.op == MicroInstrOpcode::LoadVolatileRegMem || inst.op == MicroInstrOpcode::LoadAmcRegMem ||
                inst.op == MicroInstrOpcode::LoadVecRegMem)
            {
                demand.clear(ops[0].reg);
                return;
            }
            if (inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::StoreVecMemReg)
            {
                demand.read(ops[1].reg, FloatLaneDemand::mask(ops[2].opBits));
                return;
            }
            if (inst.op == MicroInstrOpcode::CmpRegReg)
            {
                const uint8_t mask = FloatLaneDemand::mask(ops[2].opBits);
                demand.read(ops[0].reg, mask);
                demand.read(ops[1].reg, mask);
                return;
            }

            if (inst.op == MicroInstrOpcode::OpTernaryRegRegReg && (ops[4].microOp == MicroOp::FloatAddProduct || ops[4].microOp == MicroOp::FloatSubtractProduct ||
                                                                    ops[4].microOp == MicroOp::FloatProductAdd || ops[4].microOp == MicroOp::FloatProductSubtractFrom))
            {
                const uint8_t mask = FloatLaneDemand::mask(ops[3].opBits);
                demand.read(ops[0].reg, mask);
                demand.read(ops[1].reg, mask);
                demand.read(ops[2].reg, mask);
                return;
            }

            if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[0].reg.isFloat() &&
                (ops[3].opBits == MicroOpBits::B32 || ops[3].opBits == MicroOpBits::B64) &&
                hasThreeOperandForm(ops[4].microOp))
            {
                if (ops[4].microOp == MicroOp::FloatAnd || ops[4].microOp == MicroOp::FloatXor)
                {
                    // Bitwise operations have no cross-lane or exception effects.
                    // Capture the output demand before clearing an aliased input.
                    const uint8_t needed = demand.lanes[ops[0].reg.index()];
                    demand.clear(ops[0].reg);
                    demand.read(ops[1].reg, needed);
                    demand.read(ops[2].reg, needed);
                    return;
                }
                const uint8_t mask  = FloatLaneDemand::mask(ops[3].opBits);
                const uint8_t upper = demand.lanes[ops[0].reg.index()] & ~mask;
                demand.clear(ops[0].reg);
                demand.read(ops[1].reg, mask | upper);
                demand.read(ops[2].reg, mask);
                return;
            }
            const bool indexedBinary = inst.op == MicroInstrOpcode::OpBinaryRegAmcMem;
            const bool scalarBinary  = inst.op == MicroInstrOpcode::OpBinaryRegReg || inst.op == MicroInstrOpcode::OpBinaryRegMem || indexedBinary;
            const auto binaryBits    = scalarBinary ? ops[indexedBinary ? 3 : 2].opBits : MicroOpBits::Zero;
            if (scalarBinary && ops[0].reg.isFloat() && (binaryBits == MicroOpBits::B32 || binaryBits == MicroOpBits::B64))
            {
                const uint8_t mask = FloatLaneDemand::mask(binaryBits);
                const MicroOp op   = ops[info.microOpIndex].microOp;
                if (op == MicroOp::FloatAnd || op == MicroOp::FloatXor)
                {
                    if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
                        demand.read(ops[1].reg, demand.lanes[ops[0].reg.index()]);
                    return;
                }
                if (op == MicroOp::FloatSqrt)
                {
                    const uint8_t upper = demand.lanes[ops[0].reg.index()] & ~mask;
                    demand.clear(ops[0].reg);
                    if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
                        demand.read(ops[1].reg, mask | upper);
                    return;
                }
                if (hasThreeOperandForm(op))
                {
                    demand.read(ops[0].reg, mask);
                    if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
                        demand.read(ops[1].reg, mask);
                    return;
                }
            }

            // Unknown partial writes cannot kill an upper-lane demand.
            const auto useDef = inst.collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg used : useDef.uses)
                demand.read(used, 15);
        }
    }

    namespace
    {
        struct FloatLaneAnalysis
        {
            struct Block
            {
                uint32_t        begin;
                uint32_t        end;
                FloatLaneDemand input{};
            };

            const MicroControlFlowGraph*   cfg = nullptr;
            std::span<const MicroInstrRef> refs;
            std::vector<Block>             blocks;
            std::vector<uint32_t>          blockFor;
            std::vector<uint32_t>          pending;
            std::vector<bool>              queued;

            FloatLaneDemand outputDemand(const Block& block) const
            {
                FloatLaneDemand demand{};
                const auto&     successors = cfg->successors(block.end - 1);
                if (successors.empty())
                    demand.reset();
                for (const uint32_t successor : successors)
                    for (size_t reg = 0; reg < demand.lanes.size(); ++reg)
                        demand.lanes[reg] |= blocks[blockFor[successor]].input.lanes[reg];
                return demand;
            }

            bool build(Context& ctx)
            {
                if (!ctx.builder)
                    return false;
                cfg = &ctx.builder->controlFlowGraph();
                if (!cfg->supportsDeadCodeLiveness() || cfg->hasUnsupportedControlFlowForCfgLiveness())
                    return false;
                refs = cfg->instructionRefs();
                blocks.clear();
                blockFor.resize(refs.size());
                uint32_t begin = 0;
                for (uint32_t i = 0; i < refs.size(); ++i)
                {
                    blockFor[i]            = static_cast<uint32_t>(blocks.size());
                    const auto& successors = cfg->successors(i);
                    if (i + 1 < refs.size() && successors.size() == 1 && successors[0] == i + 1 &&
                        cfg->predecessors(i + 1).size() == 1)
                        continue;
                    blocks.push_back({begin, i + 1});
                    begin = i + 1;
                }
                pending.clear();
                queued.assign(blocks.size(), true);
                for (uint32_t i = 0; i < blocks.size(); ++i)
                    pending.push_back(i);
                while (!pending.empty())
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    queued[index] = false;
                    auto& block   = blocks[index];
                    auto  demand  = outputDemand(block);
                    for (uint32_t i = block.end; i > block.begin;)
                        transferFloatLaneDemand(demand, ctx, refs[--i]);
                    if (demand.lanes == block.input.lanes)
                        continue;
                    block.input = demand;
                    for (const uint32_t predecessor : cfg->predecessors(block.begin))
                    {
                        const uint32_t predecessorBlock = blockFor[predecessor];
                        if (!queued[predecessorBlock])
                        {
                            queued[predecessorBlock] = true;
                            pending.push_back(predecessorBlock);
                        }
                    }
                }
                return true;
            }

            FloatLaneDemand after(Context& ctx, MicroInstrRef ref) const
            {
                const uint32_t index = cfg->indexOf(ref);
                SWC_ASSERT(index < refs.size());
                const auto& block  = blocks[blockFor[index]];
                auto        demand = outputDemand(block);
                for (uint32_t i = block.end; i > index + 1;)
                    transferFloatLaneDemand(demand, ctx, refs[--i]);
                return demand;
            }
        };

        uint8_t floatLanesReadAfter(Context& ctx, MicroInstrRef afterRef, MicroReg reg, uint8_t requested = 15)
        {
            if (!reg.isFloat() || ctx.isClaimed(afterRef))
                return 15;
            // Stop where another edge may enter or leave. Unknown successors keep
            // every lane live; intervening complete definitions can still kill it.
            // Pending rewrites are opaque, as in the function-wide lane analysis.
            thread_local std::vector<MicroInstrRef> suffix;
            suffix.clear();
            for (auto ref = ctx.nextRef(afterRef); ref.isValid(); ref = ctx.nextRef(ref))
            {
                const auto* inst = ctx.instruction(ref);
                if (!inst || inst->op == MicroInstrOpcode::Label)
                    break;
                suffix.push_back(ref);
                const auto flags = MicroInstr::info(inst->op).flags;
                if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    break;
            }
            FloatLaneDemand demand;
            demand.reset();
            for (const auto ref : std::views::reverse(suffix))
                transferFloatLaneDemand(demand, ctx, ref);
            if (!(demand.lanes[reg.index()] & requested))
                return 0;
            // A branch is not itself a use. Reuse the full lane solver when the
            // local suffix cannot decide, rebuilding against current queued claims.
            thread_local FloatLaneAnalysis analysis;
            if (analysis.build(ctx))
                return analysis.after(ctx, afterRef).lanes[reg.index()] & requested;
            return demand.lanes[reg.index()] & requested;
        }
    }

    bool areFloatUpperLanesDeadAfter(Context& ctx, MicroInstrRef afterRef, MicroReg reg, MicroOpBits copiedBits)
    {
        if (copiedBits == MicroOpBits::B128)
            return true;
        return !floatLanesReadAfter(ctx, afterRef, reg, static_cast<uint8_t>(15 & ~FloatLaneDemand::mask(copiedBits)));
    }

    namespace
    {
        struct ScalarFloatBinary
        {
            MicroReg    dst;
            MicroReg    left;
            MicroReg    right;
            MicroOpBits bits;
            MicroOp     op;
        };

        bool scalarFloatBinary(ScalarFloatBinary& out, const MicroInstr& inst, const MicroOperandStorage& operands)
        {
            const auto* ops = inst.ops(operands);
            if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
                out = {ops[0].reg, ops[0].reg, ops[1].reg, ops[2].opBits, ops[3].microOp};
            else if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg)
                out = {ops[0].reg, ops[1].reg, ops[2].reg, ops[3].opBits, ops[4].microOp};
            else
                return false;
            return out.dst.isFloat() && out.left.isFloat() && out.right.isFloat() &&
                   (out.bits == MicroOpBits::B32 || out.bits == MicroOpBits::B64);
        }

        bool tryFuseScalarFloatProduct(Context& ctx, FloatLaneDemand& demand, MicroInstrRef multiplyRef, MicroInstrRef accumulateRef)
        {
            if (ctx.isClaimed(multiplyRef) || ctx.isClaimed(accumulateRef))
                return false;
            ScalarFloatBinary multiply;
            ScalarFloatBinary accumulate;
            if (!scalarFloatBinary(multiply, *ctx.storage->ptr(multiplyRef), *ctx.operands) ||
                !scalarFloatBinary(accumulate, *ctx.storage->ptr(accumulateRef), *ctx.operands) ||
                multiply.op != MicroOp::FloatMultiply || (accumulate.op != MicroOp::FloatAdd && accumulate.op != MicroOp::FloatSubtract) || multiply.bits != accumulate.bits)
                return false;

            MicroReg addend;
            if (accumulate.right == multiply.dst)
                addend = accumulate.left;
            else if (accumulate.op == MicroOp::FloatAdd && accumulate.left == multiply.dst)
                addend = accumulate.right;
            else
                return false;
            if (addend == multiply.dst)
                return false;

            MicroInstrOperand fused[5] = {};
            fused[0].reg               = accumulate.dst;
            fused[3].opBits            = accumulate.bits;
            if (accumulate.dst == addend)
            {
                fused[1].reg     = multiply.left;
                fused[2].reg     = multiply.right;
                fused[4].microOp = accumulate.op == MicroOp::FloatAdd ? MicroOp::FloatAddProduct : MicroOp::FloatSubtractProduct;
            }
            else if (accumulate.dst == multiply.left || accumulate.dst == multiply.right)
            {
                fused[1].reg     = accumulate.dst == multiply.left ? multiply.right : multiply.left;
                fused[2].reg     = addend;
                fused[4].microOp = accumulate.op == MicroOp::FloatAdd ? MicroOp::FloatProductAdd : MicroOp::FloatProductSubtractFrom;
            }
            else
                return false;

            // A distinct product must die in every lane, including lanes retained by
            // later scalar writes. Reusing its register for the final result is safe.
            if (multiply.dst != accumulate.dst && demand.lanes[multiply.dst.index()])
                return false;
            // Scalar binary forms copy upper lanes from their first input. Fused
            // forms retain dst instead, so any different upper source must die.
            const MicroReg upperSource = accumulate.left == multiply.dst ? multiply.left : accumulate.left;
            if (upperSource != accumulate.dst && (demand.lanes[accumulate.dst.index()] & ~FloatLaneDemand::mask(accumulate.bits)))
                return false;
            if (!encoderAcceptsAsIs(ctx, MicroInstrOpcode::OpTernaryRegRegReg, fused))
                return false;
            auto before = demand;
            transferFloatLaneDemand(before, ctx, accumulateRef);
            transferFloatLaneDemand(before, ctx, multiplyRef);
            if (!ctx.claimAll({multiplyRef, accumulateRef}))
                return false;
            demand = before;
            ctx.emitErase(multiplyRef);
            ctx.emitRewrite(accumulateRef, MicroInstrOpcode::OpTernaryRegRegReg, fused, true);
            return true;
        }
    }

    namespace
    {
        // A product and the accumulation that consumes it are often separated by the load of
        // the accumulator, which the allocator schedules right before its use: `p = a * b`,
        // `v = [m]`, `v -= p`. The pair still contracts when nothing in between reads or writes
        // the product or writes either factor - the fused form reads the factors where the
        // accumulation stands. Look a few instructions back for such a product.
        constexpr uint32_t K_MAX_PRODUCT_GAP = 6;

        bool findSeparatedProduct(Context& ctx, std::span<const MicroInstrRef> refs, uint32_t blockBegin, uint32_t accumulateIndex, uint32_t& outMultiplyIndex)
        {
            ScalarFloatBinary accumulate;
            if (!scalarFloatBinary(accumulate, *ctx.storage->ptr(refs[accumulateIndex]), *ctx.operands) ||
                (accumulate.op != MicroOp::FloatAdd && accumulate.op != MicroOp::FloatSubtract))
                return false;

            MicroInstrUseDef useDef;
            for (uint32_t back = 2; back <= K_MAX_PRODUCT_GAP && accumulateIndex >= blockBegin + back; ++back)
            {
                const uint32_t    candidateIndex = accumulateIndex - back;
                const MicroInstr* candidate      = ctx.storage->ptr(refs[candidateIndex]);
                ScalarFloatBinary multiply;
                if (!candidate || ctx.isClaimed(refs[candidateIndex]) || !scalarFloatBinary(multiply, *candidate, *ctx.operands) ||
                    multiply.op != MicroOp::FloatMultiply || (multiply.dst != accumulate.left && multiply.dst != accumulate.right))
                    continue;

                for (uint32_t gap = candidateIndex + 1; gap < accumulateIndex; ++gap)
                {
                    const MicroInstr* inst = ctx.storage->ptr(refs[gap]);
                    if (!inst || ctx.isClaimed(refs[gap]))
                        return false;
                    const auto flags = MicroInstr::info(inst->op).flags;
                    if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction))
                        return false;
                    inst->collectUseDef(useDef, *ctx.operands, ctx.encoder);
                    if (std::ranges::find(useDef.uses, multiply.dst) != useDef.uses.end())
                        return false;
                    for (const MicroReg def : useDef.defs)
                    {
                        if (def == multiply.dst || def == multiply.left || def == multiply.right)
                            return false;
                    }
                }

                outMultiplyIndex = candidateIndex;
                return true;
            }

            return false;
        }
    }

    // MOVSS/MOVSD retain the old destination's upper lanes. A complete copy
    // removes that dependency whenever no reachable consumer needs those lanes.
    // Solve demands over straight-line blocks so a scalar use beyond a branch
    // does not make all four lanes live. The same proof permits contraction when
    // the product is dead in every lane and the floating policy allows FMA.
    // Pending rewrites stay opaque.
    void optimizeScalarFloatInstructions(Context& ctx)
    {
        if (!ctx.builder)
            return;
        const auto& cfg = ctx.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return;
        const bool allowFusion = ctx.encoder && ctx.encoder->supportsFusedFloatMultiplyAdd() && ctx.builder->backendBuildCfg().fpMathFma;
        const auto refs        = cfg.instructionRefs();
        bool       candidate   = false;
        for (const auto ref : refs)
        {
            const auto* inst = ctx.storage->ptr(ref);
            if (ctx.isClaimed(ref))
                continue;
            ScalarFloatBinary binary;
            if (allowFusion && scalarFloatBinary(binary, *inst, *ctx.operands) && (binary.op == MicroOp::FloatAdd || binary.op == MicroOp::FloatSubtract))
            {
                candidate = true;
                break;
            }
            if (inst->op != MicroInstrOpcode::LoadRegReg)
                continue;
            const auto* ops = inst->ops(*ctx.operands);
            if (ops[0].reg.isFloat() && ops[1].reg.isFloat() && ops[0].reg != ops[1].reg &&
                (ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64))
            {
                candidate = true;
                break;
            }
        }
        if (!candidate)
            return;

        thread_local FloatLaneAnalysis analysis;
        if (!analysis.build(ctx))
            return;

        for (const auto& block : analysis.blocks)
        {
            auto demand = analysis.outputDemand(block);
            for (uint32_t i = block.end; i > block.begin;)
            {
                const auto  ref  = refs[--i];
                const auto* inst = ctx.storage->ptr(ref);
                const auto* ops  = inst->ops(*ctx.operands);
                if (allowFusion && i > block.begin && tryFuseScalarFloatProduct(ctx, demand, refs[i - 1], ref))
                {
                    --i;
                    continue;
                }
                // The instructions between a separated product and its accumulation stay in
                // place and are walked next; the claimed product is erased.
                uint32_t multiplyIndex = 0;
                if (allowFusion && findSeparatedProduct(ctx, refs, block.begin, i, multiplyIndex) &&
                    tryFuseScalarFloatProduct(ctx, demand, refs[multiplyIndex], ref))
                    continue;
                bool widen = false;
                if (inst->op == MicroInstrOpcode::LoadRegReg && !ctx.isClaimed(ref) &&
                    ops[0].reg.isFloat() && ops[1].reg.isFloat() && ops[0].reg != ops[1].reg &&
                    (ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64))
                    widen = !(demand.lanes[ops[0].reg.index()] & ~FloatLaneDemand::mask(ops[2].opBits));
                transferFloatLaneDemand(demand, ctx, ref);
                if (widen && ctx.claimAll({ref}))
                {
                    MicroInstrOperand wide[3] = {ops[0], ops[1], ops[2]};
                    wide[2].opBits            = MicroOpBits::B128;
                    ctx.emitRewrite(ref, inst->op, wide);
                }
            }
        }
    }

    // A retained integer copy need not sit on the floating consumer's path:
    // load float first, then capture its unchanged bits in the integer cache.
    // Both values and the memory access stay in place; the immediate consumer
    // can start without waiting for a general-register-to-XMM transfer.
    bool tryLoadIntoFirstFloatConsumer(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder)
            return false;
        const auto* load = inst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || ctx.isPrivateFrameBase(load[0].reg) ||
            (load[2].opBits != MicroOpBits::B32 && load[2].opBits != MicroOpBits::B64))
            return false;
        const auto  copyRef  = ctx.nextRef(ref);
        const auto* copyInst = ctx.instruction(copyRef);
        const auto* copy     = copyInst ? copyInst->ops(*ctx.operands) : nullptr;
        if (!copyInst || copyInst->op != MicroInstrOpcode::LoadRegReg || !copy ||
            !copy[0].reg.isFloat() || copy[1].reg != load[0].reg || copy[2].opBits != load[2].opBits)
            return false;
        const auto  consumerRef = ctx.nextRef(copyRef);
        const auto* consumer    = ctx.instruction(consumerRef);
        if (!consumer || ctx.isClaimed(consumerRef) ||
            (consumer->op != MicroInstrOpcode::OpBinaryRegReg && consumer->op != MicroInstrOpcode::OpBinaryRegMem &&
             consumer->op != MicroInstrOpcode::OpBinaryRegRegReg && consumer->op != MicroInstrOpcode::CmpRegReg))
            return false;
        const auto useDef = consumer->collectUseDef(*ctx.operands, ctx.encoder);
        if (std::ranges::find(useDef.uses, copy[0].reg) == useDef.uses.end() ||
            std::ranges::find(useDef.uses, load[0].reg) != useDef.uses.end())
            return false;

        MicroInstrOperand directLoad[4]   = {load[0], load[1], load[2], load[3]};
        directLoad[0].reg                 = copy[0].reg;
        MicroInstrOperand retainedCopy[3] = {copy[0], copy[1], copy[2]};
        retainedCopy[0].reg               = load[0].reg;
        retainedCopy[1].reg               = copy[0].reg;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, inst, directLoad) ||
            ctx.encoder->queryConformanceIssue(issue, *copyInst, retainedCopy) || !ctx.claimAll({ref, copyRef}))
            return false;
        ctx.emitRewrite(ref, inst.op, directLoad);
        ctx.emitRewrite(copyRef, copyInst->op, retainedCopy);
        return true;
    }

    bool tryFoldLoadIntoTest(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder)
            return false;
        const auto* load = inst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() ||
            (!load[1].reg.isInt() && !load[1].reg.isInstructionPointer()) ||
            ctx.isPrivateFrameBase(load[0].reg))
            return false;
        const MicroInstrRef testRef = ctx.nextRef(ref);
        const MicroInstr*   test    = ctx.instruction(testRef);
        if (!test || (test->op != MicroInstrOpcode::TestRegImm && test->op != MicroInstrOpcode::TestRegReg))
            return false;
        const auto* testOps = test->ops(*ctx.operands);
        const bool  regTest = test->op == MicroInstrOpcode::TestRegReg;
        if (!testOps)
            return false;
        const MicroOpBits testBits = regTest ? testOps[2].opBits : testOps[1].opBits;
        if (testOps[0].reg != load[0].reg ||
            (regTest && (!testOps[1].reg.isInt() || testOps[1].reg == load[0].reg)) ||
            getNumBits(testBits) > getNumBits(load[2].opBits) ||
            !ctx.isRegDeadAfter(load[0].reg, ctx.instructionIndex + 1))
            return false;

        MicroInstrOperand rewritten[4] = {};
        if (regTest)
        {
            rewritten[0] = load[1];
            rewritten[1] = testOps[1];
            rewritten[2] = testOps[2];
            rewritten[3] = load[3];
        }
        else
        {
            rewritten[0] = load[1];
            rewritten[1] = testOps[1];
            rewritten[2] = load[3];
            rewritten[3] = testOps[2];
        }
        MicroInstr probe  = *test;
        probe.op          = regTest ? MicroInstrOpcode::TestMemReg : MicroInstrOpcode::TestMemImm;
        probe.numOperands = 4;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, probe, rewritten) || !ctx.claimAll({ref, testRef}))
            return false;
        ctx.emitRewrite(ref, probe.op, rewritten);
        ctx.emitErase(testRef);
        return true;
    }

    bool tryFoldLoadIntoNarrowExtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder)
            return false;
        const auto* load = inst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || !load[1].reg.isInt() ||
            load[1].reg.isInstructionPointer() || ctx.isPrivateFrameBase(load[0].reg) ||
            (load[2].opBits != MicroOpBits::B32 && load[2].opBits != MicroOpBits::B64))
            return false;

        MicroInstrRef     extRef    = ctx.nextRef(ref);
        const MicroInstr* ext       = ctx.instruction(extRef);
        MicroInstrRef     shiftRef  = MicroInstrRef::invalid();
        uint64_t          shiftBits = 0;
        uint32_t          extIndex  = ctx.instructionIndex + 1;
        if (ext && ext->op == MicroInstrOpcode::OpBinaryRegImm)
        {
            const auto* shift = ext->ops(*ctx.operands);
            if (!shift || shift[0].reg != load[0].reg || shift[2].microOp != MicroOp::ShiftRight ||
                shift[3].hasWideImmediateValue() || shift[3].valueU64 >= getNumBits(shift[1].opBits) ||
                (shift[3].valueU64 & 7) != 0)
                return false;
            shiftBits = shift[3].valueU64;
            shiftRef  = extRef;
            extRef    = ctx.nextRef(extRef);
            ext       = ctx.instruction(extRef);
            ++extIndex;
        }
        if (!ext || ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* narrow = ext->ops(*ctx.operands);
        if (!narrow || narrow[1].reg != load[0].reg || !narrow[0].reg.isInt() || ctx.isPrivateFrameBase(narrow[0].reg) ||
            (narrow[2].opBits != MicroOpBits::B32 && narrow[2].opBits != MicroOpBits::B64) ||
            (narrow[3].opBits != MicroOpBits::B8 && narrow[3].opBits != MicroOpBits::B16 && narrow[3].opBits != MicroOpBits::B32) ||
            getNumBits(narrow[2].opBits) <= getNumBits(narrow[3].opBits) ||
            shiftBits + getNumBits(narrow[3].opBits) > getNumBits(load[2].opBits))
            return false;
        if (shiftRef.isValid())
        {
            const auto* shift = ctx.operandsFor(shiftRef);
            if (shiftBits + getNumBits(narrow[3].opBits) > getNumBits(shift[1].opBits) ||
                !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, extRef, ctx.builder))
                return false;
        }
        if (narrow[0].reg != load[0].reg && !ctx.isRegDeadAfter(load[0].reg, extIndex))
            return false;

        // Read the selected bytes at the original load's position. The x64
        // byte order turns an aligned right shift into a displacement.
        MicroInstrOperand rewritten[5] = {};
        rewritten[0]                   = narrow[0];
        rewritten[1]                   = load[1];
        rewritten[2]                   = narrow[2];
        rewritten[3]                   = narrow[3];
        rewritten[4].valueU64          = load[3].valueU64 + shiftBits / 8;
        MicroInstr probe               = inst;
        probe.op                       = MicroInstrOpcode::LoadZeroExtRegMem;
        probe.numOperands              = 5;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, probe, rewritten))
            return false;
        if (shiftRef.isValid() ? !ctx.claimAll({ref, shiftRef, extRef}) : !ctx.claimAll({ref, extRef}))
            return false;
        ctx.emitRewrite(ref, probe.op, rewritten, true);
        if (shiftRef.isValid())
            ctx.emitErase(shiftRef);
        ctx.emitErase(extRef);
        return true;
    }

    // A scalar integer conversion only defines the low f32/f64 lane. The IR
    // therefore models it as reading the destination and normally clears that
    // register first. At an immediate scalar ABI return the upper lanes are
    // unobservable, so the clear is pure encoding overhead.
    bool tryEraseScalarReturnConversionClear(Context& ctx, const MicroInstrRef clearRef, const MicroInstr& clearInst)
    {
        if (ctx.isClaimed(clearRef) ||
            !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
            return false;
        const auto* clear = clearInst.ops(*ctx.operands);
        if (!clear || clear[0].reg != ctx.floatReturn ||
            (clear[1].opBits != MicroOpBits::B32 && clear[1].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef convertRef = ctx.nextRef(clearRef);
        const MicroInstr*   convert    = ctx.instruction(convertRef);
        const auto*         convertOps = convert ? convert->ops(*ctx.operands) : nullptr;
        if (!convert || convert->op != MicroInstrOpcode::OpBinaryRegReg || !convertOps ||
            convertOps[0].reg != clear[0].reg || !convertOps[1].reg.isInt() ||
            convertOps[2].opBits != clear[1].opBits ||
            (convertOps[3].microOp != MicroOp::ConvertIntToFloat && convertOps[3].microOp != MicroOp::ConvertInt64ToFloat32 &&
             convertOps[3].microOp != MicroOp::ConvertInt32ToFloat64))
            return false;

        const MicroInstrRef retRef = ctx.nextRef(convertRef);
        const MicroInstr*   ret    = ctx.instruction(retRef);
        if (!ret || ret->op != MicroInstrOpcode::Ret || !ctx.claimAll({clearRef, convertRef}))
            return false;

        ctx.emitErase(clearRef);
        return true;
    }

    // Compare a scalar against its indexed source without staging that source
    // in another XMM register. The source register must die at the compare.
    bool tryFoldIndexedFloatCompare(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (loadInst.op != MicroInstrOpcode::LoadAmcRegMem || loadInst.numOperands < 8)
            return false;

        const MicroInstrOperand* loadOps = ctx.operandsFor(loadRef);
        if (!loadOps || !loadOps[0].reg.isFloat() || !loadOps[1].reg.isInt() || !loadOps[2].reg.isInt() ||
            loadOps[3].opBits != loadOps[4].opBits ||
            (loadOps[3].opBits != MicroOpBits::B32 && loadOps[3].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef      cmpRef  = ctx.nextRef(loadRef);
        const MicroInstr*        cmpInst = ctx.instruction(cmpRef);
        const MicroInstrOperand* cmpOps  = ctx.operandsFor(cmpRef);
        if (!cmpInst || cmpInst->op != MicroInstrOpcode::CmpRegReg || cmpInst->numOperands < 3 || !cmpOps ||
            !cmpOps[0].reg.isFloat() || cmpOps[1].reg != loadOps[0].reg ||
            cmpOps[0].reg == loadOps[0].reg || cmpOps[2].opBits != loadOps[3].opBits ||
            (!regIsDeadAfter(ctx, cmpRef, loadOps[0].reg) &&
             !ctx.isRegDeadAfter(loadOps[0].reg, ctx.instructionIndex + 1)))
            return false;

        MicroInstrOperand rewritten[7] = {};
        rewritten[0]                   = cmpOps[0];
        rewritten[1]                   = loadOps[1];
        rewritten[2]                   = loadOps[2];
        rewritten[3]                   = cmpOps[2];
        rewritten[4]                   = loadOps[4];
        rewritten[5]                   = loadOps[5];
        rewritten[6]                   = loadOps[6];
        if (!ctx.claimAll({loadRef, cmpRef}))
            return false;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegAmc, std::span{rewritten, 7}, true);
        ctx.emitErase(loadRef);
        return true;
    }

    // Add a scalar to an indexed accumulator in place. The stored result can
    // use the other addend as its destination when both values die here.
    bool tryFoldIndexedFloatAccumulation(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (loadInst.op != MicroInstrOpcode::LoadAmcRegMem || loadInst.numOperands < 8)
            return false;

        const MicroInstrOperand* loadOps = ctx.operandsFor(loadRef);
        if (!loadOps || !loadOps[0].reg.isFloat() ||
            loadOps[3].opBits != loadOps[4].opBits ||
            (loadOps[3].opBits != MicroOpBits::B32 && loadOps[3].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef      addRef  = ctx.nextRef(loadRef);
        const MicroInstr*        addInst = ctx.instruction(addRef);
        const MicroInstrOperand* addOps  = ctx.operandsFor(addRef);
        if (!addInst || addInst->op != MicroInstrOpcode::OpBinaryRegReg || addInst->numOperands < 4 || !addOps ||
            addOps[0].reg != loadOps[0].reg || !addOps[1].reg.isFloat() ||
            addOps[1].reg == loadOps[0].reg || addOps[2].opBits != loadOps[3].opBits ||
            addOps[3].microOp != MicroOp::FloatAdd)
            return false;

        const MicroInstrRef      storeRef  = ctx.nextRef(addRef);
        const MicroInstr*        storeInst = ctx.instruction(storeRef);
        const MicroInstrOperand* storeOps  = ctx.operandsFor(storeRef);
        if (!storeInst || storeInst->op != MicroInstrOpcode::LoadAmcMemReg || storeInst->numOperands < 8 || !storeOps ||
            storeOps[0].reg != loadOps[1].reg || storeOps[1].reg != loadOps[2].reg ||
            storeOps[2].reg != loadOps[0].reg || storeOps[3].opBits != MicroOpBits::B64 ||
            storeOps[4].opBits != loadOps[4].opBits ||
            storeOps[5].valueU64 != loadOps[5].valueU64 ||
            storeOps[6].valueU64 != loadOps[6].valueU64)
            return false;

        const MicroReg addend     = addOps[1].reg;
        const MicroReg loaded     = loadOps[0].reg;
        const uint32_t storeIndex = ctx.instructionIndex + 2;
        if ((!regIsDeadAfter(ctx, storeRef, addend) && !ctx.isRegDeadAfter(addend, storeIndex)) ||
            (!regIsDeadAfter(ctx, storeRef, loaded) && !ctx.isRegDeadAfter(loaded, storeIndex)) ||
            !ctx.claimAll({loadRef, addRef, storeRef}))
            return false;

        MicroInstrOperand newAddOps[8] = {};
        newAddOps[0].reg               = addend;
        newAddOps[1].reg               = loadOps[1].reg;
        newAddOps[2].reg               = loadOps[2].reg;
        newAddOps[3].opBits            = loadOps[3].opBits;
        newAddOps[4].opBits            = storeOps[3].opBits;
        newAddOps[5]                   = loadOps[5];
        newAddOps[6]                   = loadOps[6];
        newAddOps[7].microOp           = MicroOp::FloatAdd;

        MicroInstrOperand newStoreOps[8] = {};
        for (uint32_t i = 0; i < 8; ++i)
            newStoreOps[i] = storeOps[i];
        newStoreOps[2].reg = addend;

        ctx.emitRewrite(addRef, MicroInstrOpcode::OpBinaryRegAmcMem, std::span{newAddOps, 8}, true);
        ctx.emitRewrite(storeRef, MicroInstrOpcode::LoadAmcMemReg, std::span{newStoreOps, 8}, true);
        ctx.emitErase(loadRef);
        return true;
    }

    // Fold an operand's reload into the operation that consumes it.
    //
    // x86 arithmetic can read one operand straight from memory, but the
    // encoder only ever built the register form, so every value coming out of a
    // spill slot cost a separate load. raytrace's inner loop reloads twenty-two
    // times; each fold turns two instructions into one and frees the scratch
    // register the value was staged in. The integer side covers the same
    // shape for the operations x64 reads from memory, and a compare whose
    // left operand is the reload.
    bool tryFoldLoadIntoBinary(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        const bool indexed = loadInst.op == MicroInstrOpcode::LoadAmcRegMem;
        if ((!indexed && loadInst.op != MicroInstrOpcode::LoadRegMem) || loadInst.numOperands < (indexed ? 7 : 4))
            return false;

        const MicroInstrOperand* loadOps = ctx.operandsFor(loadRef);
        if (!loadOps)
            return false;

        const MicroReg loaded  = loadOps[0].reg;
        const MicroReg base    = loadOps[1].reg;
        const MicroReg index   = indexed ? loadOps[2].reg : MicroReg::invalid();
        const bool     isFloat = loaded.isFloat();
        if ((!isFloat && !loaded.isAnyInt()) || base.isFloat() || !base.isValid() ||
            (indexed && (!index.isValid() || index.isFloat())))
            return false;

        // A RIP-relative load carries the constant's relocation. The folded
        // arithmetic instruction can carry it instead, but only when this is
        // the one ordinary rel32 relocation the memory form expects.
        MicroRelocation* loadRelocation = nullptr;
        if (base.isInstructionPointer())
        {
            if (!isFloat || !ctx.builder)
                return false;
            for (MicroRelocation& relocation : ctx.builder->codeRelocations())
            {
                if (relocation.instructionRef != loadRef)
                    continue;
                if (loadRelocation || relocation.form != MicroRelocation::Form::Relative32)
                    return false;
                loadRelocation = &relocation;
            }
            if (!loadRelocation)
                return false;
        }

        // The integer rewrite is probed against the encoder before it lands.
        if (!isFloat && !ctx.encoder)
            return false;

        const MicroOpBits opBits = loadOps[indexed ? 3 : 2].opBits;
        if (isFloat ? (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64) : !isStandardIntBits(opBits))
            return false;

        constexpr uint32_t kMaxScan = 12;

        MicroInstrRef     opRef   = ctx.nextRef(loadRef);
        const MicroInstr* opInst  = nullptr;
        uint32_t          opIndex = ctx.instructionIndex + 1;
        for (uint32_t step = 0; step < kMaxScan; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (isFoldableConsumer(*candidate, ctx.operandsFor(opRef), loaded, isFloat))
            {
                opInst = candidate;
                break;
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrDef& info = MicroInstr::info(candidate->op);
            if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            // The read moves later, so anything that could change what it sees
            // stops the fold: a write to the address register, and any store at
            // all - this pass has no aliasing information.
            if (info.flags.has(MicroInstrFlagsE::WritesMemory))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == loaded || reg == base || (indexed && reg == index))
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == loaded)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
            ++opIndex;
        }

        if (!opInst)
            return false;

        if (loadRelocation)
            for (const MicroRelocation& relocation : ctx.builder->codeRelocations())
                if (&relocation != loadRelocation && relocation.instructionRef == opRef)
                    return false;

        const MicroInstrOperand* consumerOps = ctx.operandsFor(opRef);
        if (!consumerOps)
            return false;

        if (opInst->op == MicroInstrOpcode::CmpRegReg)
        {
            // The register only existed to carry the loaded value across; if
            // anything reads it afterwards it has to keep existing.
            if (!regIsDeadAfter(ctx, opRef, loaded) && !ctx.isRegDeadAfter(loaded, opIndex))
                return false;
            if (indexed)
                return false;
            if (consumerOps[2].opBits != opBits || !consumerOps[1].reg.isAnyInt())
                return false;

            MicroInstrOperand newOps[4] = {};
            newOps[0].reg               = base;
            newOps[1].reg               = consumerOps[1].reg;
            newOps[2].opBits            = opBits;
            newOps[3].valueU64          = loadOps[3].valueU64;
            if (!encoderAcceptsAsIs(ctx, MicroInstrOpcode::CmpMemReg, std::span{newOps, 4}))
                return false;
            if (!ctx.claimAll({loadRef, opRef}))
                return false;

            ctx.emitRewrite(opRef, MicroInstrOpcode::CmpMemReg, std::span{newOps, 4}, true);
            ctx.emitErase(loadRef);
            return true;
        }

        const bool        threeOperand = opInst->op == MicroInstrOpcode::OpBinaryRegRegReg;
        const MicroOpBits consumerBits = consumerOps[threeOperand ? 3 : 2].opBits;
        const MicroOp     op           = consumerOps[threeOperand ? 4 : 3].microOp;
        if (consumerBits != opBits)
            return false;
        if (isFloat ? (!hasThreeOperandForm(op) || !consumerOps[0].reg.isFloat()) : (!hasIntegerMemoryOperandForm(op, opBits) || !consumerOps[0].reg.isAnyInt()))
            return false;
        // FloatAnd/FloatXor use the packed 128-bit SSE memory form even for a
        // scalar value. A scalar load may read only four or eight bytes from
        // an address that is not 16-byte aligned (including stack spills),
        // while ANDPS/ANDPD and XORPS/XORPD require an aligned full vector.
        // Keep the scalar load for these operations.
        if (op == MicroOp::FloatAnd || op == MicroOp::FloatXor)
            return false;

        MicroInstrRef sourceCopyRef = MicroInstrRef::invalid();
        if (threeOperand && consumerOps[0].reg == loaded)
        {
            // Allocation can preserve the original destination in a temporary,
            // load the constant over the destination, then use both in a VEX
            // operation. Removing the load restores the original destination;
            // the temporary copy and the third operand then both disappear.
            sourceCopyRef                     = ctx.previousRef(loadRef);
            const MicroInstr*        copyInst = ctx.instruction(sourceCopyRef);
            const MicroInstrOperand* copyOps  = copyInst ? copyInst->ops(*ctx.operands) : nullptr;
            if (!copyInst || copyInst->op != MicroInstrOpcode::LoadRegReg || !copyOps ||
                copyOps[0].reg != consumerOps[1].reg || copyOps[1].reg != loaded || copyOps[2].opBits != opBits)
                return false;
            const MicroReg copied = copyOps[0].reg;
            if (!regIsDeadAfter(ctx, opRef, copied) && !ctx.isRegDeadAfter(copied, opIndex))
                return false;
        }
        else if (!regIsDeadAfter(ctx, opRef, loaded) && !ctx.isRegDeadAfter(loaded, opIndex))
        {
            return false;
        }

        MicroInstrOpcode  rewrittenOp = MicroInstrOpcode::OpBinaryRegMem;
        MicroInstrOperand newOps[8]   = {};
        uint32_t          numOps      = 5;
        newOps[0].reg                 = consumerOps[0].reg;
        newOps[1].reg                 = base;
        if (indexed)
        {
            rewrittenOp       = MicroInstrOpcode::OpBinaryRegAmcMem;
            numOps            = 8;
            newOps[2].reg     = index;
            newOps[3].opBits  = opBits;
            newOps[4]         = loadOps[4];
            newOps[5]         = loadOps[5];
            newOps[6]         = loadOps[6];
            newOps[7].microOp = op;
        }
        else
        {
            newOps[2].opBits   = opBits;
            newOps[3].microOp  = op;
            newOps[4].valueU64 = loadOps[3].valueU64;
        }
        const std::span rewrittenOps(newOps, numOps);
        if (!isFloat && !encoderAcceptsAsIs(ctx, rewrittenOp, rewrittenOps))
            return false;
        MicroInstrRef clearRef = MicroInstrRef::invalid();
        if (isFloat)
        {
            const MicroInstrRef      previousRef = ctx.previousRef(loadRef);
            const MicroInstr*        previous    = ctx.instruction(previousRef);
            const MicroInstrOperand* clearOps    = previous ? previous->ops(*ctx.operands) : nullptr;
            if (previous && previous->op == MicroInstrOpcode::ClearReg && clearOps &&
                clearOps[0].reg == loaded && clearOps[1].opBits == opBits)
                clearRef = previousRef;
        }

        if (sourceCopyRef.isValid())
        {
            if (!ctx.claimAll({loadRef, opRef, sourceCopyRef}))
                return false;
        }
        else if (clearRef.isValid())
        {
            if (!ctx.claimAll({loadRef, opRef, clearRef}))
                return false;
        }
        else if (!ctx.claimAll({loadRef, opRef}))
        {
            return false;
        }

        if (loadRelocation)
            loadRelocation->instructionRef = opRef;
        ctx.emitRewrite(opRef, rewrittenOp, rewrittenOps, true);
        ctx.emitErase(loadRef);
        if (sourceCopyRef.isValid())
            ctx.emitErase(sourceCopyRef);
        if (clearRef.isValid())
            ctx.emitErase(clearRef);
        return true;
    }

    // `x * x` reads the same slot twice: once to load the destination, once as
    // the operation's memory operand. Naming the register on both sides drops
    // one of the two reads and costs nothing - no extra instruction, no extra
    // dependency, since the value is already in the register the operation is
    // about to write.
    bool tryUseSelfOperandForFloatBinary(Context& ctx, const MicroInstrRef opRef, const MicroInstr& opInst)
    {
        if (opInst.numOperands < 5)
            return false;

        const MicroInstrOperand* ops = ctx.operandsFor(opRef);
        if (!ops)
            return false;

        const MicroReg dst  = ops[0].reg;
        const MicroReg base = ops[1].reg;
        if (!dst.isFloat() || !base.isValid() || base.isInstructionPointer())
            return false;

        const MicroOpBits opBits = ops[2].opBits;
        if (!hasThreeOperandForm(ops[3].microOp))
            return false;

        const uint64_t offset = ops[4].valueU64;

        // Walk back to whatever last wrote the destination. Only a load of this
        // very address means the register already holds the memory operand;
        // running out of budget before finding that write proves nothing.
        constexpr uint32_t kMaxScan = 12;

        bool          loadFound = false;
        MicroInstrRef cursor    = ctx.previousRef(opRef);
        for (uint32_t step = 0; step < kMaxScan && !loadFound; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(cursor);
            if (!candidate)
                return false;

            const MicroInstrDef& info = MicroInstr::info(candidate->op);
            if (candidate->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory))
                return false;

            if (candidate->op == MicroInstrOpcode::LoadRegMem && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* loadOps = ctx.operandsFor(cursor);
                if (loadOps && loadOps[0].reg == dst)
                {
                    if (loadOps[1].reg != base || loadOps[3].valueU64 != offset || loadOps[2].opBits != opBits)
                        return false;
                    loadFound = true;
                    continue;
                }
            }

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == base)
                    return false;
            }

            cursor = ctx.previousRef(cursor);
        }

        if (!loadFound || !ctx.claimAll({opRef}))
            return false;

        MicroInstrOperand newOps[4] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = dst;
        newOps[2].opBits            = opBits;
        newOps[3].microOp           = ops[3].microOp;

        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegReg, std::span{newOps, 4});
        return true;
    }

    // An integer multiply by a constant names its destination separately too:
    //
    //     mov rax, rcx ; imul rax, 16843010    ->    imul rax, rcx, 16843010
    //
    // The copy the two-address form needs goes, as clang's `imul rax, rdx,
    // 16843010` shows in every magic-number division.
    bool tryFoldCopyIntoIntegerMultiply(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        constexpr uint32_t K_MAX_SCAN = 8;

        if (copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;
        const MicroOpBits copyBits = copyOps[2].opBits;
        if (copyBits != MicroOpBits::B32 && copyBits != MicroOpBits::B64)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (!dst.isInt() || !src.isInt() || dst == src || ctx.isPrivateFrameBase(dst) || ctx.isPrivateFrameBase(src))
            return false;

        // The multiply that consumes the copy, with nothing in between that
        // touches either register.
        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate || candidate->op == MicroInstrOpcode::Label)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegImm && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst || ctx.isClaimed(opRef))
            return false;
        const MicroInstrOperand* mulOps = ctx.operandsFor(opRef);
        if (!mulOps || mulOps[2].microOp != MicroOp::MultiplySigned || mulOps[1].opBits != copyBits ||
            mulOps[3].hasWideImmediateValue())
            return false;

        // The three-operand form takes a signed dword immediate.
        const uint64_t value       = mulOps[3].valueU64;
        const auto     signedValue = static_cast<int64_t>(copyBits == MicroOpBits::B32 ? static_cast<int64_t>(static_cast<int32_t>(value)) : static_cast<int64_t>(value));
        if (signedValue < INT32_MIN || signedValue > INT32_MAX)
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src;
        newOps[2].opBits            = copyBits;
        newOps[3].microOp           = MicroOp::MultiplySigned;
        newOps[4].valueU64          = value;
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegImm, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    // The result of a multiply by a constant can be named where it is wanted,
    // the other way round:
    //
    //     imul rcx, 16843010 ; mov rax, rcx    ->    imul rax, rcx, 16843010
    //
    // The multiplied register must die at the copy, since it no longer holds
    // the product afterwards.
    bool tryFoldMultiplyIntoResultCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        constexpr uint32_t K_MAX_SCAN = 8;

        if (copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;
        const MicroOpBits copyBits = copyOps[2].opBits;
        if (copyBits != MicroOpBits::B32 && copyBits != MicroOpBits::B64)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (!dst.isInt() || !src.isInt() || dst == src || ctx.isPrivateFrameBase(dst) || ctx.isPrivateFrameBase(src))
            return false;
        // The product only reaches the copy: anything else still reading the
        // multiplied register would read the value it no longer gets.
        if (!ctx.isRegDeadAfterCurrent(src))
            return false;

        // The multiply that feeds the copy, with nothing in between that
        // touches either register.
        MicroInstrRef     mulRef  = ctx.previousRef(copyRef);
        const MicroInstr* mulInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(mulRef);
            if (!candidate || candidate->op == MicroInstrOpcode::Label)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegImm && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(mulRef);
                if (candidateOps && candidateOps[0].reg == src)
                {
                    mulInst = candidate;
                    break;
                }
            }

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst || reg == src)
                    return false;
            }

            mulRef = ctx.previousRef(mulRef);
        }

        if (!mulInst || ctx.isClaimed(mulRef))
            return false;
        const MicroInstrOperand* mulOps = ctx.operandsFor(mulRef);
        if (!mulOps || mulOps[2].microOp != MicroOp::MultiplySigned || mulOps[1].opBits != copyBits ||
            mulOps[3].hasWideImmediateValue())
            return false;

        // The three-operand form takes a signed dword immediate.
        const uint64_t value       = mulOps[3].valueU64;
        const auto     signedValue = copyBits == MicroOpBits::B32 ? static_cast<int64_t>(static_cast<int32_t>(value)) : static_cast<int64_t>(value);
        if (signedValue < INT32_MIN || signedValue > INT32_MAX)
            return false;

        if (!ctx.claimAll({mulRef, copyRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src;
        newOps[2].opBits            = copyBits;
        newOps[3].microOp           = MicroOp::MultiplySigned;
        newOps[4].valueU64          = value;
        ctx.emitRewrite(mulRef, MicroInstrOpcode::OpBinaryRegRegImm, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    // A three-operand float operation names its destination freely, so a
    // result computed into a temporary and then copied can be computed where
    // it is wanted:
    //
    //     vmaxss xmm3, xmm0, xmm1 ; movss xmm0, xmm3    ->    vmaxss xmm0, xmm0, xmm1
    //
    // The temporary must die at the copy. Both sources are read before the
    // destination is written, so the destination may be one of them.
    bool tryFoldFloatBinaryIntoResultCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        constexpr uint32_t K_MAX_SCAN = 8;

        if (copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;
        const MicroReg    dst      = copyOps[0].reg;
        const MicroReg    src      = copyOps[1].reg;
        const MicroOpBits copyBits = copyOps[2].opBits;
        if (!dst.isFloat() || !src.isFloat() || dst == src || !ctx.isRegDeadAfterCurrent(src))
            return false;

        // The operation that feeds the copy, with nothing in between that
        // touches either register.
        MicroInstrRef     opRef  = ctx.previousRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < K_MAX_SCAN; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate || candidate->op == MicroInstrOpcode::Label)
                return false;

            if ((candidate->op == MicroInstrOpcode::OpBinaryRegRegReg && candidate->numOperands >= 5) ||
                (candidate->op == MicroInstrOpcode::OpBinaryRegReg && candidate->numOperands >= 4))
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == src)
                {
                    opInst = candidate;
                    break;
                }
            }

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst || reg == src)
                    return false;
            }

            opRef = ctx.previousRef(opRef);
        }

        if (!opInst || ctx.isClaimed(opRef))
            return false;
        const MicroInstrOperand* opOps = ctx.operandsFor(opRef);
        if (!opOps)
            return false;

        // The two-operand form names its destination as its own left source:
        // `xmm1 *= xmm0` spelled out is `xmm1 = xmm1 * xmm0`. Widening it here
        // is what lets the copy go, since the temporary is the destination.
        MicroInstrOperand newOps[5] = {};
        if (opInst->op == MicroInstrOpcode::OpBinaryRegReg)
        {
            if ((opOps[2].opBits != copyBits && copyBits != MicroOpBits::B128) || !foldableIntoThreeOperand(opOps[3].microOp, opOps[2].opBits) ||
                !opOps[0].reg.isFloat() || !opOps[1].reg.isFloat())
                return false;
            if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
                return false;
            newOps[1].reg    = opOps[0].reg;
            newOps[2].reg    = opOps[1].reg;
            newOps[3].opBits = opOps[2].opBits;
            newOps[4]        = opOps[3];
        }
        else
        {
            if ((opOps[3].opBits != copyBits && copyBits != MicroOpBits::B128) || !opOps[1].reg.isFloat() || !opOps[2].reg.isFloat())
                return false;
            std::ranges::copy(std::span{opOps, 5}, newOps);
        }

        // A scalar VEX producer already carries the final destination's upper
        // lanes when that destination is its first input. Bitwise forms write
        // every lane and cannot use that identity.
        const bool preservesUpperLanes = newOps[1].reg == dst && newOps[4].microOp != MicroOp::FloatAnd && newOps[4].microOp != MicroOp::FloatXor;
        if ((!preservesUpperLanes && !areFloatUpperLanesDeadAfter(ctx, copyRef, dst, copyBits)) || floatLanesReadAfter(ctx, copyRef, src) ||
            !ctx.claimAll({opRef, copyRef}))
            return false;

        newOps[0].reg = dst;
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{newOps, 5}, /*allocNewBlock=*/true);
        ctx.emitErase(copyRef);
        return true;
    }

    // Constant unsigned division can leave its magic multiply and logical
    // shift in a temporary immediately copied to the return register:
    //
    //     imul T, R        imul R, T
    //     shr  T, K   ->   shr  R, K
    //     mov  R, T
    //
    // The multiply is commutative, so the register holding the magic constant
    // can become the product and final result. A narrowing copy may disappear
    // only when the logical shift itself proves the upper dword is zero.
    bool tryFoldMultiplyShiftResultCopy(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef) || !ctx.encoder)
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64) ||
            !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;
        const MicroReg dst = copy[0].reg;
        const MicroReg src = copy[1].reg;

        const MicroInstrRef shiftRef = ctx.previousRef(copyRef);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        const auto*         shiftOps = shift ? shift->ops(*ctx.operands) : nullptr;
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm || !shiftOps ||
            shiftOps[0].reg != src || shiftOps[2].microOp != MicroOp::ShiftRight || shiftOps[3].hasWideImmediateValue() ||
            (shiftOps[1].opBits != MicroOpBits::B32 && shiftOps[1].opBits != MicroOpBits::B64))
            return false;
        if (copy[2].opBits != shiftOps[1].opBits &&
            !(copy[2].opBits == MicroOpBits::B32 && shiftOps[1].opBits == MicroOpBits::B64 && shiftOps[3].valueU64 >= 32))
            return false;

        const MicroInstrRef multiplyRef = ctx.previousRef(shiftRef);
        const MicroInstr*   multiply    = ctx.instruction(multiplyRef);
        const auto*         multiplyOps = multiply ? multiply->ops(*ctx.operands) : nullptr;
        if (!multiply || multiply->op != MicroInstrOpcode::OpBinaryRegReg || !multiplyOps ||
            multiplyOps[0].reg != src || multiplyOps[1].reg != dst ||
            multiplyOps[2].opBits != shiftOps[1].opBits || multiplyOps[3].microOp != MicroOp::MultiplySigned)
            return false;

        MicroInstrOperand rewrittenMultiply[4] = {multiplyOps[0], multiplyOps[1], multiplyOps[2], multiplyOps[3]};
        rewrittenMultiply[0].reg               = dst;
        rewrittenMultiply[1].reg               = src;
        MicroInstrOperand rewrittenShift[4]    = {shiftOps[0], shiftOps[1], shiftOps[2], shiftOps[3]};
        rewrittenShift[0].reg                  = dst;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, *multiply, rewrittenMultiply) ||
            ctx.encoder->queryConformanceIssue(issue, *shift, rewrittenShift) ||
            !ctx.claimAll({multiplyRef, shiftRef, copyRef}))
            return false;

        ctx.emitRewrite(multiplyRef, multiply->op, rewrittenMultiply);
        ctx.emitRewrite(shiftRef, shift->op, rewrittenShift);
        ctx.emitErase(copyRef);
        return true;
    }

    // The same fold for a packed shift by an immediate. A rotate needs its
    // source twice - once shifted left, once right - so the vectorizer copies
    // it before each destructive shift, and the register allocator was giving
    // one of those copies a stack home rather than a register: in a vectorized
    // ChaCha20 round loop that was four stores and four reloads per iteration,
    // on the dependency chain. VEX names the destination separately, so the
    // copy disappears and the pressure that caused the spill with it.
    bool tryFoldCopyIntoVecShiftImm(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
            return false;
        if (copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps || copyOps[2].opBits != MicroOpBits::B128)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (!dst.isFloat() || !src.isFloat() || dst == src)
            return false;

        constexpr uint32_t kMaxScan = 12;

        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < kMaxScan; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegImm && candidate->numOperands >= 4)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst)
            return false;

        const MicroInstrOperand* shiftOps = ctx.operandsFor(opRef);
        if (!shiftOps || shiftOps[1].opBits != MicroOpBits::B128)
            return false;

        const MicroOp shiftOp = shiftOps[2].microOp;
        if (shiftOp != MicroOp::VecShiftLeft32 && shiftOp != MicroOp::VecShiftRight32)
            return false;

        const uint64_t shiftValue = shiftOps[3].valueU64;
        if (shiftValue > 31)
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src;
        newOps[2].opBits            = MicroOpBits::B128;
        newOps[3].microOp           = shiftOp;
        newOps[4].valueU64          = shiftValue;

        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegImm, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }

    bool tryFoldCopyIntoFloatBinary(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (!ctx.encoder || !ctx.encoder->supportsNonDestructiveFloatBinary())
            return false;
        if (copyInst.numOperands < 3)
            return false;

        const MicroInstrOperand* copyOps = ctx.operandsFor(copyRef);
        if (!copyOps)
            return false;

        const MicroReg dst  = copyOps[0].reg;
        const MicroReg src1 = copyOps[1].reg;
        if (!dst.isFloat() || !src1.isFloat())
            return false;

        // The operation is rarely the next instruction: the second operand
        // usually has to be loaded first. Scan ahead for it, but only across
        // instructions that leave both registers alone, and stop at anything
        // control flow can enter from elsewhere - reaching the operation
        // without having run the copy would find a destination that never
        // received src1.
        constexpr uint32_t kMaxScan = 12;

        MicroInstrRef     opRef  = ctx.nextRef(copyRef);
        const MicroInstr* opInst = nullptr;
        for (uint32_t step = 0; step < kMaxScan; ++step)
        {
            const MicroInstr* candidate = ctx.instruction(opRef);
            if (!candidate)
                return false;

            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                const MicroInstrOperand* candidateOps = ctx.operandsFor(opRef);
                if (candidateOps && candidateOps[0].reg == dst)
                {
                    opInst = candidate;
                    break;
                }
            }

            if (candidate->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            // A write to either register breaks the chain, and so does a read of
            // the destination: after the fold it no longer holds src1 there.
            const MicroInstrUseDef useDef = candidate->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg reg : useDef.defs)
            {
                if (reg == dst || reg == src1)
                    return false;
            }
            for (const MicroReg reg : useDef.uses)
            {
                if (reg == dst)
                    return false;
            }

            opRef = ctx.nextRef(opRef);
        }

        if (!opInst || opInst->numOperands < 4)
            return false;

        const MicroInstrOperand* binOps = ctx.operandsFor(opRef);
        if (!binOps)
            return false;

        if (binOps[0].reg != dst)
            return false;

        const MicroReg src2 = binOps[1].reg;
        if (!src2.isFloat())
            return false;

        // `dst op= dst` reads the destination as its second source. Folding the
        // copy away would make that read see the pre-copy value instead of src1,
        // so this shape stays as it is.
        if (src2 == dst)
            return false;

        const MicroOpBits opBits = binOps[2].opBits;
        if (opBits != copyOps[2].opBits && copyOps[2].opBits != MicroOpBits::B128)
            return false;
        if (!foldableIntoThreeOperand(binOps[3].microOp, opBits) ||
            !areFloatUpperLanesDeadAfter(ctx, opRef, dst, copyOps[2].opBits))
            return false;

        if (!ctx.claimAll({copyRef, opRef}))
            return false;

        MicroInstrOperand newOps[5] = {};
        newOps[0].reg               = dst;
        newOps[1].reg               = src1;
        newOps[2].reg               = src2;
        newOps[3].opBits            = opBits;
        newOps[4].microOp           = binOps[3].microOp;

        // Five operands where the original had four, so the rewrite needs a
        // fresh operand block.
        ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegRegReg, std::span{newOps, 5}, true);
        ctx.emitErase(copyRef);
        return true;
    }
}

SWC_END_NAMESPACE();
