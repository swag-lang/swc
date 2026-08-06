#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class MicroOperandStorage;

// The machinery every peephole pass shares: a queue of rewrites collected while scanning, and
// a dispatch table that maps an opcode to the patterns worth trying on it. Each pass keeps its
// own Action and Context so it can size the operand array and carry the extra state it needs;
// only the mechanics live here.
namespace MicroPeephole
{
    // Collected rewrites and the instructions already spoken for. A pass derives its Context
    // from this and adds whatever else its patterns read.
    template<typename ACTION>
    struct RewriteQueue
    {
        MicroStorage*                storage  = nullptr;
        MicroOperandStorage*         operands = nullptr;
        std::unordered_set<uint32_t> claimed;
        SmallVector<ACTION>          actions;

        bool isClaimed(MicroInstrRef ref) const { return claimed.contains(ref.get()); }

        void emitErase(MicroInstrRef ref)
        {
            ACTION action;
            action.ref   = ref;
            action.erase = true;
            actions.push_back(action);
        }

        void emitRewrite(MicroInstrRef ref, MicroInstrOpcode newOp, std::span<const MicroInstrOperand> newOps, bool allocNewBlock = false)
        {
            SWC_ASSERT(newOps.size() <= ACTION::K_MAX_OPS);

            ACTION action;
            action.ref      = ref;
            action.newOp    = newOp;
            action.numOps   = static_cast<uint8_t>(newOps.size());
            action.allocOps = allocNewBlock;
            for (size_t idx = 0; idx < newOps.size(); ++idx)
                action.ops[idx] = newOps[idx];

            actions.push_back(action);
        }

        const MicroInstr* instruction(MicroInstrRef ref) const
        {
            SWC_ASSERT(storage != nullptr);
            return storage->ptr(ref);
        }

        const MicroInstrOperand* operandsFor(MicroInstrRef ref) const
        {
            SWC_ASSERT(operands != nullptr);
            const MicroInstr* inst = instruction(ref);
            return inst ? inst->ops(*operands) : nullptr;
        }

        MicroInstrRef nextRef(MicroInstrRef ref) const
        {
            SWC_ASSERT(storage != nullptr);
            return storage->findNextInstructionRef(ref);
        }

        MicroInstrRef previousRef(MicroInstrRef ref) const
        {
            SWC_ASSERT(storage != nullptr);
            return storage->findPreviousInstructionRef(ref);
        }
    };

    // Applies one queued rewrite. Operands are patched in place when the new count fits the
    // existing block; allocOps forces a fresh block instead.
    template<typename CTX, typename ACTION>
    void applyAction(const CTX& ctx, const ACTION& action)
    {
        SWC_ASSERT(ctx.storage != nullptr);
        SWC_ASSERT(ctx.operands != nullptr);

        if (action.erase)
        {
            ctx.storage->erase(action.ref);
            return;
        }

        MicroInstr* inst = ctx.storage->ptr(action.ref);
        SWC_ASSERT(inst != nullptr);

        if (action.allocOps)
        {
            const auto [newRef, opsBlock] = ctx.operands->emplaceUninitArray(action.numOps);
            for (uint8_t idx = 0; idx < action.numOps; ++idx)
                opsBlock[idx] = action.ops[idx];
            inst->opsRef = newRef;
        }
        else if (action.numOps)
        {
            MicroInstrOperand* existingOps = inst->ops(*ctx.operands);
            SWC_ASSERT(existingOps != nullptr);
            for (uint8_t idx = 0; idx < action.numOps; ++idx)
                existingOps[idx] = action.ops[idx];
        }

        inst->op          = action.newOp;
        inst->numOperands = action.numOps;
    }

    // Patterns indexed by the opcode they fire on, so a scan only tries what can match.
    template<typename PATTERN_FN>
    struct PatternRegistry
    {
        static constexpr size_t K_OPCODE_COUNT = MICRO_INSTR_OPCODE_INFOS.size();

        std::array<SmallVector<PATTERN_FN, 2>, K_OPCODE_COUNT> byOpcode;

        void                        add(MicroInstrOpcode op, PATTERN_FN fn) { byOpcode[static_cast<size_t>(op)].push_back(fn); }
        std::span<const PATTERN_FN> patternsFor(MicroInstrOpcode op) const { return byOpcode[static_cast<size_t>(op)].span(); }
    };
}

SWC_END_NAMESPACE();
