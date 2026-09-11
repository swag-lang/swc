#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Support/Core/SmallVector.h"

// A vector load whose every reader widens half of it.
//
//     LoadVecRegMem      vt,  [b+o]           (or the 128-bit LoadRegMem,
//     VecUnaryRegReg     lo,  vt, widenLo           or the indexed LoadAmcRegMem)
//     OpBinaryRegRegReg  hi,  vt, zero, unpackHi   (the high eight, against zero)
//   ->
//     VecUnaryRegMem     lo,  [b+o],   widenLo
//     VecUnaryRegMem     hi,  [b+o+8], widenLo
//
// Each half is one widening from memory instead of a load and a widening:
// no register holds the sixteen bytes, and the zero goes unread. An indexed
// load becomes the indexed widening the same way. The reads move to the
// readers, so nothing between the load and a reader may write memory,
// transfer control, or redefine the address registers - except a store into
// this function's own frame when the load reads through a pointer that came
// from outside it: an argument, or an address computed from one, was formed
// before the frame existed and cannot point into it. A deblocking filter
// builds its strength vectors in frame temporaries between the row loads
// and the high widenings; without that exception every row stayed in a
// register across the whole low half, and spilled.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_VECFOLD_WINDOW = 512;
        constexpr uint32_t K_MAX_ORIGIN_DEPTH   = 12;
        constexpr uint32_t K_MAX_ENTRY_WALK     = 256;

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

        // The address a load reads: a base and an offset, with an index, a
        // scale and an addressing width for the indexed form.
        struct LoadAddress
        {
            bool        indexed  = false;
            MicroReg    base     = MicroReg::invalid();
            MicroReg    index    = MicroReg::invalid();
            MicroOpBits addrBits = MicroOpBits::B64;
            uint64_t    mul      = 1;
            uint64_t    offset   = 0;
        };

        bool readLoadAddress(LoadAddress& out, const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            switch (inst.op)
            {
                case MicroInstrOpcode::LoadVecRegMem:
                case MicroInstrOpcode::LoadRegMem:
                    // ops: [0] dst, [1] base, [2] opBits, [3] offset
                    if (ops[2].opBits != MicroOpBits::B128)
                        return false;
                    out.base   = ops[1].reg;
                    out.offset = ops[3].valueU64;
                    return out.base.isVirtualInt();
                case MicroInstrOpcode::LoadAmcRegMem:
                    // ops: [0] dst, [1] base, [2] index, [3] loadBits, [4] addrBits, [5] mul, [6] add
                    if (ops[3].opBits != MicroOpBits::B128 || ops[4].opBits != MicroOpBits::B64)
                        return false;
                    out.indexed  = true;
                    out.base     = ops[1].reg;
                    out.index    = ops[2].reg;
                    out.addrBits = ops[4].opBits;
                    out.mul      = ops[5].valueU64;
                    out.offset   = ops[6].valueU64;
                    return out.base.isVirtualInt() && out.index.isVirtualInt();
                default:
                    return false;
            }
        }

        // Whether the physical register `reg` still holds what the caller put
        // in it where `atRef` reads it: the read sits in the function's entry
        // straight line, with no call, no label, and no definition of the
        // register before it. That is where the code generator copies each
        // argument register into its virtual register.
        bool isArgumentRegisterAt(const Context& ctx, const MicroReg reg, const MicroInstrRef atRef)
        {
            if (reg == ctx.stackPointer)
                return false;
            MicroInstrRef ref = ctx.storage->findPreviousInstructionRef(atRef);
            for (uint32_t step = 0; step < K_MAX_ENTRY_WALK; ++step, ref = ctx.storage->findPreviousInstructionRef(ref))
            {
                if (!ref.isValid())
                    return true;
                const MicroInstr* inst = ctx.storage->ptr(ref);
                if (!inst || isControlOrCall(*inst))
                    return false;
                const MicroInstrUseDef* useDef = ctx.ssa->instrUseDef(ref);
                if (useDef && std::ranges::find(useDef->defs, reg) != useDef->defs.end())
                    return false;
            }
            return false;
        }

        // Whether `reg`, where `atRef` reads it, holds a value formed from
        // arguments and constants alone: a copy of an argument register, or
        // address arithmetic over such values. Such a pointer was formed
        // before this function's frame existed and cannot point into it. A
        // phi, a value loaded from memory, and anything else answer no.
        bool isOutsideOrigin(const Context& ctx, const MicroReg reg, const MicroInstrRef atRef, const uint32_t depth)
        {
            if (depth > K_MAX_ORIGIN_DEPTH || !reg.isValid())
                return false;
            if (reg.isInt())
                return isArgumentRegisterAt(ctx, reg, atRef);
            if (!reg.isVirtualInt())
                return false;

            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid() || def.isPhi || !def.inst)
                return false;
            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            if (!ops)
                return false;

            switch (def.inst->op)
            {
                case MicroInstrOpcode::LoadRegImm:
                case MicroInstrOpcode::LoadRegPtrImm:
                    return true;
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegReg:
                    return isOutsideOrigin(ctx, ops[1].reg, def.instRef, depth + 1);
                case MicroInstrOpcode::LoadAddrRegMem:
                    return isOutsideOrigin(ctx, ops[1].reg, def.instRef, depth + 1);
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    return isOutsideOrigin(ctx, ops[1].reg, def.instRef, depth + 1) && isOutsideOrigin(ctx, ops[2].reg, def.instRef, depth + 1);
                case MicroInstrOpcode::OpBinaryRegImm:
                    // ops: [0] dst (read and written), [1] opBits, [2] microOp, [3] imm
                    return isOutsideOrigin(ctx, ops[0].reg, def.instRef, depth + 1);
                case MicroInstrOpcode::OpBinaryRegReg:
                    // ops: [0] dst (read and written), [1] src, [2] opBits, [3] microOp
                    return isOutsideOrigin(ctx, ops[0].reg, def.instRef, depth + 1) && isOutsideOrigin(ctx, ops[1].reg, def.instRef, depth + 1);
                case MicroInstrOpcode::OpBinaryRegRegReg:
                    return isOutsideOrigin(ctx, ops[1].reg, def.instRef, depth + 1) && isOutsideOrigin(ctx, ops[2].reg, def.instRef, depth + 1);
                default:
                    return false;
            }
        }

        // Whether the instruction is a store into this function's frame.
        bool storesIntoFrame(const Context& ctx, const MicroInstr& inst, const MicroInstrRef ref)
        {
            const MicroInstrDef& info = MicroInstr::info(inst.op);
            if (!info.flags.has(MicroInstrFlagsE::WritesMemory) || info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            const MicroInstrOperand* ops = inst.ops(*ctx.operands);
            if (!ops)
                return false;

            MicroPassHelpers::AmcLayout layout;
            if (MicroPassHelpers::amcLayoutFor(layout, inst.op))
                return isFrameDerivedAddress(ctx, ops[layout.baseIdx].reg, ref);
            if (!info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                return false;
            return isFrameDerivedAddress(ctx, ops[info.memBaseOperandIndex].reg, ref);
        }

        // Whether the read may move from the load to `useRef`: the reader
        // follows the load in the same straight line, and nothing in between
        // writes memory the load may read, is a call, or redefines an address
        // register.
        bool readMovesToReader(const Context& ctx, const MicroInstrRef loadRef, const MicroInstrRef useRef, const LoadAddress& address, const bool baseFromOutside)
        {
            MicroInstrRef ref = ctx.storage->findNextInstructionRef(loadRef);
            for (uint32_t step = 0; ref.isValid() && step < K_MAX_VECFOLD_WINDOW; ++step, ref = ctx.storage->findNextInstructionRef(ref))
            {
                if (ref == useRef)
                    return true;
                const MicroInstr* inst = ctx.storage->ptr(ref);
                if (!inst || isControlOrCall(*inst))
                    return false;
                if (writesMemory(*inst) && !(baseFromOutside && storesIntoFrame(ctx, *inst, ref)))
                    return false;
                const MicroInstrUseDef* useDef = ctx.ssa->instrUseDef(ref);
                if (!useDef)
                    continue;
                if (std::ranges::find(useDef->defs, address.base) != useDef->defs.end())
                    return false;
                if (address.indexed && std::ranges::find(useDef->defs, address.index) != useDef->defs.end())
                    return false;
            }
            return false;
        }

        struct Fold
        {
            MicroInstrRef ref;
            MicroReg      dst;
            MicroOp       widen = MicroOp::VecWidenLoU8;
            uint64_t      extra = 0; // eight for the high half
        };

        void emitWiden(Context& ctx, const Fold& fold, const LoadAddress& address)
        {
            if (address.indexed)
            {
                MicroInstrOperand ops[8] = {};
                ops[0].reg               = fold.dst;
                ops[1].reg               = address.base;
                ops[2].reg               = address.index;
                ops[3].opBits            = MicroOpBits::B128;
                ops[4].opBits            = address.addrBits;
                ops[5].valueU64          = address.mul;
                ops[6].valueU64          = address.offset + fold.extra;
                ops[7].microOp           = fold.widen;
                ctx.emitRewrite(fold.ref, MicroInstrOpcode::VecUnaryAmcRegMem, std::span<const MicroInstrOperand>(ops, 8), true);
                return;
            }

            MicroInstrOperand ops[5] = {};
            ops[0].reg               = fold.dst;
            ops[1].reg               = address.base;
            ops[2].opBits            = MicroOpBits::B128;
            ops[3].valueU64          = address.offset + fold.extra;
            ops[4].microOp           = fold.widen;
            ctx.emitRewrite(fold.ref, MicroInstrOpcode::VecUnaryRegMem, std::span<const MicroInstrOperand>(ops, 5), true);
        }
    }

    bool tryFoldVecLoadIntoWiden(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || ctx.isRelocated(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        LoadAddress address;
        if (!readLoadAddress(address, loadInst, loadOps))
            return false;

        const MicroReg vt = loadOps[0].reg;
        if (!vt.isVirtualFloat())
            return false;
        // A frame slot belongs to slot promotion, a global to its own
        // instruction-pointer form.
        if (keepAccessScalar(ctx, loadRef, address.base) || isFrameDerivedAddress(ctx, address.base, loadRef) || isRelocatedAddress(ctx, address.base, loadRef))
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, valueId))
            return false;
        const auto values = ctx.ssa->values();
        if (valueId >= values.size())
            return false;

        const bool baseFromOutside = isOutsideOrigin(ctx, address.base, loadRef, 0) &&
                                     (!address.indexed || isOutsideOrigin(ctx, address.index, loadRef, 0));

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
                fold.dst   = useOps[0].reg;
                fold.widen = useOps[3].microOp;
            }
            else if (useInst->op == MicroInstrOpcode::OpBinaryRegRegReg)
            {
                // ops: [0] dst, [1] src1, [2] src2, [3] opBits, [4] microOp
                if (useOps[1].reg != vt || useOps[2].reg == vt || useOps[3].opBits != MicroOpBits::B128)
                    return false;
                if (!widenOfUnpackHi(useOps[4].microOp, fold.widen) || !isZeroVectorAt(ctx, useOps[2].reg, use.instRef))
                    return false;
                fold.dst   = useOps[0].reg;
                fold.extra = 8;
            }
            else
                return false;

            if (!fold.dst.isVirtualFloat() || !readMovesToReader(ctx, loadRef, use.instRef, address, baseFromOutside))
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
            emitWiden(ctx, fold, address);
        ctx.emitErase(loadRef);
        return true;
    }
}

SWC_END_NAMESPACE();
