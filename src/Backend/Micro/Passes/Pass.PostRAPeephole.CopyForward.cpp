#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

// Post-RA copy coalescing: when a value is produced into a scratch register
// only to be immediately moved to another physical register, retarget the
// producer directly at the final destination and erase the move.
//
//     LoadRegMem  rA, [mem]        ->   LoadRegMem  rB, [mem]
//     LoadRegReg  rB, rA, bits          (move erased)
//
// Common shape is ABI marshalling after a spill reload:
//     load_reg_mem rax, [rsp+X]
//     load_reg_reg rcx, rax              -- rcx is the ABI arg slot
//     call                               -- clobbers rax anyway
//
// We only touch producers whose single def is ops[0] with Def mode (no
// UseDef), so retargeting is a straight operand swap. The encoder is
// queried before committing - some instructions pin specific physical regs
// (e.g. shifts on %cl) and those must not be rewritten.

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        constexpr int      K_MAX_LIVENESS_WINDOW    = 32;
        constexpr int      K_MAX_SAME_COPY_WINDOW   = 16;
        constexpr uint32_t K_MAX_COPY_SOURCE_WINDOW = 16;

        bool canMoveUnaryAcrossCopy(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            switch (ops[2].microOp)
            {
                case MicroOp::ShiftLeft:
                case MicroOp::ShiftRight:
                case MicroOp::ShiftArithmeticLeft:
                case MicroOp::ShiftArithmeticRight:
                case MicroOp::RotateLeft:
                case MicroOp::RotateRight:
                    if (inst.op != MicroInstrOpcode::OpBinaryRegImm || ops[3].hasWideImmediateValue() ||
                        (ops[3].valueU64 & (getNumBits(ops[1].opBits) - 1)) == 0)
                        return false;
                    break;
                case MicroOp::Negate:
                case MicroOp::BitwiseNot:
                    if (inst.op != MicroInstrOpcode::OpUnaryReg)
                        return false;
                    break;
                default:
                    return false;
            }
            return true;
        }

        bool regInList(std::span<const MicroReg> list, MicroReg reg)
        {
            for (const MicroReg r : list)
                if (r == reg)
                    return true;
            return false;
        }

        bool regDeadAfter(const Context& ctx, MicroInstrRef fromRef, MicroReg reg)
        {
            return regIsDeadAfter(ctx, fromRef, reg);
        }

        // Producers whose only register write is a pure Def at ops[0]. Anything
        // that consumes its own destination (UseDef) or has fixed-register
        // semantics beyond what regModes expresses is excluded.
        bool isSimpleSingleDefProducer(MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::LoadRegImm:
                case MicroInstrOpcode::LoadRegMem:
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadRegPtrImm:
                case MicroInstrOpcode::LoadRegPtrReloc:
                case MicroInstrOpcode::LoadSignedExtRegMem:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadAddrRegMem:
                case MicroInstrOpcode::SetCondReg:
                    return true;
                default:
                    return false;
            }
        }
    }

    // A copy whose destination already holds exactly what it is about to be
    // given again. The shape comes from the lowering of an operand a form
    // requires in a named register: two shifts by the same count each move
    // that count into rcx, and the second move has nothing to do. Same
    // registers, same width - a narrower copy left the upper half of the
    // destination with something else - and nothing in between writes either
    // register or leaves the straight line.
    //
    // The reversed pair `mov A, B ... mov B, A` is the same equality read the
    // other way; it comes from a parameter homed in one register and copied
    // back into its argument register by the next value's allocation. Only the
    // full-width pair qualifies: a 32-bit move back would also clear the upper
    // half of B, which the first move never promised was zero.
    bool tryEraseRedundantCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (copyInst.op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg    dst    = copyOps[0].reg;
        const MicroReg    src    = copyOps[1].reg;
        const MicroOpBits opBits = copyOps[2].opBits;
        if (dst == src || !dst.isInt() || !src.isInt())
            return false;

        MicroInstrRef cur = ctx.previousRef(copyRef);
        for (int step = 0; step < K_MAX_SAME_COPY_WINDOW && cur.isValid(); ++step, cur = ctx.previousRef(cur))
        {
            const MicroInstr* inst = ctx.instruction(cur);
            if (!inst || ctx.isClaimed(cur))
                return false;

            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                inst->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrOperand* ops          = inst->ops(*ctx.operands);
            const bool               sameCopy     = inst->op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == dst && ops[1].reg == src && ops[2].opBits == opBits;
            const bool               reversedCopy = inst->op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == src && ops[1].reg == dst &&
                                      ops[2].opBits == MicroOpBits::B64 && opBits == MicroOpBits::B64;
            if (sameCopy || reversedCopy)
            {
                if (!ctx.claimAll({copyRef}))
                    return false;
                ctx.emitErase(copyRef);
                return true;
            }

            const MicroInstrUseDef ud = inst->collectUseDef(*ctx.operands, ctx.encoder);
            if (regInList(ud.defs, dst) || regInList(ud.defs, src))
                return false;
        }

        return false;
    }

    // Coalesce mov D,S; op D; mov S,D without requiring D to be dead:
    // perform op S and finish with mov D,S, preserving both final values.
    bool tryFoldCopyRoundTrip(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef opRef = ctx.nextRef(copyRef);
        const MicroInstr*   op    = ctx.instruction(opRef);
        if (!op || (op->op != MicroInstrOpcode::OpBinaryRegImm && op->op != MicroInstrOpcode::OpUnaryReg))
            return false;
        const auto* ops = op->ops(*ctx.operands);
        if (!ops || ops[0].reg != copy[0].reg || ops[1].opBits != copy[2].opBits)
            return false;
        if (!canMoveUnaryAcrossCopy(*op, ops))
            return false;
        const MicroInstrRef backRef = ctx.nextRef(opRef);
        const MicroInstr*   back    = ctx.instruction(backRef);
        if (!back || back->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* backOps = back->ops(*ctx.operands);
        if (!backOps || backOps[0].reg != copy[1].reg || backOps[1].reg != copy[0].reg || backOps[2].opBits != copy[2].opBits)
            return false;
        MicroInstrOperand rewritten[4] = {};
        for (uint8_t i = 0; i < op->numOperands; ++i)
            rewritten[i] = ops[i];
        rewritten[0].reg = copy[1].reg;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *op, rewritten)) || !ctx.claimAll({copyRef, opRef, backRef}))
            return false;
        ctx.emitErase(copyRef);
        ctx.emitRewrite(opRef, op->op, std::span{rewritten, op->numOperands});
        ctx.emitRewrite(backRef, copyInst.op, std::span{copy, copyInst.numOperands});
        return true;
    }

    // An address computation can write the final result even when it reads its
    // old destination as a base/index. Only that old result must be dead.
    namespace
    {
        bool canRenameFullWidth(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            switch (inst.op)
            {
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::LoadAddrRegMem:
                    return ops[2].opBits == MicroOpBits::B64;
                case MicroInstrOpcode::CmpRegImm:
                    return ops[1].opBits == MicroOpBits::B64;
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    return ops[3].opBits == MicroOpBits::B64 && ops[4].opBits == MicroOpBits::B64;
                case MicroInstrOpcode::OpUnaryReg:
                    return ops[1].opBits == MicroOpBits::B64 &&
                           (ops[2].microOp == MicroOp::Negate || ops[2].microOp == MicroOp::BitwiseNot || ops[2].microOp == MicroOp::ByteSwap);
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpBinaryRegReg:
                {
                    const bool immediate = inst.op == MicroInstrOpcode::OpBinaryRegImm;
                    if (ops[immediate ? 1 : 2].opBits != MicroOpBits::B64)
                        return false;
                    switch (ops[immediate ? 2 : 3].microOp)
                    {
                        case MicroOp::Add:
                        case MicroOp::Subtract:
                        case MicroOp::And:
                        case MicroOp::Or:
                        case MicroOp::Xor:
                        case MicroOp::MultiplySigned:
                            return true;
                        case MicroOp::ShiftLeft:
                        case MicroOp::ShiftRight:
                        case MicroOp::ShiftArithmeticLeft:
                        case MicroOp::ShiftArithmeticRight:
                        case MicroOp::RotateLeft:
                        case MicroOp::RotateRight:
                            return immediate;
                        default:
                            return false;
                    }
                }
                default:
                    return false;
            }
        }
    }

    // Keep a short computation in a copied physical source when both old
    // register values die within the straight-line window. Claim the complete
    // window, including independent instructions, to exclude queued forwarding
    // rewrites that could introduce a new read of either register.
    bool tryCoalesceLocalCopyChain(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* copy = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !copy || !ctx.encoder || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || copy[2].opBits != MicroOpBits::B64 ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg))
            return false;
        const MicroReg     dst       = copy[0].reg;
        const MicroReg     src       = copy[1].reg;
        constexpr uint32_t maxWindow = 16;
        // A removed 64-bit MOV saves three bytes. Each renamed 64-bit form can
        // add at most one addressing byte, so three rewrites cannot grow code.
        constexpr uint32_t                                                        maxRewrites = 3;
        std::array<MicroInstrRef, maxWindow + 1>                                  window;
        std::array<MicroInstrRef, maxRewrites>                                    rewrittenRefs;
        std::array<std::array<MicroInstrOperand, Action::K_MAX_OPS>, maxRewrites> rewrittenOps;
        uint32_t                                                                  rewriteCount  = 0;
        bool                                                                      sourceChanged = false;
        window[0]                                                                               = ref;
        MicroInstrRef cursor                                                                    = ctx.nextRef(ref);
        for (uint32_t step = 1; step <= maxWindow && cursor.isValid(); ++step, cursor = ctx.nextRef(cursor))
        {
            const MicroInstr* current = ctx.instruction(cursor);
            if (!current || ctx.isClaimed(cursor))
                return false;
            const MicroInstrDef& info = MicroInstr::info(current->op);
            if (current->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                return false;
            window[step]    = cursor;
            const auto* ops = current->ops(*ctx.operands);
            if (!ops)
                return false;
            const MicroInstrUseDef useDef            = current->collectUseDef(*ctx.operands, ctx.encoder);
            const bool             readsDestination  = regInList(useDef.uses.span(), dst);
            const bool             writesDestination = regInList(useDef.defs.span(), dst);
            if (regInList(useDef.defs.span(), src) || (sourceChanged && regInList(useDef.uses.span(), src)))
                return false;
            if (readsDestination || writesDestination)
            {
                if (!readsDestination || rewriteCount == maxRewrites || current->numOperands > Action::K_MAX_OPS || !canRenameFullWidth(*current, ops))
                    return false;
                auto& rewritten = rewrittenOps[rewriteCount];
                std::copy_n(ops, current->numOperands, rewritten.data());
                for (uint32_t operand = 0; operand < info.regModes.size(); ++operand)
                    if (info.regModes[operand] != MicroInstrRegMode::None && rewritten[operand].reg == dst)
                        rewritten[operand].reg = src;
                MicroConformanceIssue issue;
                if (ctx.encoder->queryConformanceIssue(issue, *current, rewritten.data()))
                    return false;
                rewrittenRefs[rewriteCount++] = cursor;
                sourceChanged |= writesDestination;
            }
            if (rewriteCount && ctx.isRegDeadAfter(dst, ctx.instructionIndex + step) && ctx.isRegDeadAfter(src, ctx.instructionIndex + step))
            {
                if (!ctx.claimAll(std::span{window.data(), step + 1}))
                    return false;
                ctx.emitErase(ref);
                for (uint32_t i = 0; i < rewriteCount; ++i)
                {
                    const MicroInstr* changed = ctx.instruction(rewrittenRefs[i]);
                    ctx.emitRewrite(rewrittenRefs[i], changed->op, std::span{rewrittenOps[i].data(), changed->numOperands});
                }
                return true;
            }
        }
        return false;
    }

    bool tryRetargetAddressResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef addressRef = ctx.previousRef(copyRef);
        const MicroInstr*   address    = ctx.instruction(addressRef);
        if (!address || (address->op != MicroInstrOpcode::LoadAddrRegMem && address->op != MicroInstrOpcode::LoadAddrAmcRegMem))
            return false;
        const auto*    ops        = address->ops(*ctx.operands);
        const uint32_t widthIndex = address->op == MicroInstrOpcode::LoadAddrRegMem ? 2 : 3;
        if (!ops || ops[0].reg != copy[1].reg || ops[widthIndex].opBits != copy[2].opBits ||
            !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;
        MicroInstrOperand rewritten[Action::K_MAX_OPS] = {};
        std::copy_n(ops, address->numOperands, rewritten);
        rewritten[0].reg = copy[0].reg;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *address, rewritten)) || !ctx.claimAll({addressRef, copyRef}))
            return false;
        ctx.emitRewrite(addressRef, address->op, std::span{rewritten, address->numOperands});
        ctx.emitErase(copyRef);
        return true;
    }

    // MOV d,s; LEA s,[s+k]; d op= s can compute the address in d instead.
    // Commutativity preserves the final operation's value and flags; liveness
    // must prove that the old address result in s has no remaining reader.
    bool tryFoldCommutativeAddressCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* copy = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef addressRef = ctx.nextRef(ref);
        const MicroInstr*   address    = ctx.instruction(addressRef);
        if (!address || address->op != MicroInstrOpcode::LoadAddrRegMem)
            return false;
        const auto* lea = address->ops(*ctx.operands);
        if (!lea || lea[0].reg != copy[1].reg || (lea[1].reg != copy[0].reg && lea[1].reg != copy[1].reg) ||
            lea[2].opBits != copy[2].opBits)
            return false;
        const MicroInstrRef binaryRef = ctx.nextRef(addressRef);
        const MicroInstr*   binary    = ctx.instruction(binaryRef);
        if (!binary || binary->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* ops = binary->ops(*ctx.operands);
        if (!ops || ops[0].reg != copy[0].reg || ops[1].reg != copy[1].reg || ops[2].opBits != copy[2].opBits)
            return false;
        switch (ops[3].microOp)
        {
            case MicroOp::Add:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::MultiplySigned:
                break;
            default:
                return false;
        }
        const MicroInstrUseDef useDef = binary->collectUseDef(*ctx.operands, ctx.encoder);
        if (useDef.defs.size() != 1 || useDef.defs[0] != copy[0].reg || !ctx.isRegDeadAfter(copy[1].reg, ctx.instructionIndex + 2))
            return false;
        MicroInstrOperand     rewritten[4] = {copy[0], copy[1], lea[2], lea[3]};
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *address, rewritten)) || !ctx.claimAll({ref, addressRef, binaryRef}))
            return false;
        ctx.emitRewrite(ref, address->op, rewritten, true);
        ctx.emitErase(addressRef);
        return true;
    }

    // A commutative result copied over its other input can be produced there
    // directly. The old destination must be dead, including along CFG successors.
    bool tryCommuteBinaryResultCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* copy = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef binaryRef = ctx.previousRef(ref);
        const MicroInstr*   binary    = ctx.instruction(binaryRef);
        if (!binary || binary->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* ops = binary->ops(*ctx.operands);
        if (!ops || ops[0].reg != copy[1].reg || ops[1].reg != copy[0].reg ||
            (ops[2].opBits != copy[2].opBits && !(ops[2].opBits == MicroOpBits::B32 && copy[2].opBits == MicroOpBits::B64)))
            return false;
        switch (ops[3].microOp)
        {
            case MicroOp::Add:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::MultiplySigned:
                break;
            default:
                return false;
        }
        const MicroInstrUseDef useDef = binary->collectUseDef(*ctx.operands, ctx.encoder);
        if (useDef.defs.size() != 1 || useDef.defs[0] != copy[1].reg || !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;
        MicroInstrOperand     swapped[4] = {ops[1], ops[0], ops[2], ops[3]};
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *binary, swapped)) || !ctx.claimAll({binaryRef, ref}))
            return false;
        ctx.emitRewrite(binaryRef, binary->op, swapped);
        ctx.emitErase(ref);
        return true;
    }

    // A count-only copy needs at most six bits. Clearing its upper half is
    // harmless once the count dies or is replaced by the shift's full result.
    bool tryNarrowShiftCountCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* copy = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !copy || copy[2].opBits != MicroOpBits::B64 ||
            !copy[0].reg.isInt() || !copy[1].reg.isInt() || ctx.isPrivateFrameBase(copy[0].reg))
            return false;
        const MicroInstrRef shiftRef = ctx.nextRef(ref);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        if (!shift || (shift->op != MicroInstrOpcode::OpBinaryRegReg && shift->op != MicroInstrOpcode::OpBinaryRegRegReg))
            return false;
        const auto*    ops        = shift->ops(*ctx.operands);
        const bool     three      = shift->op == MicroInstrOpcode::OpBinaryRegRegReg;
        const uint32_t countIndex = three ? 2 : 1;
        if (!ops || ops[countIndex].reg != copy[0].reg || ops[three ? 1 : 0].reg == copy[0].reg ||
            (ops[countIndex + 1].opBits != MicroOpBits::B32 && ops[countIndex + 1].opBits != MicroOpBits::B64))
            return false;
        switch (ops[countIndex + 2].microOp)
        {
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                break;
            default:
                return false;
        }
        if (!(three && ops[0].reg == copy[0].reg) && !ctx.isRegDeadAfter(copy[0].reg, ctx.instructionIndex + 1))
            return false;
        if (!ctx.claimAll({ref, shiftRef}))
            return false;
        MicroInstrOperand narrowed[3] = {copy[0], copy[1], copy[2]};
        narrowed[2].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(ref, inst.op, narrowed);
        return true;
    }

    // The first use of a copied value can discard its upper half. Until that
    // full 32-bit write, no instruction may observe the original high bits.
    bool tryNarrowCopyBefore32BitWrite(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* copy = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !ctx.encoder || !copy || copy[2].opBits != MicroOpBits::B64 ||
            !copy[0].reg.isInt() || !copy[1].reg.isInt() || ctx.isPrivateFrameBase(copy[0].reg))
            return false;
        constexpr uint32_t                       maxWindow = 8;
        std::array<MicroInstrRef, maxWindow + 1> window;
        window[0]            = ref;
        MicroInstrRef cursor = ctx.nextRef(ref);
        for (uint32_t step = 1; step <= maxWindow && cursor.isValid(); ++step, cursor = ctx.nextRef(cursor))
        {
            const MicroInstr* current = ctx.instruction(cursor);
            if (!current || ctx.isClaimed(cursor))
                return false;
            const MicroInstrDef& info = MicroInstr::info(current->op);
            if (current->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                return false;
            window[step]                  = cursor;
            const MicroInstrUseDef useDef = current->collectUseDef(*ctx.operands, ctx.encoder);
            if (!regInList(useDef.uses.span(), copy[0].reg) && !regInList(useDef.defs.span(), copy[0].reg))
                continue;
            const auto* ops = current->ops(*ctx.operands);
            if (!ops || ops[0].reg != copy[0].reg || useDef.defs.size() != 1 || useDef.defs[0] != copy[0].reg)
                return false;
            const bool regReg = current->op == MicroInstrOpcode::OpBinaryRegReg;
            if (!regReg && current->op != MicroInstrOpcode::OpBinaryRegImm && current->op != MicroInstrOpcode::OpUnaryReg)
                return false;
            if (ops[regReg ? 2 : 1].opBits != MicroOpBits::B32)
                return false;
            switch (ops[regReg ? 3 : 2].microOp)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                    break;
                default:
                    if (regReg || !canMoveUnaryAcrossCopy(*current, ops))
                        return false;
                    break;
            }
            // Queued forwarding must not introduce a wider read in the window.
            if (!ctx.claimAll(std::span{window.data(), step + 1}))
                return false;
            MicroInstrOperand narrowed[3] = {copy[0], copy[1], copy[2]};
            narrowed[2].opBits            = MicroOpBits::B32;
            ctx.emitRewrite(ref, inst.op, narrowed);
            return true;
        }
        return false;
    }

    // A full copy of a value just defined at 32 bits can use a 32-bit MOV.
    // The IR width contract already guarantees that the source's upper half is zero.
    bool tryNarrowCopyOf32BitResult(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* copy = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !copy || copy[2].opBits != MicroOpBits::B64 ||
            !copy[0].reg.isInt() || !copy[1].reg.isInt() || ctx.isPrivateFrameBase(copy[0].reg))
            return false;
        const MicroInstrRef producerRef = ctx.previousRef(ref);
        const MicroInstr*   producer    = ctx.instruction(producerRef);
        const auto*         ops         = producer ? producer->ops(*ctx.operands) : nullptr;
        if (!ops)
            return false;
        MicroOpBits bits;
        switch (producer->op)
        {
            case MicroInstrOpcode::ClearReg:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::OpUnaryReg:
                bits = ops[1].opBits;
                break;
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                bits = ops[2].opBits;
                break;
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                bits = ops[3].opBits;
                break;
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegImm:
            {
                const bool immediate = producer->op == MicroInstrOpcode::OpBinaryRegImm;
                bits                 = ops[immediate ? 1 : 2].opBits;
                const MicroOp op     = ops[immediate ? 2 : 3].microOp;
                switch (op)
                {
                    case MicroOp::Add:
                    case MicroOp::Subtract:
                    case MicroOp::And:
                    case MicroOp::Or:
                    case MicroOp::Xor:
                    case MicroOp::MultiplySigned:
                        break;
                    case MicroOp::ShiftLeft:
                    case MicroOp::ShiftArithmeticLeft:
                    case MicroOp::ShiftRight:
                    case MicroOp::ShiftArithmeticRight:
                    case MicroOp::RotateLeft:
                    case MicroOp::RotateRight:
                        if (!immediate || ops[3].hasWideImmediateValue() || (ops[3].valueU64 & 31) == 0)
                            return false;
                        break;
                    default:
                        return false;
                }
                break;
            }
            default:
                return false;
        }
        const MicroInstrUseDef useDef = producer->collectUseDef(*ctx.operands, ctx.encoder);
        if (ops[0].reg != copy[1].reg || bits != MicroOpBits::B32 || useDef.defs.size() != 1 || useDef.defs[0] != copy[1].reg ||
            !ctx.claimAll({producerRef, ref}))
            return false;
        MicroInstrOperand narrowed[3] = {copy[0], copy[1], copy[2]};
        narrowed[2].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(ref, inst.op, narrowed);
        return true;
    }

    // Retarget a two-step add/multiply computation as one unit so forwarding
    // cannot reintroduce its removed result copy on the next sweep.
    bool tryFoldAddMultiplyResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        const auto* copy = copyInst.ops(*ctx.operands);
        if (ctx.isClaimed(copyRef) || !ctx.encoder || !copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroReg    dst         = copy[0].reg;
        const MicroReg    src         = copy[1].reg;
        MicroInstrRef     multiplyRef = ctx.previousRef(copyRef);
        const MicroInstr* multiply    = ctx.instruction(multiplyRef);
        const auto*       mul         = multiply ? multiply->ops(*ctx.operands) : nullptr;
        bool              square      = false;
        MicroInstrRef     addRef;
        if (multiply && multiply->op == MicroInstrOpcode::OpBinaryRegReg && mul &&
            mul[3].microOp == MicroOp::MultiplySigned && mul[0].reg == src &&
            mul[1].reg != dst && ctx.isRegDeadAfterCurrent(src))
            addRef = ctx.previousRef(multiplyRef);
        else
        {
            addRef      = ctx.previousRef(copyRef);
            multiplyRef = ctx.nextRef(copyRef);
            multiply    = ctx.instruction(multiplyRef);
            mul         = multiply ? multiply->ops(*ctx.operands) : nullptr;
            if (!multiply || multiply->op != MicroInstrOpcode::OpBinaryRegReg || !mul ||
                mul[3].microOp != MicroOp::MultiplySigned || mul[0].reg != dst || mul[1].reg != src ||
                !ctx.isRegDeadAfter(src, ctx.instructionIndex + 1))
                return false;
            square = true;
        }
        const MicroInstr* add = ctx.instruction(addRef);
        const auto*       ops = add ? add->ops(*ctx.operands) : nullptr;
        if (!add || add->op != MicroInstrOpcode::OpBinaryRegReg || !ops || ops[3].microOp != MicroOp::Add ||
            ops[0].reg != src || !ops[1].reg.isInt() || !mul[1].reg.isInt() ||
            ops[2].opBits != copy[2].opBits || mul[2].opBits != copy[2].opBits ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, addRef, ctx.builder))
            return false;
        MicroInstrOperand address[8] = {};
        address[0].reg               = dst;
        address[1].reg               = src;
        address[2].reg               = ops[1].reg;
        address[3].opBits            = copy[2].opBits;
        address[4].opBits            = MicroOpBits::B64;
        address[5].valueU64          = 1;
        MicroInstr probe;
        probe.op          = MicroInstrOpcode::LoadAddrAmcRegMem;
        probe.numOperands = 8;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, probe, address))
            return false;
        MicroInstrOperand product[4];
        std::copy_n(mul, 4, product);
        product[0].reg = dst;
        if (square || product[1].reg == src)
            product[1].reg = dst;
        if (ctx.encoder->queryConformanceIssue(issue, *multiply, product) || !ctx.claimAll({addRef, multiplyRef, copyRef}))
            return false;
        ctx.emitRewrite(addRef, probe.op, address, true);
        ctx.emitRewrite(multiplyRef, multiply->op, product);
        ctx.emitErase(copyRef);
        return true;
    }

    // ADD followed by a result copy can compute directly in the copy's
    // destination when ABI-aware liveness proves its old result is dead.
    bool tryFoldIntegerAddResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef addRef = ctx.previousRef(copyRef);
        const MicroInstr*   add    = ctx.instruction(addRef);
        if (!add || add->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* ops = add->ops(*ctx.operands);
        if (!ops || ops[3].microOp != MicroOp::Add || ops[0].reg != copy[1].reg || !ops[1].reg.isInt() ||
            ops[2].opBits != copy[2].opBits || !ctx.isRegDeadAfterCurrent(copy[1].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, addRef, ctx.builder))
            return false;
        MicroInstrOperand address[8] = {};
        address[0].reg               = copy[0].reg;
        address[1].reg               = ops[0].reg;
        address[2].reg               = ops[1].reg;
        address[3].opBits            = ops[2].opBits;
        address[4].opBits            = MicroOpBits::B64;
        address[5].valueU64          = 1;
        MicroInstr probe;
        probe.op          = MicroInstrOpcode::LoadAddrAmcRegMem;
        probe.numOperands = 8;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, address)) || !ctx.claimAll({addRef, copyRef}))
            return false;
        ctx.emitRewrite(addRef, probe.op, address, true);
        ctx.emitErase(copyRef);
        return true;
    }

    // A 64-bit overflow-safe ceiling average can keep its result in the
    // original input by computing the xor in the copied temporary first:
    //
    //     M = A; M |= B                 M = A; M ^= B
    //     A ^= B; A >>= 1        ->     A |= B; M >>= 1
    //     M -= A; A = M                 A -= M
    bool tryFoldUnsignedCeilAverage64(Context& ctx, const MicroInstrRef resultCopyRef, const MicroInstr& resultCopyInst)
    {
        if (ctx.isClaimed(resultCopyRef))
            return false;
        const auto* resultCopy = resultCopyInst.ops(*ctx.operands);
        if (!resultCopy || resultCopy[2].opBits != MicroOpBits::B64 || !resultCopy[0].reg.isInt() || !resultCopy[1].reg.isInt() ||
            resultCopy[0].reg == resultCopy[1].reg || ctx.isPrivateFrameBase(resultCopy[0].reg) ||
            ctx.isPrivateFrameBase(resultCopy[1].reg) || !ctx.isRegDeadAfterCurrent(resultCopy[1].reg))
            return false;
        const MicroReg result = resultCopy[0].reg;
        const MicroReg merged = resultCopy[1].reg;

        const MicroInstrRef subtractRef = ctx.previousRef(resultCopyRef);
        const MicroInstr*   subtract    = ctx.instruction(subtractRef);
        const auto*         sub         = subtract ? subtract->ops(*ctx.operands) : nullptr;
        const MicroInstrRef shiftRef    = ctx.previousRef(subtractRef);
        const MicroInstr*   shift       = ctx.instruction(shiftRef);
        const auto*         shifted     = shift ? shift->ops(*ctx.operands) : nullptr;
        const MicroInstrRef xorRef      = ctx.previousRef(shiftRef);
        const MicroInstr*   xorInst     = ctx.instruction(xorRef);
        const auto*         xorOps      = xorInst ? xorInst->ops(*ctx.operands) : nullptr;
        const MicroInstrRef orRef       = ctx.previousRef(xorRef);
        const MicroInstr*   orInst      = ctx.instruction(orRef);
        const auto*         orOps       = orInst ? orInst->ops(*ctx.operands) : nullptr;
        const MicroInstrRef initialCopyRef  = ctx.previousRef(orRef);
        const MicroInstr*   initialCopyInst = ctx.instruction(initialCopyRef);
        const auto*         initialCopy     = initialCopyInst ? initialCopyInst->ops(*ctx.operands) : nullptr;
        if (!subtract || subtract->op != MicroInstrOpcode::OpBinaryRegReg || !sub ||
            sub[0].reg != merged || sub[1].reg != result || sub[2].opBits != MicroOpBits::B64 || sub[3].microOp != MicroOp::Subtract ||
            !shift || shift->op != MicroInstrOpcode::OpBinaryRegImm || !shifted || shifted[0].reg != result ||
            shifted[1].opBits != MicroOpBits::B64 || shifted[2].microOp != MicroOp::ShiftRight ||
            shifted[3].hasWideImmediateValue() || shifted[3].valueU64 != 1 ||
            !xorInst || xorInst->op != MicroInstrOpcode::OpBinaryRegReg || !xorOps || xorOps[0].reg != result ||
            xorOps[2].opBits != MicroOpBits::B64 || xorOps[3].microOp != MicroOp::Xor ||
            !orInst || orInst->op != MicroInstrOpcode::OpBinaryRegReg || !orOps || orOps[0].reg != merged ||
            orOps[1].reg != xorOps[1].reg || orOps[2].opBits != MicroOpBits::B64 || orOps[3].microOp != MicroOp::Or ||
            !initialCopyInst || initialCopyInst->op != MicroInstrOpcode::LoadRegReg || !initialCopy ||
            initialCopy[0].reg != merged || initialCopy[1].reg != result || initialCopy[2].opBits != MicroOpBits::B64 ||
            !xorOps[1].reg.isInt() || xorOps[1].reg == result || xorOps[1].reg == merged ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, subtractRef, ctx.builder))
            return false;

        MicroInstrOperand rewrittenXor[4] = {orOps[0], orOps[1], orOps[2], orOps[3]};
        rewrittenXor[3].microOp           = MicroOp::Xor;
        MicroInstrOperand rewrittenOr[4]  = {xorOps[0], xorOps[1], xorOps[2], xorOps[3]};
        rewrittenOr[3].microOp            = MicroOp::Or;
        MicroInstrOperand rewrittenShift[4] = {shifted[0], shifted[1], shifted[2], shifted[3]};
        rewrittenShift[0].reg               = merged;
        MicroInstrOperand rewrittenSubtract[4] = {sub[0], sub[1], sub[2], sub[3]};
        rewrittenSubtract[0].reg               = result;
        rewrittenSubtract[1].reg               = merged;

        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, *orInst, rewrittenXor) ||
                             ctx.encoder->queryConformanceIssue(issue, *xorInst, rewrittenOr) ||
                             ctx.encoder->queryConformanceIssue(issue, *shift, rewrittenShift) ||
                             ctx.encoder->queryConformanceIssue(issue, *subtract, rewrittenSubtract))) ||
            !ctx.claimAll({initialCopyRef, orRef, xorRef, shiftRef, subtractRef, resultCopyRef}))
            return false;
        ctx.emitRewrite(orRef, orInst->op, rewrittenXor);
        ctx.emitRewrite(xorRef, xorInst->op, rewrittenOr);
        ctx.emitRewrite(shiftRef, shift->op, rewrittenShift);
        ctx.emitRewrite(subtractRef, subtract->op, rewrittenSubtract);
        ctx.emitErase(resultCopyRef);
        return true;
    }

    // The overflow-safe ceiling average widens clear dwords and keeps its
    // result in the original input register:
    //
    //     M = A; M |= B                  A += B, b64
    //     A ^= B; A >>= 1, b32    ->    A += 1, b64
    //     M -= A; A = M                  A >>= 1, b64
    bool tryFoldUnsignedCeilAverage(Context& ctx, MicroInstrRef resultCopyRef, const MicroInstr& resultCopyInst)
    {
        if (ctx.isClaimed(resultCopyRef))
            return false;
        const auto* resultCopy = resultCopyInst.ops(*ctx.operands);
        if (!resultCopy || resultCopy[2].opBits != MicroOpBits::B32 || !resultCopy[0].reg.isInt() || !resultCopy[1].reg.isInt() ||
            resultCopy[0].reg == resultCopy[1].reg || ctx.isPrivateFrameBase(resultCopy[0].reg) ||
            ctx.isPrivateFrameBase(resultCopy[1].reg) || !ctx.isRegDeadAfterCurrent(resultCopy[1].reg))
            return false;
        const MicroReg result = resultCopy[0].reg;
        const MicroReg merged = resultCopy[1].reg;

        const MicroInstrRef subtractRef = ctx.previousRef(resultCopyRef);
        const MicroInstr*   subtract    = ctx.instruction(subtractRef);
        const auto*         sub         = subtract ? subtract->ops(*ctx.operands) : nullptr;
        if (!subtract || subtract->op != MicroInstrOpcode::OpBinaryRegReg || !sub ||
            sub[0].reg != merged || sub[1].reg != result || sub[2].opBits != MicroOpBits::B32 || sub[3].microOp != MicroOp::Subtract ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, subtractRef, ctx.builder))
            return false;

        const MicroInstrRef shiftRef = ctx.previousRef(subtractRef);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        const auto*         shifted  = shift ? shift->ops(*ctx.operands) : nullptr;
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm || !shifted || shifted[0].reg != result ||
            shifted[1].opBits != MicroOpBits::B32 || shifted[2].microOp != MicroOp::ShiftRight ||
            shifted[3].hasWideImmediateValue() || shifted[3].valueU64 != 1)
            return false;

        const MicroInstrRef xorRef = ctx.previousRef(shiftRef);
        const MicroInstr*   xorInst = ctx.instruction(xorRef);
        const auto*         xorOps  = xorInst ? xorInst->ops(*ctx.operands) : nullptr;
        if (!xorInst || xorInst->op != MicroInstrOpcode::OpBinaryRegReg || !xorOps || xorOps[0].reg != result ||
            !xorOps[1].reg.isInt() || xorOps[1].reg == result || xorOps[1].reg == merged ||
            xorOps[2].opBits != MicroOpBits::B32 || xorOps[3].microOp != MicroOp::Xor)
            return false;
        const MicroReg other = xorOps[1].reg;

        const MicroInstrRef orRef = ctx.previousRef(xorRef);
        const MicroInstr*   orInst = ctx.instruction(orRef);
        const auto*         orOps  = orInst ? orInst->ops(*ctx.operands) : nullptr;
        const MicroInstrRef initialCopyRef = ctx.previousRef(orRef);
        const MicroInstr*   initialCopyInst = ctx.instruction(initialCopyRef);
        const auto*         initialCopy = initialCopyInst ? initialCopyInst->ops(*ctx.operands) : nullptr;
        if (!orInst || orInst->op != MicroInstrOpcode::OpBinaryRegReg || !orOps ||
            orOps[0].reg != merged || orOps[1].reg != other || orOps[2].opBits != MicroOpBits::B32 || orOps[3].microOp != MicroOp::Or ||
            !initialCopyInst || initialCopyInst->op != MicroInstrOpcode::LoadRegReg || !initialCopy ||
            initialCopy[0].reg != merged || initialCopy[1].reg != result || initialCopy[2].opBits != MicroOpBits::B32 ||
            !ctx.isUpperHalfZeroBefore(initialCopyRef, result) || !ctx.isUpperHalfZeroBefore(initialCopyRef, other))
            return false;

        MicroInstrOperand widenedAdd[4] = {resultCopy[0], xorOps[1], resultCopy[2], {}};
        widenedAdd[2].opBits            = MicroOpBits::B64;
        widenedAdd[3].microOp           = MicroOp::Add;
        MicroInstrOperand increment[3];
        increment[0].reg     = result;
        increment[1].opBits  = MicroOpBits::B64;
        increment[2].microOp = MicroOp::Add;
        MicroInstrOperand widenedShift[4] = {shifted[0], shifted[1], shifted[2], shifted[3]};
        widenedShift[1].opBits            = MicroOpBits::B64;

        MicroInstr addProbe;
        addProbe.op          = MicroInstrOpcode::OpBinaryRegReg;
        addProbe.numOperands = 4;
        MicroInstr incrementProbe;
        incrementProbe.op          = MicroInstrOpcode::OpUnaryReg;
        incrementProbe.numOperands = 3;
        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, addProbe, widenedAdd) ||
                             ctx.encoder->queryConformanceIssue(issue, incrementProbe, increment) ||
                             ctx.encoder->queryConformanceIssue(issue, *shift, widenedShift))) ||
            !ctx.claimAll({initialCopyRef, orRef, xorRef, shiftRef, subtractRef, resultCopyRef}))
            return false;
        ctx.emitErase(initialCopyRef);
        ctx.emitRewrite(orRef, addProbe.op, widenedAdd);
        ctx.emitRewrite(xorRef, incrementProbe.op, increment);
        ctx.emitRewrite(shiftRef, shift->op, widenedShift);
        ctx.emitErase(subtractRef);
        ctx.emitErase(resultCopyRef);
        return true;
    }

    // Keep a selected intermediate in the copied source when its next use is
    // another selection. The source's old value must die at that point, while
    // the temporary must be dead after the consumer:
    //
    //     mov     T, R                 cmovCC R, A
    //     cmovCC  T, A                 cmp     R, B
    //     cmp     T, B        ->       cmovDD  B, R
    //     cmovDD  B, T
    bool tryRetargetSelectedIntermediate(Context& ctx, const MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64) ||
            !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg))
            return false;
        const MicroReg temporary = copy[0].reg;
        const MicroReg result    = copy[1].reg;

        const MicroInstrRef firstSelectRef = ctx.nextRef(copyRef);
        const MicroInstr*   firstSelect    = ctx.instruction(firstSelectRef);
        const auto*         first          = firstSelect ? firstSelect->ops(*ctx.operands) : nullptr;
        if (!firstSelect || firstSelect->op != MicroInstrOpcode::LoadCondRegReg || !first ||
            first[0].reg != temporary || first[1].reg == temporary || first[1].reg == result ||
            first[3].opBits != copy[2].opBits)
            return false;

        const MicroInstrRef compareRef = ctx.nextRef(firstSelectRef);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        const auto*         cmp        = compare ? compare->ops(*ctx.operands) : nullptr;
        if (!compare || compare->op != MicroInstrOpcode::CmpRegReg || !cmp || cmp[2].opBits != copy[2].opBits)
            return false;
        MicroReg other;
        if (cmp[0].reg == temporary)
            other = cmp[1].reg;
        else if (cmp[1].reg == temporary)
            other = cmp[0].reg;
        else
            return false;
        if (!other.isInt() || other == temporary || other == result)
            return false;

        const MicroInstrRef secondSelectRef = ctx.nextRef(compareRef);
        const MicroInstr*   secondSelect    = ctx.instruction(secondSelectRef);
        const auto*         second          = secondSelect ? secondSelect->ops(*ctx.operands) : nullptr;
        if (!secondSelect || secondSelect->op != MicroInstrOpcode::LoadCondRegReg || !second ||
            second[0].reg != other || second[1].reg != temporary || second[3].opBits != copy[2].opBits ||
            !regIsDeadAfter(ctx, secondSelectRef, result) ||
            !ctx.isRegDeadAfter(temporary, ctx.instructionIndex + 3))
            return false;

        MicroInstrOperand rewrittenFirst[4] = {first[0], first[1], first[2], first[3]};
        rewrittenFirst[0].reg               = result;
        MicroInstrOperand rewrittenCompare[3] = {cmp[0], cmp[1], cmp[2]};
        if (rewrittenCompare[0].reg == temporary)
            rewrittenCompare[0].reg = result;
        else
            rewrittenCompare[1].reg = result;
        MicroInstrOperand rewrittenSecond[4] = {second[0], second[1], second[2], second[3]};
        rewrittenSecond[1].reg              = result;

        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, *firstSelect, rewrittenFirst) ||
                             ctx.encoder->queryConformanceIssue(issue, *compare, rewrittenCompare) ||
                             ctx.encoder->queryConformanceIssue(issue, *secondSelect, rewrittenSecond))) ||
            !ctx.claimAll({copyRef, firstSelectRef, compareRef, secondSelectRef}))
            return false;
        ctx.emitErase(copyRef);
        ctx.emitRewrite(firstSelectRef, firstSelect->op, rewrittenFirst);
        ctx.emitRewrite(compareRef, compare->op, rewrittenCompare);
        ctx.emitRewrite(secondSelectRef, secondSelect->op, rewrittenSecond);
        return true;
    }

    // A pair of nested selections can stay in the final register throughout:
    //
    //     mov     A, L                 ; R already holds the other arm
    //     cmp     R, L                 cmp     R, L
    //     cmovCC  A, R                 cmov!CC R, L
    //     cmp     A, H        ->       cmp     R, H
    //     cmovDD  H, A                 cmov!DD R, H
    //     mov     R, H
    bool tryFoldConditionalCascadeResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64) || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;

        const MicroReg      result       = copy[0].reg;
        const MicroReg      secondResult = copy[1].reg;
        const MicroInstrRef secondSelectRef = ctx.previousRef(copyRef);
        const MicroInstr*   secondSelect    = ctx.instruction(secondSelectRef);
        const auto*         second          = secondSelect ? secondSelect->ops(*ctx.operands) : nullptr;
        if (!secondSelect || secondSelect->op != MicroInstrOpcode::LoadCondRegReg || !second ||
            second[0].reg != secondResult || !second[1].reg.isInt() || second[1].reg == result ||
            second[1].reg == secondResult || (second[3].opBits != MicroOpBits::B32 && second[3].opBits != MicroOpBits::B64))
            return false;
        const MicroReg firstResult = second[1].reg;
        const MicroOpBits bits = second[3].opBits;
        if ((copy[2].opBits != bits &&
             !(copy[2].opBits == MicroOpBits::B64 && bits == MicroOpBits::B32 && ctx.isUpperHalfZeroBefore(copyRef, secondResult))) ||
            !ctx.isRegDeadAfterCurrent(firstResult))
            return false;

        const MicroInstrRef secondCompareRef = ctx.previousRef(secondSelectRef);
        const MicroInstr*   secondCompare    = ctx.instruction(secondCompareRef);
        const auto*         secondCmp        = secondCompare ? secondCompare->ops(*ctx.operands) : nullptr;
        if (!secondCompare || secondCompare->op != MicroInstrOpcode::CmpRegReg || !secondCmp ||
            secondCmp[2].opBits != bits ||
            !((secondCmp[0].reg == firstResult && secondCmp[1].reg == secondResult) ||
              (secondCmp[1].reg == firstResult && secondCmp[0].reg == secondResult)))
            return false;

        const MicroInstrRef firstSelectRef = ctx.previousRef(secondCompareRef);
        const MicroInstr*   firstSelect    = ctx.instruction(firstSelectRef);
        const auto*         first          = firstSelect ? firstSelect->ops(*ctx.operands) : nullptr;
        if (!firstSelect || firstSelect->op != MicroInstrOpcode::LoadCondRegReg || !first ||
            first[0].reg != firstResult || first[1].reg != result || first[3].opBits != bits)
            return false;

        const MicroInstrRef firstCompareRef = ctx.previousRef(firstSelectRef);
        const MicroInstr*   firstCompare    = ctx.instruction(firstCompareRef);
        const auto*         firstCmp        = firstCompare ? firstCompare->ops(*ctx.operands) : nullptr;
        const MicroInstrRef initialRef      = ctx.previousRef(firstCompareRef);
        const MicroInstr*   initial         = ctx.instruction(initialRef);
        const auto*         initialCopy     = initial ? initial->ops(*ctx.operands) : nullptr;
        if (!firstCompare || firstCompare->op != MicroInstrOpcode::CmpRegReg || !firstCmp ||
            firstCmp[2].opBits != bits || !initial || initial->op != MicroInstrOpcode::LoadRegReg || !initialCopy ||
            initialCopy[0].reg != firstResult || !initialCopy[1].reg.isInt() || getNumBits(initialCopy[2].opBits) < getNumBits(bits) ||
            !((firstCmp[0].reg == result && firstCmp[1].reg == initialCopy[1].reg) ||
              (firstCmp[1].reg == result && firstCmp[0].reg == initialCopy[1].reg)))
            return false;
        const MicroReg initialAlternative = initialCopy[1].reg;
        if (initialAlternative == result || initialAlternative == firstResult || initialAlternative == secondResult)
            return false;

        MicroCond invertedFirst;
        MicroCond invertedSecond;
        if (!MicroPassHelpers::invertCondition(invertedFirst, first[2].cpuCond) ||
            !MicroPassHelpers::invertCondition(invertedSecond, second[2].cpuCond))
            return false;

        MicroInstrOperand rewrittenFirst[4] = {first[0], first[1], first[2], first[3]};
        rewrittenFirst[0].reg               = result;
        rewrittenFirst[1].reg               = initialAlternative;
        rewrittenFirst[2].cpuCond           = invertedFirst;
        MicroInstrOperand rewrittenCompare[3] = {secondCmp[0], secondCmp[1], secondCmp[2]};
        if (rewrittenCompare[0].reg == firstResult)
            rewrittenCompare[0].reg = result;
        else
            rewrittenCompare[1].reg = result;
        MicroInstrOperand rewrittenSecond[4] = {second[0], second[1], second[2], second[3]};
        rewrittenSecond[0].reg              = result;
        rewrittenSecond[1].reg              = secondResult;
        rewrittenSecond[2].cpuCond          = invertedSecond;

        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, *firstSelect, rewrittenFirst) ||
                             ctx.encoder->queryConformanceIssue(issue, *secondCompare, rewrittenCompare) ||
                             ctx.encoder->queryConformanceIssue(issue, *secondSelect, rewrittenSecond))) ||
            !ctx.claimAll({initialRef, firstCompareRef, firstSelectRef, secondCompareRef, secondSelectRef, copyRef}))
            return false;
        ctx.emitErase(initialRef);
        ctx.emitRewrite(firstSelectRef, firstSelect->op, rewrittenFirst);
        ctx.emitRewrite(secondCompareRef, secondCompare->op, rewrittenCompare);
        ctx.emitRewrite(secondSelectRef, secondSelect->op, rewrittenSecond);
        ctx.emitErase(copyRef);
        return true;
    }

    // Two selections accumulated in one temporary can start in the final
    // register instead. Complement the first condition, then carry that final
    // register through the second compare and selection:
    //
    //     cmovCC A, R                 cmov!CC R, A
    //     cmp     B, A                cmp     B, R
    //     cmovDD  A, B       ->       cmovDD  R, B
    //     mov     R, A
    bool tryFoldConditionalChainResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64) || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;

        const MicroReg      result    = copy[0].reg;
        const MicroReg      temporary = copy[1].reg;
        const MicroInstrRef secondSelectRef = ctx.previousRef(copyRef);
        const MicroInstr*   secondSelect    = ctx.instruction(secondSelectRef);
        const auto*         second          = secondSelect ? secondSelect->ops(*ctx.operands) : nullptr;
        if (!secondSelect || secondSelect->op != MicroInstrOpcode::LoadCondRegReg || !second ||
            second[0].reg != temporary || second[1].reg == result || second[1].reg == temporary ||
            (second[3].opBits != MicroOpBits::B32 && second[3].opBits != MicroOpBits::B64))
            return false;
        const MicroOpBits bits = second[3].opBits;
        if (copy[2].opBits != bits &&
            !(copy[2].opBits == MicroOpBits::B64 && bits == MicroOpBits::B32 && ctx.isUpperHalfZeroBefore(copyRef, temporary)))
            return false;

        const MicroInstrRef compareRef = ctx.previousRef(secondSelectRef);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        const auto*         cmp        = compare ? compare->ops(*ctx.operands) : nullptr;
        if (!compare || compare->op != MicroInstrOpcode::CmpRegReg || !cmp || cmp[2].opBits != bits ||
            !((cmp[0].reg == temporary && cmp[1].reg == second[1].reg) ||
              (cmp[1].reg == temporary && cmp[0].reg == second[1].reg)))
            return false;

        const MicroInstrRef firstSelectRef = ctx.previousRef(compareRef);
        const MicroInstr*   firstSelect    = ctx.instruction(firstSelectRef);
        const auto*         first          = firstSelect ? firstSelect->ops(*ctx.operands) : nullptr;
        if (!firstSelect || firstSelect->op != MicroInstrOpcode::LoadCondRegReg || !first ||
            first[0].reg != temporary || first[1].reg != result || first[3].opBits != bits)
            return false;

        MicroCond inverted;
        if (!MicroPassHelpers::invertCondition(inverted, first[2].cpuCond))
            return false;

        MicroInstrOperand rewrittenFirst[4] = {first[0], first[1], first[2], first[3]};
        rewrittenFirst[0].reg               = result;
        rewrittenFirst[1].reg               = temporary;
        rewrittenFirst[2].cpuCond           = inverted;
        MicroInstrOperand rewrittenCompare[3] = {cmp[0], cmp[1], cmp[2]};
        if (rewrittenCompare[0].reg == temporary)
            rewrittenCompare[0].reg = result;
        else
            rewrittenCompare[1].reg = result;
        MicroInstrOperand rewrittenSecond[4] = {second[0], second[1], second[2], second[3]};
        rewrittenSecond[0].reg              = result;

        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, *firstSelect, rewrittenFirst) ||
                             ctx.encoder->queryConformanceIssue(issue, *compare, rewrittenCompare) ||
                             ctx.encoder->queryConformanceIssue(issue, *secondSelect, rewrittenSecond))) ||
            !ctx.claimAll({firstSelectRef, compareRef, secondSelectRef, copyRef}))
            return false;
        ctx.emitRewrite(firstSelectRef, firstSelect->op, rewrittenFirst);
        ctx.emitRewrite(compareRef, compare->op, rewrittenCompare);
        ctx.emitRewrite(secondSelectRef, secondSelect->op, rewrittenSecond);
        ctx.emitErase(copyRef);
        return true;
    }

    // A conditional move followed by a copy back into its alternative source
    // can select directly in that final register by complementing the condition:
    // `cmovCC A, B; mov B, A` becomes `cmov!CC B, A`. The old value of B is
    // exactly the true arm, while A is the false arm. A must die at the copy.
    bool tryFoldConditionalResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || copy[2].opBits != MicroOpBits::B64 || !copy[0].reg.isInt() || !copy[1].reg.isInt() ||
            copy[0].reg == copy[1].reg || ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            !ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;

        const MicroInstrRef selectRef = ctx.previousRef(copyRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        const auto*         ops       = select ? select->ops(*ctx.operands) : nullptr;
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg || !ops ||
            ops[0].reg != copy[1].reg || ops[1].reg != copy[0].reg || ops[3].opBits != copy[2].opBits)
            return false;

        MicroCond inverted;
        if (!MicroPassHelpers::invertCondition(inverted, ops[2].cpuCond))
            return false;
        MicroInstrOperand rewritten[4] = {ops[0], ops[1], ops[2], ops[3]};
        rewritten[0].reg               = copy[0].reg;
        rewritten[1].reg               = copy[1].reg;
        rewritten[2].cpuCond           = inverted;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *select, rewritten)) ||
            !ctx.claimAll({selectRef, copyRef}))
            return false;
        ctx.emitRewrite(selectRef, select->op, rewritten);
        ctx.emitErase(copyRef);
        return true;
    }

    // Keep the original value in the temporary and negate the final register:
    // `mov A, B; neg A; cmovCC A, B; mov B, A` becomes
    // `mov A, B; neg B; cmovCC B, A`. NEG produces identical flags because
    // both registers held the same value, and the temporary dies at the copy.
    bool tryRetargetNegatedConditionalResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* result = copyInst.ops(*ctx.operands);
        if (!result || result[2].opBits != MicroOpBits::B64 || !result[0].reg.isInt() || !result[1].reg.isInt() ||
            result[0].reg == result[1].reg || ctx.isPrivateFrameBase(result[0].reg) || ctx.isPrivateFrameBase(result[1].reg) ||
            !ctx.isRegDeadAfterCurrent(result[1].reg))
            return false;

        const MicroInstrRef selectRef = ctx.previousRef(copyRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        const auto*         selected  = select ? select->ops(*ctx.operands) : nullptr;
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg || !selected ||
            selected[0].reg != result[1].reg || selected[1].reg != result[0].reg || selected[3].opBits != result[2].opBits)
            return false;

        const MicroInstrRef negateRef = ctx.previousRef(selectRef);
        const MicroInstr*   negate    = ctx.instruction(negateRef);
        const auto*         negated   = negate ? negate->ops(*ctx.operands) : nullptr;
        if (!negate || negate->op != MicroInstrOpcode::OpUnaryReg || !negated ||
            negated[0].reg != result[1].reg || negated[1].opBits != result[2].opBits || negated[2].microOp != MicroOp::Negate)
            return false;

        const MicroInstrRef initialRef = ctx.previousRef(negateRef);
        const MicroInstr*   initial    = ctx.instruction(initialRef);
        const auto*         copied     = initial ? initial->ops(*ctx.operands) : nullptr;
        if (!initial || initial->op != MicroInstrOpcode::LoadRegReg || !copied ||
            copied[0].reg != result[1].reg || copied[1].reg != result[0].reg || copied[2].opBits != result[2].opBits)
            return false;

        MicroInstrOperand rewrittenNegate[3] = {negated[0], negated[1], negated[2]};
        rewrittenNegate[0].reg               = result[0].reg;
        MicroInstrOperand rewrittenSelect[4] = {selected[0], selected[1], selected[2], selected[3]};
        rewrittenSelect[0].reg               = result[0].reg;
        rewrittenSelect[1].reg               = result[1].reg;
        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, *negate, rewrittenNegate) ||
                             ctx.encoder->queryConformanceIssue(issue, *select, rewrittenSelect))) ||
            !ctx.claimAll({initialRef, negateRef, selectRef, copyRef}))
            return false;
        ctx.emitRewrite(negateRef, negate->op, rewrittenNegate);
        ctx.emitRewrite(selectRef, select->op, rewrittenSelect);
        ctx.emitErase(copyRef);
        return true;
    }

    // Move a dying unary result into its final register before the operation.
    // This exposes preceding arithmetic to the input-copy folds on the next sweep.
    bool tryRetargetUnaryResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef opRef = ctx.previousRef(copyRef);
        const MicroInstr*   op    = ctx.instruction(opRef);
        if (!op || (op->op != MicroInstrOpcode::OpBinaryRegImm && op->op != MicroInstrOpcode::OpUnaryReg))
            return false;
        const auto* ops = op->ops(*ctx.operands);
        if (!ops || ops[0].reg != copy[1].reg || ops[1].opBits != copy[2].opBits)
            return false;
        if (!canMoveUnaryAcrossCopy(*op, ops))
            return false;
        if (!ctx.isRegDeadAfterCurrent(copy[1].reg))
            return false;
        MicroInstrOperand rewritten[4] = {};
        for (uint8_t i = 0; i < op->numOperands; ++i)
            rewritten[i] = ops[i];
        rewritten[0].reg = copy[0].reg;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, *op, rewritten)) || !ctx.claimAll({opRef, copyRef}))
            return false;
        ctx.emitRewrite(opRef, copyInst.op, std::span{copy, copyInst.numOperands}, true);
        ctx.emitRewrite(copyRef, op->op, std::span{rewritten, op->numOperands}, true);
        return true;
    }

    // Keep value additions intact through SSA/loop optimization, then merge
    // the physical input copy with a flag-dead add. A 32-bit LEA needs only
    // the low input bits even though its addressing operands are 64-bit.
    bool tryFoldCopyIntoIntegerAdd(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef addRef = ctx.nextRef(copyRef);
        const MicroInstr*   add    = ctx.instruction(addRef);
        if (!add || add->op != MicroInstrOpcode::OpBinaryRegReg || ctx.isClaimed(addRef))
            return false;
        const auto* ops = add->ops(*ctx.operands);
        if (!ops || ops[3].microOp != MicroOp::Add || ops[0].reg != copy[0].reg || !ops[1].reg.isInt() ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
            getNumBits(copy[2].opBits) < getNumBits(ops[2].opBits) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, addRef, ctx.builder))
            return false;
        MicroInstrOperand address[8] = {};
        address[0].reg               = copy[0].reg;
        address[1].reg               = copy[1].reg;
        address[2].reg               = ops[1].reg == copy[0].reg ? copy[1].reg : ops[1].reg;
        address[3].opBits            = ops[2].opBits;
        address[4].opBits            = MicroOpBits::B64;
        address[5].valueU64          = 1;
        MicroInstr probe;
        probe.op          = MicroInstrOpcode::LoadAddrAmcRegMem;
        probe.numOperands = 8;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, address)) || !ctx.claimAll({copyRef, addRef}))
            return false;
        ctx.emitRewrite(addRef, probe.op, address, true);
        // Other readers, including implicit ABI uses, remain the DCE's job.
        return true;
    }

    // A later operation can read the original register directly. Leave the
    // copy in place: its other readers and ABI obligations belong to post-RA
    // dead-code elimination, which removes it only when they are all gone.
    bool tryForwardCopySource(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg == copyOps[1].reg)
            return false;
        // A scalar float copy forwards to float readers of its lane alone.
        const bool floatCopy = copyOps[0].reg.isFloat() && copyOps[1].reg.isFloat() &&
                               (copyOps[2].opBits == MicroOpBits::B32 || copyOps[2].opBits == MicroOpBits::B64);
        if (!floatCopy && (!copyOps[0].reg.isInt() || !copyOps[1].reg.isInt()))
            return false;
        // A byte or word copy forwards too, to readers of no more than its bits.
        if (copyOps[2].opBits == MicroOpBits::Zero || copyOps[2].opBits == MicroOpBits::B128)
            return false;

        // A 32-bit copy of a register whose upper half is already clear
        // copies all of it.
        std::optional<MicroOpBits> copyBits;
        const auto                 effectiveCopyBits = [&] {
            if (!copyBits)
                copyBits = copyOps[2].opBits == MicroOpBits::B32 && ctx.isUpperHalfZeroBefore(copyRef, copyOps[1].reg) ? MicroOpBits::B64 : copyOps[2].opBits;
            return *copyBits;
        };

        // Only the equality established by the copy is propagated. Stop when
        // either register changes or control leaves the straight line. Claim
        // every instruction crossed so later queued rewrites preserve that proof.
        SmallVector<MicroInstrRef, K_MAX_COPY_SOURCE_WINDOW + 1> observed;
        observed.push_back(copyRef);
        MicroInstrRef nextRef = ctx.nextRef(copyRef);
        for (uint32_t step = 0; step < K_MAX_COPY_SOURCE_WINDOW && nextRef.isValid(); ++step, nextRef = ctx.nextRef(nextRef))
        {
            const MicroInstr* next = ctx.instruction(nextRef);
            if (!next || ctx.isClaimed(nextRef))
                return false;
            const auto& info = MicroInstr::info(next->op);
            if (next->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) || info.flags.has(MicroInstrFlagsE::JumpInstruction))
                return false;
            observed.push_back(nextRef);
            const bool extends        = next->op == MicroInstrOpcode::LoadZeroExtRegReg || next->op == MicroInstrOpcode::LoadSignedExtRegReg;
            const bool conditional    = next->op == MicroInstrOpcode::LoadCondRegReg;
            const bool compareRegs    = next->op == MicroInstrOpcode::CmpRegReg || next->op == MicroInstrOpcode::TestRegReg;
            const bool compareImm     = next->op == MicroInstrOpcode::CmpRegImm || next->op == MicroInstrOpcode::TestRegImm;
            const bool indexedAddress = next->op == MicroInstrOpcode::LoadAddrAmcRegMem;
            const bool address        = indexedAddress || next->op == MicroInstrOpcode::LoadAddrRegMem;
            // An exchange writes its second operand too: renaming it would
            // swap a different register (a parallel-move cycle at a loop edge
            // then leaves a value in the wrong register).
            const bool binary = next->op == MicroInstrOpcode::OpBinaryRegReg && next->ops(*ctx.operands)[3].microOp != MicroOp::Exchange;
            const bool three  = next->op == MicroInstrOpcode::OpBinaryRegRegReg;
            // A store or a memory update reads its value operand; the base stays.
            const bool memory = next->op == MicroInstrOpcode::LoadMemReg || next->op == MicroInstrOpcode::OpBinaryMemReg;
            const bool candidate = floatCopy ? compareRegs || next->op == MicroInstrOpcode::LoadRegReg || binary || three || memory
                                             : extends || conditional || compareRegs || compareImm || address || next->op == MicroInstrOpcode::LoadRegReg || binary || three || memory;
            if (candidate)
            {
                const MicroInstrOperand* ops = next->ops(*ctx.operands);
                if (!ops)
                    return false;
                const uint32_t widthOperand = extends || conditional || three ? 3 : compareImm ? 1
                                                                                               : 2;
                // A truncated LEA result depends only on the corresponding low
                // input bits, even though its addressing mode uses 64-bit registers.
                const MicroOpBits readBits = address ? ops[indexedAddress ? 3 : 2].opBits : ops[widthOperand].opBits;
                if ((floatCopy || ops[0].reg.isInt()) && (getNumBits(readBits) <= getNumBits(copyOps[2].opBits) || getNumBits(readBits) <= getNumBits(effectiveCopyBits())))
                {
                    MicroInstrOperand rewritten[Action::K_MAX_OPS];
                    std::ranges::copy(std::span{ops, next->numOperands}, rewritten);
                    bool           changed      = false;
                    const uint32_t firstOperand = compareRegs || compareImm ? 0 : 1;
                    const uint32_t lastOperand  = indexedAddress || three ? 2 : compareImm ? 0
                                                                                           : 1;
                    for (uint32_t i = firstOperand; i <= lastOperand; ++i)
                    {
                        if (rewritten[i].reg == copyOps[0].reg)
                        {
                            rewritten[i].reg = copyOps[1].reg;
                            changed          = true;
                        }
                    }
                    MicroConformanceIssue issue;
                    if (changed && (!ctx.encoder || !ctx.encoder->queryConformanceIssue(issue, *next, rewritten)))
                    {
                        if (!ctx.claimAll(observed.span()))
                            return false;
                        ctx.emitRewrite(nextRef, next->op, std::span{rewritten, next->numOperands});
                        return true;
                    }
                }
            }
            const MicroInstrUseDef ud = next->collectUseDef(*ctx.operands, ctx.encoder);
            if (regInList(ud.defs, copyOps[0].reg) || regInList(ud.defs, copyOps[1].reg))
                return false;
        }
        return false;
    }

    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        // Liveness here is a linear forward scan, sound only on the pristine
        // post-RA IR. Restrict to the first sweep of the optimization loop.
        if (!ctx.allowForwarding)
            return false;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        if (ctx.isClaimed(copyRef))
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg dst = copyOps[0].reg;
        const MicroReg src = copyOps[1].reg;
        if (dst == src || !dst.isAnyInt() || !src.isAnyInt())
            return false;

        // Walk backward looking for the producer of `src`. We can skip
        // instructions that touch neither `src` nor `dst`, but must bail if
        // `src` is read in between (the producer's value is still observed),
        // if `dst` is read or written in between (we're about to pull the
        // producer's write forward onto `dst`), or if we cross a control-
        // flow boundary (the copy may be reachable via other paths where the
        // producer never ran).
        MicroInstrRef     prevRef = MicroInstrRef::invalid();
        const MicroInstr* prev    = nullptr;
        {
            MicroInstrRef cur = ctx.previousRef(copyRef);
            for (int step = 0; step < K_MAX_LIVENESS_WINDOW && cur.isValid(); ++step, cur = ctx.previousRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return false;
                if (ctx.isClaimed(cur))
                    return false;

                const MicroInstrUseDef ud = inst->collectUseDef(*ctx.operands, ctx.encoder);

                const bool defsSrc = regInList(ud.defs.span(), src);
                const bool usesSrc = regInList(ud.uses.span(), src);

                // The producer is allowed to read `dst`: its operands are read
                // before its destination is written, so retargeting it at `dst`
                // computes the same value. That is the `x = x + 1` shape every
                // scan loop ends with — `lea t, [x + 1]` then `mov x, t` — and
                // refusing it left one instruction per iteration in the hottest
                // loops of the benchmark. Every OTHER read or write of `dst`
                // before the copy still blocks: `dst` carries a live value
                // there, and retargeting would clobber or shadow it.
                if (defsSrc && !usesSrc)
                {
                    prevRef = cur;
                    prev    = inst;
                    break;
                }

                if (regInList(ud.uses.span(), dst))
                    return false;
                if (regInList(ud.defs.span(), dst))
                    return false;

                if (defsSrc)
                    return false; // UseDef of src: not a pure producer.
                if (usesSrc)
                    return false; // Intermediate read of src's future value.

                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (inst->op == MicroInstrOpcode::Label)
                    return false;
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
                    return false;
                if (info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return false;
            }
        }

        if (!prev || !prevRef.isValid() || ctx.isClaimed(prevRef))
            return false;
        if (!isSimpleSingleDefProducer(prev->op))
            return false;

        const MicroInstrOperand* prevOps = prev->ops(*ctx.operands);
        if (!prevOps)
            return false;

        // The producer must write exactly `src` at ops[0], with no other defs.
        // It may read `dst` (see the walk above); the encoder is asked below
        // whether the retargeted form, where source and destination coincide,
        // is encodable at all.
        const MicroInstrUseDef prevUseDef = prev->collectUseDef(*ctx.operands, ctx.encoder);
        if (prevUseDef.isCall)
            return false;
        if (prevUseDef.defs.size() != 1 || prevUseDef.defs[0] != src)
            return false;
        if (prevOps[0].reg != src)
            return false;

        if (!regDeadAfter(ctx, copyRef, src))
            return false;

        if (ctx.encoder)
        {
            // Build the retargeted instruction in a scratch buffer and ask
            // the encoder whether it is legal before committing.
            MicroInstrOperand probeOps[Action::K_MAX_OPS] = {};
            const uint8_t     numOps                      = prev->numOperands;
            if (numOps > Action::K_MAX_OPS)
                return false;
            for (uint8_t i = 0; i < numOps; ++i)
                probeOps[i] = prevOps[i];
            probeOps[0].reg = dst;

            MicroInstr probe;
            probe.op          = prev->op;
            probe.numOperands = numOps;

            MicroConformanceIssue issue;
            if (ctx.encoder->queryConformanceIssue(issue, probe, probeOps))
                return false;
        }

        if (!ctx.claimAll({prevRef, copyRef}))
            return false;

        MicroInstrOperand newOps[Action::K_MAX_OPS] = {};
        const uint8_t     numOps                    = prev->numOperands;
        for (uint8_t i = 0; i < numOps; ++i)
            newOps[i] = prevOps[i];
        newOps[0].reg = dst;

        const std::span rewrittenOps(newOps, numOps);
        ctx.emitRewrite(prevRef, prev->op, rewrittenOps);
        ctx.emitErase(copyRef);
        return true;
    }

    namespace
    {
        using UpperHalfState = uint32_t;

        bool writesWholeRegisterAt32(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                case MicroOp::ShiftLeft:
                case MicroOp::ShiftArithmeticLeft:
                case MicroOp::ShiftRight:
                case MicroOp::ShiftArithmeticRight:
                case MicroOp::RotateLeft:
                case MicroOp::RotateRight:
                case MicroOp::Negate:
                case MicroOp::BitwiseNot:
                case MicroOp::ByteSwap:
                case MicroOp::PopCount:
                    return true;
                default:
                    return false;
            }
        }

        bool isPartialWidth(const MicroOpBits bits)
        {
            return bits == MicroOpBits::B8 || bits == MicroOpBits::B16;
        }

        UpperHalfState regBit(const MicroReg reg)
        {
            return reg.isInt() && reg.index() < 32 ? UpperHalfState{1} << reg.index() : 0;
        }

        // Whether `reg`, the instruction's destination, has its upper half
        // clear afterwards, given what was known before it. A byte or word
        // write keeps the upper half as it was.
        bool definesUpperHalfZero(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg reg, const UpperHalfState before)
        {
            if (!ops || ops[0].reg != reg)
                return false;

            const bool kept  = (before & regBit(reg)) != 0;
            const auto known = [&](const MicroReg other) {
                return (before & regBit(other)) != 0;
            };

            switch (inst.op)
            {
                case MicroInstrOpcode::ClearReg:
                    return isPartialWidth(ops[1].opBits) ? kept : true;
                case MicroInstrOpcode::LoadRegImm:
                    if (isPartialWidth(ops[1].opBits))
                        return kept;
                    return ops[1].opBits == MicroOpBits::B32 || (!ops[2].hasWideImmediateValue() && ops[2].valueU64 <= UINT32_MAX);
                case MicroInstrOpcode::LoadRegReg:
                    if (isPartialWidth(ops[2].opBits))
                        return kept;
                    return ops[2].opBits == MicroOpBits::B32 || known(ops[1].reg);
                case MicroInstrOpcode::LoadRegMem:
                    return isPartialWidth(ops[2].opBits) ? kept : ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadAddrRegMem:
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadAmcRegMem:
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    return ops[3].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::LoadCondRegReg:
                    return ops[3].opBits == MicroOpBits::B32 || (ops[3].opBits == MicroOpBits::B64 && kept && known(ops[1].reg));
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegMem:
                    if (isPartialWidth(ops[2].opBits))
                        return kept;
                    return ops[2].opBits == MicroOpBits::B32 || getNumBits(ops[3].opBits) <= 32;
                case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                    if (isPartialWidth(ops[3].opBits))
                        return kept;
                    return ops[3].opBits == MicroOpBits::B32 || getNumBits(ops[4].opBits) <= 32;
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadSignedExtRegMem:
                    if (isPartialWidth(ops[2].opBits))
                        return kept;
                    return ops[2].opBits == MicroOpBits::B32;
                case MicroInstrOpcode::SetCondReg:
                    return kept;
                case MicroInstrOpcode::OpBinaryRegReg:
                case MicroInstrOpcode::OpBinaryRegMem:
                {
                    const MicroOpBits bits = ops[2].opBits;
                    const MicroOp     op   = ops[3].microOp;
                    if (op == MicroOp::Exchange)
                        return false;
                    if (isPartialWidth(bits))
                        return kept;
                    if (bits == MicroOpBits::B32)
                        return writesWholeRegisterAt32(op);
                    if (bits != MicroOpBits::B64 || inst.op != MicroInstrOpcode::OpBinaryRegReg)
                        return false;
                    if (op == MicroOp::And)
                        return kept || known(ops[1].reg);
                    if (op == MicroOp::Or || op == MicroOp::Xor)
                        return kept && known(ops[1].reg);
                    return false;
                }
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpUnaryReg:
                {
                    const MicroOpBits bits = ops[1].opBits;
                    const MicroOp     op   = ops[2].microOp;
                    if (isPartialWidth(bits))
                        return kept;
                    if (bits == MicroOpBits::B32)
                        return writesWholeRegisterAt32(op);
                    if (bits != MicroOpBits::B64 || inst.op != MicroInstrOpcode::OpBinaryRegImm || ops[3].hasWideImmediateValue())
                        return false;
                    const uint64_t imm = ops[3].valueU64;
                    if (op == MicroOp::And)
                        return kept || imm <= UINT32_MAX;
                    if (op == MicroOp::Or || op == MicroOp::Xor)
                        return kept && imm <= UINT32_MAX;
                    if (op == MicroOp::ShiftRight)
                        return kept || (imm & 63) >= 32;
                    return false;
                }
                default:
                    return false;
            }
        }

        UpperHalfState upperHalfAfter(const Context& ctx, const MicroInstr& inst, const UpperHalfState before)
        {
            const MicroInstrUseDef useDef = inst.collectUseDef(*ctx.operands, ctx.encoder);
            if (useDef.isCall)
                return 0;

            const MicroInstrOperand* ops   = inst.ops(*ctx.operands);
            UpperHalfState           after = before;
            for (const MicroReg def : useDef.defs)
                after &= ~regBit(def);
            for (const MicroReg def : useDef.defs)
            {
                if (definesUpperHalfZero(inst, ops, def, before))
                    after |= regBit(def);
            }
            return after;
        }

        // A move that only clears the upper half of its own register:
        // `mov r32, r32` or the equivalent widening.
        bool isUpperHalfClear(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (!ops || !ops[0].reg.isInt() || ops[0].reg != ops[1].reg)
                return false;
            if (inst.op == MicroInstrOpcode::LoadRegReg)
                return ops[2].opBits == MicroOpBits::B32;
            if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg)
                return ops[2].opBits == MicroOpBits::B64 && ops[3].opBits == MicroOpBits::B32;
            return false;
        }
    }

    // Which integer registers have their upper half clear on entry to each
    // instruction: after a 32-bit result, a zero-extension, or a full copy of
    // either. A forward must-analysis over the instruction graph; a call and
    // any definition it does not model forget what was known.
    bool Context::isUpperHalfZeroBefore(const MicroInstrRef ref, const MicroReg reg)
    {
        if (!upperHalfReady)
        {
            upperHalfReady = true;
            if (!builder)
                return false;
            const MicroControlFlowGraph& cfg = builder->controlFlowGraph();
            if (cfg.hasUnsupportedControlFlowForCfgLiveness())
                return false;

            const uint32_t              count = cfg.instructionCount();
            const auto                  refs  = cfg.instructionRefs();
            std::vector<UpperHalfState> in(count, ~UpperHalfState{0});
            std::vector<UpperHalfState> out(count, ~UpperHalfState{0});
            std::vector<uint8_t>        queued(count, 1);
            SmallVector<uint32_t>       worklist;
            for (uint32_t i = count; i > 0; --i)
                worklist.push_back(i - 1);

            while (!worklist.empty())
            {
                const uint32_t index = worklist.back();
                worklist.pop_back();
                queued[index] = 0;

                UpperHalfState state = index == 0 ? 0 : ~UpperHalfState{0};
                for (const uint32_t pred : cfg.predecessors(index))
                    state &= out[pred];
                in[index] = state;

                const MicroInstr* inst = storage->ptr(refs[index]);
                if (!inst)
                    return false;
                const UpperHalfState after = upperHalfAfter(*this, *inst, state);
                if (after == out[index])
                    continue;
                out[index] = after;
                for (const uint32_t succ : cfg.successors(index))
                {
                    if (!queued[succ])
                    {
                        queued[succ] = 1;
                        worklist.push_back(succ);
                    }
                }
            }

            upperHalfZeroIn.assign(storage->slotCount(), 0);
            for (uint32_t index = 0; index < count; ++index)
                upperHalfZeroIn[refs[index].get()] = in[index];
            upperHalfValid = true;
        }

        if (!upperHalfValid || !ref.isValid() || ref.get() >= upperHalfZeroIn.size())
            return false;
        const UpperHalfState bit = regBit(reg);
        return bit && (upperHalfZeroIn[ref.get()] & bit) != 0;
    }

    // A move that clears the upper half of a register where that half is
    // already clear does nothing.
    void eraseRedundantUpperHalfClears(Context& ctx)
    {
        for (auto it = ctx.storage->view().begin(); it != ctx.storage->view().end(); ++it)
        {
            const MicroInstrOperand* ops = it->ops(*ctx.operands);
            if (!isUpperHalfClear(*it, ops) || !ctx.isUpperHalfZeroBefore(it.current, ops[0].reg))
                continue;
            if (ctx.claimAll({it.current}))
                ctx.emitErase(it.current);
        }
    }
}

SWC_END_NAMESPACE();
