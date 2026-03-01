#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.Private.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"

SWC_BEGIN_NAMESPACE();

void MicroConstantPropagationPass::clearRunContext()
{
    context_         = nullptr;
    storage_         = nullptr;
    operands_        = nullptr;
    stackPointerReg_ = {};
}

void MicroConstantPropagationPass::clearState()
{
    known_.clear();
    knownStackSlots_.clear();
    knownAddresses_.clear();
    knownStackAddresses_.clear();
    knownConstantPointers_.clear();
    compareState_ = {};
    relocationByInstructionRef_.clear();
    referencedLabels_.clear();
    clearRunContext();
}

void MicroConstantPropagationPass::initRunState(MicroPassContext& context)
{
    clearState();

    context_  = &context;
    storage_  = context.instructions;
    operands_ = context.operands;

    known_.reserve(64);
    knownStackSlots_.reserve(64);
    knownAddresses_.reserve(32);
    knownStackAddresses_.reserve(32);
    knownConstantPointers_.reserve(32);

    stackPointerReg_ = CallConv::get(context.callConvKind).stackPointer;
    if (context.encoder)
        stackPointerReg_ = context.encoder->stackPointerReg();

    if (context.builder)
    {
        const auto& relocations = context.builder->codeRelocations();
        relocationByInstructionRef_.reserve(relocations.size());
        for (const auto& relocation : relocations)
            relocationByInstructionRef_[relocation.instructionRef] = &relocation;
    }

    collectReferencedLabels();
}

void MicroConstantPropagationPass::collectReferencedLabels()
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    referencedLabels_.reserve(storage_->count());
    MicroPassHelpers::collectReferencedLabels(*storage_, *operands_, referencedLabels_, true);
}

void MicroConstantPropagationPass::updateCompareStateForInstruction(const MicroInstr& inst, MicroInstrOperand* ops, std::optional<std::pair<MicroReg, uint64_t>>& deferredKnownDef)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::CmpRegImm:
        {
            if (!ops[0].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[0].reg);
            if (itKnown != known_.end())
            {
                compareState_.valid  = true;
                compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[1].opBits);
                compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(ops[2].valueU64, ops[1].opBits);
                compareState_.opBits = ops[1].opBits;
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::CmpRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            const auto itKnownLhs = known_.find(ops[0].reg);
            const auto itKnownRhs = known_.find(ops[1].reg);
            if (itKnownLhs != known_.end() && itKnownRhs != known_.end())
            {
                compareState_.valid  = true;
                compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(itKnownLhs->second.value, ops[2].opBits);
                compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(itKnownRhs->second.value, ops[2].opBits);
                compareState_.opBits = ops[2].opBits;
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::CmpMemImm:
        {
            if (!ops[0].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetFromState(stackOffset, ops[0].reg, ops[2].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[1].opBits))
                {
                    compareState_.valid  = true;
                    compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(knownValue, ops[1].opBits);
                    compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(ops[3].valueU64, ops[1].opBits);
                    compareState_.opBits = ops[1].opBits;
                }
                else
                {
                    compareState_.valid = false;
                }
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::CmpMemReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetFromState(stackOffset, ops[0].reg, ops[3].valueU64))
            {
                uint64_t   knownValue = 0;
                const auto itKnownRhs = known_.find(ops[1].reg);
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[2].opBits) && itKnownRhs != known_.end())
                {
                    compareState_.valid  = true;
                    compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                    compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(itKnownRhs->second.value, ops[2].opBits);
                    compareState_.opBits = ops[2].opBits;
                }
                else
                {
                    compareState_.valid = false;
                }
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::SetCondReg:
        {
            if (!ops[0].reg.isInt() || !compareState_.valid)
                break;

            const std::optional<bool> condValue = MicroPassHelpers::evaluateCondition(ops[1].cpuCond, compareState_.lhs, compareState_.rhs, compareState_.opBits);
            if (condValue.has_value())
                deferredKnownDef = std::pair{ops[0].reg, static_cast<uint64_t>(*condValue ? 1 : 0)};
            break;
        }
        default:
            if (MicroInstrInfo::definesCpuFlags(inst))
                compareState_.valid = false;
            break;
    }
}

void MicroConstantPropagationPass::clearControlFlowBoundaryForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (MicroPassHelpers::shouldClearDataflowStateOnControlFlowBoundary(inst, ops, referencedLabels_))
    {
        known_.clear();
        knownStackSlots_.clear();
        knownAddresses_.clear();
        knownStackAddresses_.clear();
        knownConstantPointers_.clear();
        compareState_.valid = false;
    }
}

void MicroConstantPropagationPass::clearForCallBoundary(CallConvKind callConvKind)
{
    const bool hasStackAddressArg = callHasStackAddressArgument(knownAddresses_, callConvKind);
    known_.clear();
    if (hasStackAddressArg)
        knownStackSlots_.clear();
    knownAddresses_.clear();
    knownStackAddresses_.clear();
    knownConstantPointers_.clear();
    compareState_.valid = false;
}

bool MicroConstantPropagationPass::tryResolveStackOffsetFromState(uint64_t& outOffset, MicroReg baseReg, uint64_t baseOffset) const
{
    return tryResolveStackOffset(outOffset, knownAddresses_, stackPointerReg_, baseReg, baseOffset);
}

bool MicroConstantPropagationPass::tryResolveStackOffsetForAmcFromState(uint64_t& outOffset, MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue) const
{
    return tryResolveStackOffsetForAmc(outOffset, knownAddresses_, known_, stackPointerReg_, baseReg, mulReg, mulValue, addValue);
}

bool MicroConstantPropagationPass::rewriteMemoryBaseToKnownStack(const MicroInstr& inst, MicroInstrOperand* ops) const
{
    SWC_ASSERT(context_ != nullptr);
    return tryRewriteMemoryBaseToStack(*context_, inst, ops, stackPointerReg_, knownAddresses_);
}

bool MicroConstantPropagationPass::definesRegisterInSet(MicroRegSpan defs, MicroReg reg)
{
    return microRegSpanContains(defs, reg);
}

SWC_END_NAMESPACE();
