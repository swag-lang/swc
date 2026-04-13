#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroUseDefMap.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA constant folding — purely semantic.
// Tracks known constant values per register and folds them through operations.
// Does NOT change instruction forms (e.g., RegReg -> RegImm); form selection is
// a post-RA concern that depends on physical register encoding constraints.
//
// Patterns handled:
//   LoadRegImm v1, C; OpBinaryRegImm v1, op, imm  ->  LoadRegImm v1, fold(C, imm, op)
//   LoadRegImm v1, C; LoadRegReg v2, v1            ->  LoadRegImm v2, C
//   ClearReg v1                                    ->  track v1 = 0
//
// State is cleared at control flow barriers (labels, branches, calls, ret).

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownValue
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    using KnownMap = std::unordered_map<MicroReg, KnownValue>;

    void clearState(KnownMap& known)
    {
        known.clear();
    }

    void killDef(KnownMap& known, MicroReg reg)
    {
        known.erase(reg);
    }

    void killDefs(KnownMap& known, const MicroInstrUseDef& useDef)
    {
        for (const MicroReg reg : useDef.defs)
            killDef(known, reg);
    }

    void setKnown(KnownMap& known, MicroReg reg, uint64_t value, MicroOpBits opBits)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        known[reg] = {value & getBitsMask(opBits), opBits};
    }

    const KnownValue* getKnown(const KnownMap& known, MicroReg reg)
    {
        const auto it = known.find(reg);
        if (it == known.end())
            return nullptr;
        return &it->second;
    }

    // LoadRegImm v, C  ->  track v = C
    void trackLoadRegImm(KnownMap& known, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::LoadRegImm || !ops)
            return;
        if (!ops[0].reg.isAnyInt())
            return;

        setKnown(known, ops[0].reg, ops[2].valueU64, ops[1].opBits);
    }

    // ClearReg v  ->  track v = 0
    void trackClearReg(KnownMap& known, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::ClearReg || !ops)
            return;
        if (!ops[0].reg.isAnyInt())
            return;

        setKnown(known, ops[0].reg, 0, ops[1].opBits);
    }

    // LoadRegReg dst, src  ->  if src is known, rewrite to LoadRegImm dst, C
    bool tryFoldCopyFromKnown(KnownMap& known, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        if (!ops || inst.numOperands < 3)
            return false;
        if (!ops[0].reg.isAnyInt() || !ops[1].reg.isAnyInt())
            return false;
        if (ops[2].opBits != MicroOpBits::B64)
            return false;

        const KnownValue* srcKnown = getKnown(known, ops[1].reg);
        if (!srcKnown)
            return false;

        // Rewrite: LoadRegReg dst, src  ->  LoadRegImm dst, C
        const MicroReg dstReg = ops[0].reg;
        inst.op               = MicroInstrOpcode::LoadRegImm;
        ops[0].reg            = dstReg;
        ops[1].opBits         = srcKnown->opBits;
        ops[2].valueU64       = srcKnown->value;
        inst.numOperands      = 3;

        setKnown(known, dstReg, srcKnown->value, srcKnown->opBits);
        return true;
    }

    // OpBinaryRegImm dst, op, imm  ->  if dst is known, fold to LoadRegImm dst, result
    bool tryFoldBinaryRegImm(KnownMap& known, const MicroPassContext& context, MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (!ops || inst.numOperands < 4)
            return false;
        if (!ops[0].reg.isAnyInt())
            return false;

        const KnownValue* dstKnown = getKnown(known, ops[0].reg);
        if (!dstKnown)
            return false;

        // Cross-check: verify the reaching definition is a constant-producing instruction.
        if (context.useDefMap)
        {
            const auto reachDef = context.useDefMap->reachingDef(ops[0].reg, instRef);
            if (!reachDef.valid())
                return false;
            if (reachDef.inst->op != MicroInstrOpcode::LoadRegImm && reachDef.inst->op != MicroInstrOpcode::ClearReg)
                return false;
        }

        const MicroOp     microOp = ops[2].microOp;
        const MicroOpBits opBits  = ops[1].opBits;
        const uint64_t    imm     = ops[3].valueU64;

        uint64_t   result = 0;
        const auto status = MicroPassHelpers::foldBinaryImmediate(result, dstKnown->value, imm, microOp, opBits);
        if (status != Math::FoldStatus::Ok)
            return false;

        // Rewrite: OpBinaryRegImm dst, op, imm  ->  LoadRegImm dst, result
        const MicroReg dstReg = ops[0].reg;
        inst.op               = MicroInstrOpcode::LoadRegImm;
        ops[0].reg            = dstReg;
        ops[1].opBits         = opBits;
        ops[2].valueU64       = result;
        inst.numOperands      = 3;

        setKnown(known, dstReg, result, opBits);
        return true;
    }
}

Result MicroConstantFoldingPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/ConstFold");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    KnownMap known;
    known.reserve(64);

    const auto view  = storage.view();
    const auto endIt = view.end();
    for (auto it = view.begin(); it != endIt; ++it)
    {
        const MicroInstrRef    instRef = it.current;
        MicroInstr&            inst    = *it;
        MicroInstrOperand*     ops     = inst.ops(operands);
        const MicroInstrUseDef useDef  = inst.collectUseDef(operands, context.encoder);

        // Clear state at control flow barriers.
        if (MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
        {
            clearState(known);
            continue;
        }

        // Try folding patterns.
        bool changed = false;
        changed      = changed | tryFoldCopyFromKnown(known, inst, ops);
        changed      = changed | tryFoldBinaryRegImm(known, context, instRef, inst, ops);

        if (changed)
            context.passChanged = true;

        // Kill defs before tracking new known values.
        if (changed)
        {
            const MicroInstrUseDef newUseDef = inst.collectUseDef(operands, context.encoder);
            killDefs(known, newUseDef);
        }
        else
        {
            killDefs(known, useDef);
        }

        // Track new known values from the (possibly rewritten) instruction.
        trackLoadRegImm(known, inst, ops);
        trackClearReg(known, inst, ops);

        // Calls clobber transient registers.
        if (useDef.isCall)
            clearState(known);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
