#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.CopyElimination.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA copy elimination on virtual registers.
//
// Step 1: compute a "canonical value" lattice over SSA. A value's canonical
//         form is itself, unless it's defined by a register-to-register copy
//         from a source whose own canonical value still reaches this point —
//         in which case we transitively forward to that source. Phi nodes are
//         canonicalized only when every incoming canonical value agrees.
//
// Step 2: rewrite every virtual-register use to its canonical value, but only
//         when the canonical reg's reaching def at the use site is the same
//         SSA value we resolved (otherwise the canonical reg has been
//         redefined and we'd alias the wrong value).
//
// Step 3: rebuild SSA (live ranges and uses are now stale) and erase any copy
//         whose destination is no longer used afterwards. Self-copies are
//         removed unconditionally.
//
// Example: mov v2, v1; add v3, v2  ->  add v3, v1  (then drop the dead copy).

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CanonicalValue
    {
        MicroReg reg     = MicroReg::invalid();
        uint32_t valueId = MicroSsaState::K_INVALID_VALUE;

        bool valid() const
        {
            return reg.isValid() && valueId != MicroSsaState::K_INVALID_VALUE;
        }
    };

    bool isCopyInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return ops &&
               inst.op == MicroInstrOpcode::LoadRegReg &&
               inst.numOperands >= 3;
    }

    bool isExactVirtualIntCopy(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return isCopyInstruction(inst, ops) &&
               ops[0].reg.isVirtualInt() &&
               ops[1].reg.isVirtualInt() &&
               ops[2].opBits == MicroOpBits::B64;
    }

    bool isSelfCopy(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return isCopyInstruction(inst, ops) && ops[0].reg == ops[1].reg;
    }

    bool tryGetCanonicalValue(CanonicalValue& outValue,
                              const std::vector<CanonicalValue>& canonicalValues,
                              const std::vector<uint8_t>&        canonicalFlags,
                              const uint32_t                     valueId)
    {
        if (valueId >= canonicalFlags.size() || !canonicalFlags[valueId])
            return false;

        outValue = canonicalValues[valueId];
        return outValue.valid();
    }

    bool tryGetCanonicalReachingValue(CanonicalValue&                      outValue,
                                      const MicroSsaState&                ssaState,
                                      const std::vector<CanonicalValue>&  canonicalValues,
                                      const std::vector<uint8_t>&         canonicalFlags,
                                      const MicroReg                      reg,
                                      const MicroInstrRef                 instRef)
    {
        const auto reachingDef = ssaState.reachingDef(reg, instRef);
        if (!reachingDef.valid())
            return false;

        return tryGetCanonicalValue(outValue, canonicalValues, canonicalFlags, reachingDef.valueId);
    }

    bool sameCanonicalValue(const CanonicalValue& lhs, const CanonicalValue& rhs)
    {
        return lhs.reg == rhs.reg && lhs.valueId == rhs.valueId;
    }

    bool tryInferPhiCanonical(CanonicalValue&                     outValue,
                              const MicroSsaState::PhiInfo&       phiInfo,
                              const std::vector<CanonicalValue>&  canonicalValues,
                              const std::vector<uint8_t>&         canonicalFlags)
    {
        bool           hasCandidate = false;
        CanonicalValue candidate;

        for (const uint32_t incomingValueId : phiInfo.incomingValueIds)
        {
            CanonicalValue incomingValue;
            if (!tryGetCanonicalValue(incomingValue, canonicalValues, canonicalFlags, incomingValueId))
                return false;

            if (!hasCandidate)
            {
                candidate    = incomingValue;
                hasCandidate = true;
                continue;
            }

            if (!sameCanonicalValue(candidate, incomingValue))
                return false;
        }

        if (!hasCandidate)
            return false;

        outValue = candidate;
        return true;
    }

    bool tryInferInstructionCanonical(CanonicalValue&                     outValue,
                                      const MicroSsaState&               ssaState,
                                      const MicroStorage&                storage,
                                      const MicroOperandStorage&         operands,
                                      const std::vector<CanonicalValue>& canonicalValues,
                                      const std::vector<uint8_t>&        canonicalFlags,
                                      const uint32_t                     valueId,
                                      const MicroSsaState::ValueInfo&    valueInfo)
    {
        if (!valueInfo.instRef.isValid())
            return false;

        const MicroInstr* inst = storage.ptr(valueInfo.instRef);
        if (!inst)
            return false;

        const MicroInstrOperand* ops = inst->ops(operands);
        if (!ops)
            return false;

        if (!isExactVirtualIntCopy(*inst, ops))
        {
            outValue.reg     = valueInfo.reg;
            outValue.valueId = valueId;
            return outValue.valid();
        }

        CanonicalValue srcValue;
        if (!tryGetCanonicalReachingValue(srcValue, ssaState, canonicalValues, canonicalFlags, ops[1].reg, valueInfo.instRef))
            return false;

        const auto rootReachingDef = ssaState.reachingDef(srcValue.reg, valueInfo.instRef);
        if (!rootReachingDef.valid() || rootReachingDef.valueId != srcValue.valueId)
            return false;

        outValue = srcValue;
        return true;
    }

    void computeCanonicalValues(std::vector<CanonicalValue>& outValues,
                                std::vector<uint8_t>&        outFlags,
                                const MicroSsaState&        ssaState,
                                const MicroStorage&         storage,
                                const MicroOperandStorage&  operands)
    {
        outValues.assign(ssaState.values().size(), {});
        outFlags.assign(ssaState.values().size(), 0);

        bool changed = true;
        while (changed)
        {
            changed = false;
            const auto values = ssaState.values();
            for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
            {
                if (outFlags[valueId])
                    continue;

                const auto& valueInfo = values[valueId];
                CanonicalValue canonicalValue;
                bool           inferred = false;

                if (valueInfo.isPhi())
                {
                    const auto* phiInfo = ssaState.phiInfoForValue(valueId);
                    if (phiInfo)
                        inferred = tryInferPhiCanonical(canonicalValue, *phiInfo, outValues, outFlags);
                }
                else
                {
                    inferred = tryInferInstructionCanonical(canonicalValue, ssaState, storage, operands, outValues, outFlags, valueId, valueInfo);
                }

                if (!inferred)
                    continue;

                outValues[valueId] = canonicalValue;
                outFlags[valueId]  = 1;
                changed            = true;
            }
        }
    }

    void mergeVirtualForbiddenRegs(MicroBuilder& builder, const MicroReg fromReg, const MicroReg toReg)
    {
        if (!fromReg.isVirtual() || !toReg.isVirtual() || fromReg == toReg)
            return;

        const auto it = builder.virtualRegForbiddenPhysRegs().find(fromReg);
        if (it == builder.virtualRegForbiddenPhysRegs().end())
            return;

        builder.addVirtualRegForbiddenPhysRegs(toReg, it->second.span());
    }

    bool rewriteCanonicalUses(MicroBuilder*                      builder,
                              const MicroSsaState&               ssaState,
                              const std::vector<CanonicalValue>& canonicalValues,
                              const std::vector<uint8_t>&        canonicalFlags,
                              MicroStorage&                      storage,
                              MicroOperandStorage&               operands)
    {
        bool       changed = false;
        const auto view  = storage.view();
        const auto endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            const MicroInstrRef instRef = it.current;
            MicroInstr&         inst    = *it;
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(operands, refs, nullptr);

            for (const auto& ref : refs)
            {
                if (!ref.reg || !ref.use || ref.def || !ref.reg->isVirtual())
                    continue;

                const MicroReg oldReg = *ref.reg;
                CanonicalValue canonicalValue;
                if (!tryGetCanonicalReachingValue(canonicalValue, ssaState, canonicalValues, canonicalFlags, oldReg, instRef))
                    continue;
                if (!canonicalValue.valid() || canonicalValue.reg == oldReg)
                    continue;

                const auto rootReachingDef = ssaState.reachingDef(canonicalValue.reg, instRef);
                if (!rootReachingDef.valid() || rootReachingDef.valueId != canonicalValue.valueId)
                    continue;

                if (builder)
                    mergeVirtualForbiddenRegs(*builder, oldReg, canonicalValue.reg);

                *ref.reg = canonicalValue.reg;
                changed  = true;
            }
        }

        return changed;
    }

    bool eraseDeadCopies(MicroStorage& storage, MicroOperandStorage& operands, const MicroSsaState& ssaState)
    {
        bool changed = false;
        const auto view  = storage.view();
        const auto endIt = view.end();
        for (auto it = view.begin(); it != endIt;)
        {
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;
            ++it;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!isCopyInstruction(inst, ops))
                continue;

            if (isSelfCopy(inst, ops))
            {
                changed |= storage.erase(instRef);
                continue;
            }

            if (!ops[0].reg.isVirtual())
                continue;

            if (ssaState.isRegUsedAfter(ops[0].reg, instRef))
                continue;

            changed |= storage.erase(instRef);
        }

        return changed;
    }
}

Result MicroCopyEliminationPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/CopyElim");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;

    std::vector<CanonicalValue> canonicalValues;
    std::vector<uint8_t>        canonicalFlags;
    computeCanonicalValues(canonicalValues, canonicalFlags, *ssaState, storage, operands);

    const bool rewroteUses = rewriteCanonicalUses(context.builder, *ssaState, canonicalValues, canonicalFlags, storage, operands);

    MicroSsaState updatedSsaState;
    updatedSsaState.build(*context.builder, storage, operands, context.encoder);
    const bool erasedCopies = eraseDeadCopies(storage, operands, updatedSsaState);

    if (rewroteUses || erasedCopies)
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
