#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Support/Core/SmallVector.h"

// A vector load whose every reader widens half of it.
//
//     LoadVecRegMem      vt,  [b+o]           (or the 128-bit LoadRegMem)
//     VecUnaryRegReg     lo,  vt, widenLo          (the low eight bytes)
//     OpBinaryRegRegReg  hi,  vt, zero, unpackHi   (the high eight, against zero)
//   ->
//     VecUnaryRegMem     lo,  [b+o],   widenLo
//     VecUnaryRegMem     hi,  [b+o+8], widenLo
//
// Each half is one widening from memory instead of a load and a widening:
// no register holds the sixteen bytes, and the zero goes unread. The reads
// move to the readers, so nothing between the load and a reader may write
// memory, transfer control, or redefine the base.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_VECFOLD_WINDOW = 32;

        bool isLowWiden(const MicroOp op)
        {
            switch (op)
            {
                case MicroOp::VecWidenLoU8:
                case MicroOp::VecWidenLoU16:
                case MicroOp::VecWidenLoU32:
                case MicroOp::VecWidenLoS8:
                case MicroOp::VecWidenLoS16:
                case MicroOp::VecWidenLoS32:
                    return true;
                default:
                    return false;
            }
        }

        // The unsigned widening an interleave of the high half with zero
        // amounts to.
        bool widenOfUnpackHi(const MicroOp op, MicroOp& outWiden)
        {
            switch (op)
            {
                case MicroOp::VecUnpackHi8:
                    outWiden = MicroOp::VecWidenLoU8;
                    return true;
                case MicroOp::VecUnpackHi16:
                    outWiden = MicroOp::VecWidenLoU16;
                    return true;
                case MicroOp::VecUnpackHi32:
                    outWiden = MicroOp::VecWidenLoU32;
                    return true;
                default:
                    return false;
            }
        }

        // Whether the value is a cleared vector register, through the phis a
        // loop header places on a register the loop never redefines.
        bool isZeroVectorValue(const Context& ctx, const uint32_t valueId, const uint32_t depth)
        {
            const auto values = ctx.ssa->values();
            if (valueId >= values.size() || depth > 4)
                return false;

            const MicroSsaState::ValueInfo& info = values[valueId];
            if (info.isPhi())
            {
                const MicroSsaState::PhiInfo* phi = ctx.ssa->phiInfoForValue(valueId);
                if (!phi || phi->incomingValueIds.empty())
                    return false;
                for (const uint32_t incoming : phi->incomingValueIds)
                {
                    if (incoming != valueId && !isZeroVectorValue(ctx, incoming, depth + 1))
                        return false;
                }
                return true;
            }

            const MicroInstr* inst = info.instRef.isValid() ? ctx.storage->ptr(info.instRef) : nullptr;
            if (!inst || inst->op != MicroInstrOpcode::ClearReg)
                return false;
            const MicroInstrOperand* ops = inst->ops(*ctx.operands);
            return ops && ops[1].opBits == MicroOpBits::B128;
        }

        // Whether `reg` is a cleared vector register where `atRef` reads it.
        bool isZeroVectorAt(const Context& ctx, const MicroReg reg, const MicroInstrRef atRef)
        {
            if (!reg.isVirtualFloat())
                return false;
            const auto def = ctx.ssa->reachingDef(reg, atRef);
            return def.valid() && isZeroVectorValue(ctx, def.valueId, 0);
        }

        // Whether the read may move from the load to `useRef`: the reader
        // follows the load in the same straight line, and nothing in between
        // writes memory, is a call, or redefines the base.
        bool readMovesToReader(const Context& ctx, const MicroInstrRef loadRef, const MicroInstrRef useRef, const MicroReg base)
        {
            MicroInstrRef ref = ctx.storage->findNextInstructionRef(loadRef);
            for (uint32_t step = 0; ref.isValid() && step < K_MAX_VECFOLD_WINDOW; ++step, ref = ctx.storage->findNextInstructionRef(ref))
            {
                if (ref == useRef)
                    return true;
                const MicroInstr* inst = ctx.storage->ptr(ref);
                if (!inst || isControlOrCall(*inst) || writesMemory(*inst))
                    return false;
                const MicroInstrUseDef* useDef = ctx.ssa->instrUseDef(ref);
                if (useDef && std::ranges::find(useDef->defs, base) != useDef->defs.end())
                    return false;
            }
            return false;
        }

        struct Fold
        {
            MicroInstrRef ref;
            MicroReg      dst;
            MicroOp       widen  = MicroOp::VecWidenLoU8;
            uint64_t      offset = 0;
        };
    }

    bool tryFoldVecLoadIntoWiden(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        // The front end reads a vector through either load form; both carry
        // [dst, base, opBits, offset].
        if (ctx.isClaimed(loadRef) || ctx.isRelocated(loadRef) || !ctx.ssa)
            return false;
        if (loadInst.op != MicroInstrOpcode::LoadVecRegMem && loadInst.op != MicroInstrOpcode::LoadRegMem)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps || loadOps[2].opBits != MicroOpBits::B128)
            return false;

        const MicroReg vt   = loadOps[0].reg;
        const MicroReg base = loadOps[1].reg;
        const uint64_t off  = loadOps[3].valueU64;
        if (!vt.isVirtualFloat() || !base.isVirtualInt())
            return false;
        // A frame slot belongs to slot promotion, a global to its own
        // instruction-pointer form.
        if (keepAccessScalar(ctx, loadRef, base) || isFrameDerivedAddress(ctx, base, loadRef) || isRelocatedAddress(ctx, base, loadRef))
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, valueId))
            return false;
        const auto values = ctx.ssa->values();
        if (valueId >= values.size())
            return false;

        SmallVector<Fold, 4> folds;
        for (const MicroSsaState::UseSite& use : values[valueId].uses)
        {
            // A phi is the loop header's; its readers are counted below.
            if (use.kind != MicroSsaState::UseSite::Kind::Instruction)
                continue;
            if (!use.instRef.isValid() || ctx.isClaimed(use.instRef) || ctx.isRelocated(use.instRef))
                return false;

            const MicroInstr*        useInst = ctx.storage->ptr(use.instRef);
            const MicroInstrOperand* useOps  = useInst ? useInst->ops(*ctx.operands) : nullptr;
            if (!useOps)
                return false;

            Fold fold;
            fold.ref = use.instRef;
            if (useInst->op == MicroInstrOpcode::VecUnaryRegReg)
            {
                // ops: [0] dst, [1] src, [2] opBits, [3] microOp
                if (useOps[1].reg != vt || useOps[2].opBits != MicroOpBits::B128 || !isLowWiden(useOps[3].microOp))
                    return false;
                fold.dst    = useOps[0].reg;
                fold.widen  = useOps[3].microOp;
                fold.offset = off;
            }
            else if (useInst->op == MicroInstrOpcode::OpBinaryRegRegReg)
            {
                // ops: [0] dst, [1] src1, [2] src2, [3] opBits, [4] microOp
                if (useOps[1].reg != vt || useOps[2].reg == vt || useOps[3].opBits != MicroOpBits::B128)
                    return false;
                if (!widenOfUnpackHi(useOps[4].microOp, fold.widen) || !isZeroVectorAt(ctx, useOps[2].reg, use.instRef))
                    return false;
                fold.dst    = useOps[0].reg;
                fold.offset = off + 8;
            }
            else
                return false;

            if (!fold.dst.isVirtualFloat() || !readMovesToReader(ctx, loadRef, use.instRef, base))
                return false;
            folds.push_back(fold);
        }

        // Every reader of the value, through the phis a loop header places on
        // it, is one of the folds: a reader behind a phi would take the bytes
        // of the trip before.
        if (folds.empty() || ctx.ssa->transitiveInstructionUseCount(valueId, static_cast<uint32_t>(folds.size()) + 1) != folds.size())
            return false;

        if (!ctx.claimAll({loadRef}))
            return false;
        for (const Fold& fold : folds)
        {
            if (!ctx.claimAll({fold.ref}))
                return false;
        }

        for (const Fold& fold : folds)
        {
            MicroInstrOperand ops[5] = {};
            ops[0].reg               = fold.dst;
            ops[1].reg               = base;
            ops[2].opBits            = MicroOpBits::B128;
            ops[3].valueU64          = fold.offset;
            ops[4].microOp           = fold.widen;
            ctx.emitRewrite(fold.ref, MicroInstrOpcode::VecUnaryRegMem, std::span<const MicroInstrOperand>(ops, 5), true);
        }
        ctx.emitErase(loadRef);
        return true;
    }
}

SWC_END_NAMESPACE();
