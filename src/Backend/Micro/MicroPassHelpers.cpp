#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/ApsInt.h"

SWC_BEGIN_NAMESPACE();

MicroPassHelpers::FramePrivacy MicroPassHelpers::analyzeFramePrivacy(const MicroPassContext& context, std::span<const MicroInstrRef> refs, std::span<const MicroInstrUseDef> useDefs, const FlatKeyMap<RegDefinitionSummary>& definitions, bool collectEscapes)
{
    FramePrivacy   result;
    const MicroReg stackPointer = CallConv::get(context.callConvKind).stackPointer;
    const auto&    storage      = *context.instructions;
    const auto&    operands     = *context.operands;
    if (!stackPointer.isValid())
    {
        result.framePrivate = false;
        return result;
    }
    const auto propagatesAddress = [](const MicroInstr& inst, const MicroInstrOperand* ops) {
        if (inst.op == MicroInstrOpcode::LoadRegReg || inst.op == MicroInstrOpcode::LoadAddrRegMem)
            return ops && ops[2].opBits == MicroOpBits::B64;
        return inst.op == MicroInstrOpcode::LoadAddrAmcRegMem && ops && ops[3].opBits == MicroOpBits::B64;
    };
    bool changed = true;
    while (changed)
    {
        changed = false;
        for (uint32_t i = 0; i < refs.size(); ++i)
        {
            const MicroInstr* inst = storage.ptr(refs[i]);
            const auto*       ops  = inst ? inst->ops(operands) : nullptr;
            if (!inst || !propagatesAddress(*inst, ops) || useDefs[i].defs.size() != 1)
                continue;
            const MicroReg dst = useDefs[i].defs[0];
            const RegDefinitionSummary* def = definitions.find(dst.packed);
            if (!dst.isVirtualInt() || !def || def->count != 1 || result.frameDerived.contains(dst))
                continue;
            if (result.isFrame(ops[1].reg, stackPointer))
            {
                result.frameDerived.insert(dst);
                changed = true;
            }
        }
    }
    for (uint32_t i = 0; i < refs.size(); ++i)
    {
        const MicroInstr* inst = storage.ptr(refs[i]);
        const auto*       ops  = inst ? inst->ops(operands) : nullptr;
        if (!inst || !ops)
            continue;
        const auto& info        = MicroInstr::info(inst->op);
        uint8_t     baseIndex   = 0;
        const bool  hasBase     = dereferenceBaseOperandIndex(baseIndex, inst->op, info);
        const bool  propagation = propagatesAddress(*inst, ops) && result.frameDerived.contains(ops[0].reg);
        const auto  modes       = info.resolvedRegModes(ops);
        for (size_t operand = 0; operand < modes.size(); ++operand)
        {
            if (modes[operand] != MicroInstrRegMode::Use && modes[operand] != MicroInstrRegMode::UseDef)
                continue;
            if (!result.isFrame(ops[operand].reg, stackPointer))
                continue;
            // Match operand positions: storing the same pointer used as the
            // destination base still exposes that pointer as a value.
            if ((hasBase && operand == baseIndex) || (propagation && operand == 1))
                continue;
            if (ops[operand].reg == stackPointer && inst->op == MicroInstrOpcode::OpBinaryRegImm && operand == 0 &&
                (ops[2].microOp == MicroOp::Add || ops[2].microOp == MicroOp::Subtract))
                continue;
            result.framePrivate = false;
            if (!collectEscapes)
                return result;
            result.escapes.push_back(refs[i]);
            break;
        }
    }
    return result;
}

// One entry per instruction the walk reaches with a known displacement, which is most of the
// function: a flat table holds them where a node-based map allocated one node each.
FlatKeyMap<uint64_t> MicroPassHelpers::collectStackPointerOffsets(const MicroPassContext& context, MicroInstrRef frameBaseRef, uint64_t frameBaseOffset)
{
    FlatKeyMap<uint64_t> result;
    const auto&          cfg   = context.builder->controlFlowGraph();
    const uint32_t       entry = cfg.indexOf(frameBaseRef);
    if (entry == MicroControlFlowGraph::K_NO_INDEX || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.addressTakenLabelIndices().empty())
        return result;
    const auto&    callConv     = CallConv::get(context.callConvKind);
    const MicroReg stackPointer = callConv.stackPointer;
    const auto     refs         = cfg.instructionRefs();
    // 0: unvisited, 1: one known displacement, 2: conflicting or unknown.
    std::vector<uint8_t>  states(refs.size());
    std::vector<uint64_t> offsets(refs.size());
    std::vector<uint32_t> pending{entry};
    states[entry]  = 1;
    offsets[entry] = 0ull - frameBaseOffset;
    while (!pending.empty())
    {
        const uint32_t index = pending.back();
        pending.pop_back();
        uint8_t           state  = states[index];
        uint64_t          offset = offsets[index];
        const MicroInstr& inst   = *context.instructions->ptr(refs[index]);
        const auto*       ops    = inst.ops(*context.operands);
        if (state == 1)
        {
            if (inst.op == MicroInstrOpcode::Push)
                offset -= callConv.stackSlotSize();
            else if (inst.op == MicroInstrOpcode::Pop)
            {
                if (ops[0].reg == stackPointer)
                    state = 2;
                else
                    offset += callConv.stackSlotSize();
            }
            else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg == stackPointer && ops[1].opBits == MicroOpBits::B64 &&
                     (ops[2].microOp == MicroOp::Add || ops[2].microOp == MicroOp::Subtract))
                offset += ops[2].microOp == MicroOp::Add ? ops[3].valueU64 : 0ull - ops[3].valueU64;
            else if (ops)
            {
                const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
                for (size_t operand = 0; operand < modes.size(); ++operand)
                    if ((modes[operand] == MicroInstrRegMode::Def || modes[operand] == MicroInstrRegMode::UseDef) && ops[operand].reg == stackPointer)
                        state = 2;
            }
        }
        for (const uint32_t successor : cfg.successors(index))
        {
            if (states[successor] == 2)
                continue;
            if (states[successor] == 1 && state == 1 && offsets[successor] == offset)
                continue;
            if (states[successor])
                states[successor] = 2;
            else
            {
                states[successor]  = state;
                offsets[successor] = offset;
            }
            pending.push_back(successor);
        }
    }
    for (uint32_t index = 0; index < refs.size(); ++index)
        if (states[index] == 1)
            result.emplace(refs[index].get(), offsets[index]);
    return result;
}

FlatKeySet MicroPassHelpers::collectReadOnlyCallRefs(const MicroBuilder& builder)
{
    FlatKeySet refs;
    for (const MicroRelocation& relocation : builder.codeRelocations())
    {
        if (relocation.instructionRef.isValid() && relocation.targetSymbol && relocation.targetSymbol->isFunction() &&
            relocation.targetSymbol->cast<SymbolFunction>().attributes().hasRtFlag(RtAttributeFlagsE::ReadOnly))
            refs.insert(relocation.instructionRef.get());
    }
    return refs;
}

FlatKeySet MicroPassHelpers::collectReportCallRefs(const MicroBuilder& builder)
{
    const IdentifierManager& idMgr = builder.ctx().idMgr();
    const std::array         names = {
        idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::SafetyPanic),
        idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::Panic),
        idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::FailedExpect),
    };

    FlatKeySet refs;
    for (const MicroRelocation& relocation : builder.codeRelocations())
    {
        if (relocation.instructionRef.isInvalid() || !relocation.targetSymbol)
            continue;
        const IdentifierRef idRef = relocation.targetSymbol->idRef();
        if (idRef.isValid() && std::ranges::find(names, idRef) != names.end())
            refs.insert(relocation.instructionRef.get());
    }
    return refs;
}

// Logical complement of a branch condition at the CPU-flag level. The pairs
// are exact complements over (CF, ZF, SF, OF, PF), so flipping is valid for
// both integer and floating-point (unordered) comparisons. Anything
// unexpected reports failure and blocks the rewrite.
bool MicroPassHelpers::invertCondition(MicroCond& outInverted, MicroCond cond)
{
    switch (cond)
    {
        case MicroCond::Equal: outInverted = MicroCond::NotEqual; return true;
        case MicroCond::NotEqual: outInverted = MicroCond::Equal; return true;
        case MicroCond::Zero: outInverted = MicroCond::NotZero; return true;
        case MicroCond::NotZero: outInverted = MicroCond::Zero; return true;
        case MicroCond::Less: outInverted = MicroCond::GreaterOrEqual; return true;
        case MicroCond::GreaterOrEqual: outInverted = MicroCond::Less; return true;
        case MicroCond::Greater: outInverted = MicroCond::LessOrEqual; return true;
        case MicroCond::LessOrEqual: outInverted = MicroCond::Greater; return true;
        case MicroCond::Below: outInverted = MicroCond::AboveOrEqual; return true;
        case MicroCond::AboveOrEqual: outInverted = MicroCond::Below; return true;
        case MicroCond::Above: outInverted = MicroCond::BelowOrEqual; return true;
        case MicroCond::BelowOrEqual: outInverted = MicroCond::Above; return true;
        case MicroCond::NotAbove: outInverted = MicroCond::Above; return true;
        case MicroCond::Overflow: outInverted = MicroCond::NotOverflow; return true;
        case MicroCond::NotOverflow: outInverted = MicroCond::Overflow; return true;
        case MicroCond::Parity: outInverted = MicroCond::NotParity; return true;
        case MicroCond::NotParity: outInverted = MicroCond::Parity; return true;
        case MicroCond::EvenParity: outInverted = MicroCond::NotEvenParity; return true;
        case MicroCond::NotEvenParity: outInverted = MicroCond::EvenParity; return true;
        case MicroCond::Sign: outInverted = MicroCond::NotSign; return true;
        case MicroCond::NotSign: outInverted = MicroCond::Sign; return true;
        default: return false;
    }
}

bool MicroPassHelpers::violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!context.encoder || !ops)
        return false;

    MicroConformanceIssue issue;
    return context.encoder->queryConformanceIssue(issue, inst, ops);
}

bool MicroPassHelpers::instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    if (!info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
        return false;

    if ((inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm) &&
        ops &&
        ops[0].cpuCond == MicroCond::Unconditional)
    {
        return false;
    }

    return true;
}

namespace
{
    // Whether the x64 form of a micro-op writes EFLAGS. Shifts and rotates
    // count as writers (they are, for any non-zero count).
    bool microOpWritesCpuFlags(const MicroOp op)
    {
        if (isVecMicroOp(op))
            return false;
        switch (op)
        {
            case MicroOp::Exchange:
            case MicroOp::Move:
            case MicroOp::MoveSignExtend:
            case MicroOp::LoadEffectiveAddress:
            case MicroOp::BitwiseNot:
            case MicroOp::ByteSwap:
            case MicroOp::ConvertFloatToFloat:
            case MicroOp::ConvertFloatToInt:
            case MicroOp::ConvertIntToFloat:
            case MicroOp::ConvertInt64ToFloat32:
            case MicroOp::ConvertInt32ToFloat64:
            case MicroOp::ConvertUIntToFloat64:
            case MicroOp::FloatAddProduct:
            case MicroOp::FloatSubtractProduct:
            case MicroOp::FloatProductAdd:
            case MicroOp::FloatProductSubtractFrom:
            case MicroOp::FloatAdd:
            case MicroOp::FloatAnd:
            case MicroOp::FloatDivide:
            case MicroOp::FloatMax:
            case MicroOp::FloatMin:
            case MicroOp::FloatMultiply:
            case MicroOp::FloatRound:
            case MicroOp::FloatSqrt:
            case MicroOp::FloatSubtract:
            case MicroOp::FloatXor:
            case MicroOp::MultiplyAdd:
                return false;
            default:
                return true;
        }
    }
}

bool MicroPassHelpers::instructionActuallyDefinesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    if (!info.flags.has(MicroInstrFlagsE::DefinesCpuFlags))
        return false;
    if (!ops)
        return true;

    switch (inst.op)
    {
        case MicroInstrOpcode::ClearReg:
            // XORPS/XORPD clear an XMM value without changing integer flags.
            return !ops[0].reg.isAnyFloat();
        case MicroInstrOpcode::OpUnaryReg:
        case MicroInstrOpcode::OpUnaryMem:
        case MicroInstrOpcode::OpBinaryRegImm:
        case MicroInstrOpcode::OpBinaryMemImm:
            return microOpWritesCpuFlags(ops[2].microOp);
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryMemReg:
            return microOpWritesCpuFlags(ops[3].microOp);
        case MicroInstrOpcode::OpBinaryRegAmcMem:
        case MicroInstrOpcode::OpBinaryAmcMemReg:
        case MicroInstrOpcode::OpUnaryAmcMem:
        case MicroInstrOpcode::OpBinaryAmcMemImm:
            return microOpWritesCpuFlags(ops[7].microOp);
        default:
            return true;
    }
}

bool MicroPassHelpers::instructionOverwritesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!ops || !instructionActuallyDefinesCpuFlags(inst, ops))
        return false;

    MicroOp                  op;
    MicroOpBits              bits;
    const MicroInstrOperand* count = nullptr;
    switch (inst.op)
    {
        case MicroInstrOpcode::OpBinaryRegImm:
        case MicroInstrOpcode::OpBinaryMemImm:
            op    = ops[2].microOp;
            bits  = ops[1].opBits;
            count = &ops[inst.op == MicroInstrOpcode::OpBinaryRegImm ? 3 : 4];
            break;
        case MicroInstrOpcode::OpUnaryReg:
        case MicroInstrOpcode::OpUnaryMem:
            op   = ops[2].microOp;
            bits = ops[1].opBits;
            break;
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryMemReg:
            op   = ops[3].microOp;
            bits = ops[2].opBits;
            break;
        case MicroInstrOpcode::OpBinaryRegAmcMem:
        case MicroInstrOpcode::OpBinaryAmcMemReg:
            op   = ops[7].microOp;
            bits = ops[inst.op == MicroInstrOpcode::OpBinaryRegAmcMem ? 3 : 4].opBits;
            break;
        case MicroInstrOpcode::OpBinaryAmcMemImm:
            op    = ops[7].microOp;
            bits  = ops[2].opBits;
            count = &ops[6];
            break;
        case MicroInstrOpcode::OpUnaryAmcMem:
            // The unary Add/Subtract forms encode INC/DEC. They preserve CF,
            // so they never overwrite the complete abstract flags value.
            op   = ops[7].microOp;
            bits = ops[4].opBits;
            if (op == MicroOp::Add || op == MicroOp::Subtract)
                return false;
            break;
        default:
            return true;
    }

    switch (op)
    {
        case MicroOp::RotateLeft:
        case MicroOp::RotateRight:
            // Rotates preserve ZF, SF and PF regardless of the count.
            return false;
        case MicroOp::ShiftLeft:
        case MicroOp::ShiftArithmeticLeft:
        case MicroOp::ShiftRight:
        case MicroOp::ShiftArithmeticRight:
            // A register count may be zero. Immediate counts use the same
            // five/six-bit mask as x64; a masked zero preserves all flags.
            return count && !count->hasWideImmediateValue() &&
                   (count->valueU64 & (bits == MicroOpBits::B64 ? 63ull : 31ull)) != 0;
        default:
            return true;
    }
}

namespace
{
    uint32_t computeNextVirtualRegIndex(const MicroPassContext& context, bool isFloat, uint32_t nextIndex)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        for (const MicroInstr& inst : context.instructions->view())
        {
            const MicroInstrOperand* ops = inst.ops(*context.operands);
            if (!ops)
                continue;
            const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] == MicroInstrRegMode::None)
                    continue;

                const MicroReg reg = ops[i].reg;
                if (isFloat ? !reg.isVirtualFloat() : !reg.isVirtualInt())
                    continue;

                if (reg.index() < MicroReg::K_MAX_INDEX)
                    nextIndex = std::max(nextIndex, reg.index() + 1);
                else
                    nextIndex = MicroReg::K_MAX_INDEX;
            }
        }

        return nextIndex;
    }
}

uint32_t MicroPassHelpers::computeNextVirtualIntRegIndex(const MicroPassContext& context)
{
    uint32_t hint = 1;
    if (context.builder)
        hint = std::max(hint, context.builder->nextVirtualIntRegIndexHint());
    return computeNextVirtualRegIndex(context, false, hint);
}

uint32_t MicroPassHelpers::computeNextVirtualFloatRegIndex(const MicroPassContext& context)
{
    return computeNextVirtualRegIndex(context, true, 1);
}

void MicroPassHelpers::collectFrameDerivedRegs(FlatKeySet& out, const MicroStorage& storage, const MicroOperandStorage& operands, const MicroReg stackPointer)
{
    out = {};
    if (!stackPointer.isValid())
        return;
    out.insert(stackPointer.packed);

    bool changed = true;
    while (changed)
    {
        changed = false;
        for (const MicroInstr& inst : storage.view())
        {
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            bool derived = false;
            switch (inst.op)
            {
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadAddrRegMem:
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    derived = out.contains(ops[1].reg.packed);
                    break;
                case MicroInstrOpcode::OpBinaryRegReg:
                    derived = ops[3].microOp == MicroOp::Add && out.contains(ops[1].reg.packed);
                    break;
                case MicroInstrOpcode::OpBinaryRegRegReg:
                    derived = ops[4].microOp == MicroOp::Add && (out.contains(ops[1].reg.packed) || out.contains(ops[2].reg.packed));
                    break;
                case MicroInstrOpcode::OpBinaryRegRegImm:
                    derived = (ops[3].microOp == MicroOp::Add || ops[3].microOp == MicroOp::Subtract) && out.contains(ops[1].reg.packed);
                    break;
                default:
                    break;
            }

            if (derived && out.insert(ops[0].reg.packed))
                changed = true;
        }
    }
}

void MicroPassHelpers::collectFrameVariableExtents(std::vector<std::pair<uint64_t, uint64_t>>& out, const MicroPassContext& context, const MicroReg frameBase)
{
    out.clear();
    if (!context.sanitizerFunction || (context.debugStackBaseVirtualReg.isValid() && context.debugStackBaseVirtualReg != frameBase))
        return;
    for (const SymbolVariable* localVar : context.sanitizerFunction->localVariables())
    {
        if (!localVar || !localVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            continue;
        const uint64_t size = localVar->codeGenLocalSize();
        if (size)
            out.emplace_back(localVar->offset(), localVar->offset() + size);
    }
}

void MicroPassHelpers::computeNextVirtualRegIndices(const MicroPassContext& context, uint32_t& outIntIndex, uint32_t& outFloatIndex)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    outIntIndex   = context.builder ? std::max(1u, context.builder->nextVirtualIntRegIndexHint()) : 1;
    outFloatIndex = 1;
    for (const MicroInstr& inst : context.instructions->view())
    {
        const MicroInstrOperand* ops = inst.ops(*context.operands);
        if (!ops)
            continue;
        const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
        for (size_t i = 0; i < modes.size(); ++i)
        {
            if (modes[i] == MicroInstrRegMode::None || !ops[i].reg.isVirtual())
                continue;
            const MicroReg reg       = ops[i].reg;
            uint32_t&      nextIndex = reg.isVirtualFloat() ? outFloatIndex : outIntIndex;
            if (reg.index() < MicroReg::K_MAX_INDEX)
                nextIndex = std::max(nextIndex, reg.index() + 1);
            else
                nextIndex = MicroReg::K_MAX_INDEX;
        }
    }
}

bool MicroPassHelpers::areCpuFlagsDeadAfter(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstrRef afterRef, MicroBuilder* builder)
{
    for (MicroStorage::ConstIterator it{&storage, storage.findNextInstructionRef(afterRef)}; it.current.isValid(); ++it)
    {
        const MicroInstr* scanInst = &*it;

        const MicroInstrDef&     info           = MicroInstr::info(scanInst->op);
        const bool               mayUseFlags    = info.flags.has(MicroInstrFlagsE::UsesCpuFlags);
        const bool               mayDefineFlags = info.flags.has(MicroInstrFlagsE::DefinesCpuFlags);
        const MicroInstrOperand* scanOps        = mayUseFlags || mayDefineFlags ? scanInst->ops(operands) : nullptr;
        if (mayUseFlags && instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            return false;

        // A jump preserves the flags. Its destination can read them even if
        // the jump itself is unconditional; only a CFG walk can prove otherwise.
        if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
            return builder && areCpuFlagsDeadAfterInCfg(*builder, it.current);
        if ((mayDefineFlags && instructionOverwritesCpuFlags(*scanInst, scanOps)) ||
            info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
        {
            return true;
        }
    }

    return true;
}

bool MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstrRef instRef)
{
    for (MicroStorage::ConstIterator it{&storage, storage.findNextInstructionRef(instRef)}; it.current.isValid(); ++it)
    {
        const MicroInstr* scanInst = &*it;

        const MicroInstrDef&     scanInfo       = MicroInstr::info(scanInst->op);
        const bool               mayUseFlags    = scanInfo.flags.has(MicroInstrFlagsE::UsesCpuFlags);
        const bool               mayDefineFlags = scanInfo.flags.has(MicroInstrFlagsE::DefinesCpuFlags);
        const MicroInstrOperand* scanOps        = mayUseFlags || mayDefineFlags ? scanInst->ops(operands) : nullptr;
        if (mayUseFlags && instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            return false;

        if (scanInst->op == MicroInstrOpcode::Label ||
            scanInfo.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
            scanInfo.flags.has(MicroInstrFlagsE::JumpInstruction) ||
            scanInfo.flags.has(MicroInstrFlagsE::IsCallInstruction))
            return false;

        if (mayDefineFlags && instructionOverwritesCpuFlags(*scanInst, scanOps))
            return true;
    }

    return false;
}

bool MicroPassHelpers::areCpuFlagsDeadAfterInCfg(MicroBuilder& builder, MicroInstrRef afterRef)
{
    const auto& cfg = builder.controlFlowGraph();
    if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
        return false;
    const uint32_t index = cfg.indexOf(afterRef);
    if (index == MicroControlFlowGraph::K_NO_INDEX)
        return false;
    return areCpuFlagsDeadAfterInCfg(cfg, builder.instructions(), builder.operands(), index);
}

bool MicroPassHelpers::areCpuFlagsDeadAfterInCfg(const MicroControlFlowGraph& cfg, const MicroStorage& storage, const MicroOperandStorage& operands, const uint32_t index)
{
    const uint32_t count = cfg.instructionCount();
    if (index >= count)
        return false;

    // Queries are sequential on each compiler worker. A stamp avoids clearing
    // every CFG row when a candidate only visits a few successors.
    thread_local std::vector<uint8_t>  visited;
    thread_local uint8_t               visitStamp = 0;
    thread_local SmallVector<uint32_t> worklist;
    if (visited.size() < count)
        visited.resize(count, 0);
    if (++visitStamp == 0)
    {
        std::ranges::fill(visited, 0);
        ++visitStamp;
    }
    worklist.clear();
    for (const uint32_t successor : cfg.successors(index))
        worklist.push_back(successor);

    while (!worklist.empty())
    {
        const uint32_t i = worklist.back();
        worklist.pop_back();
        SWC_ASSERT(i < count);
        if (visited[i] == visitStamp)
            continue;
        visited[i] = visitStamp;

        const MicroInstr* inst = storage.ptr(cfg.instructionRefs()[i]);
        if (!inst)
            return false;
        const MicroInstrFlags    flags          = MicroInstr::info(inst->op).flags;
        const bool               mayUseFlags    = flags.has(MicroInstrFlagsE::UsesCpuFlags);
        const bool               mayDefineFlags = flags.has(MicroInstrFlagsE::DefinesCpuFlags);
        const MicroInstrOperand* ops            = mayUseFlags || mayDefineFlags ? inst->ops(operands) : nullptr;
        if (mayUseFlags && instructionActuallyUsesCpuFlags(*inst, ops))
            return false;
        if ((mayDefineFlags && instructionOverwritesCpuFlags(*inst, ops)) || flags.has(MicroInstrFlagsE::IsCallInstruction))
            continue;
        for (const uint32_t successor : cfg.successors(i))
            worklist.push_back(successor);
    }

    return true;
}

uint32_t MicroPassHelpers::replaceRegInLocalUses(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef afterInstRef, MicroReg fromReg, MicroReg toReg)
{
    if (!fromReg.isValid() || fromReg.isNoBase())
        return 0;
    if (fromReg == toReg)
        return 0;

    uint32_t replacedCount = 0;

    const MicroStorage::View view = storage.view();
    auto                     it   = view.begin();
    while (it != view.end() && it.current != afterInstRef)
        ++it;
    if (it == view.end())
        return 0;
    ++it;

    for (; it != view.end(); ++it)
    {
        MicroInstr&            inst   = *it;
        const MicroInstrUseDef useDef = inst.collectUseDef(operands, nullptr);

        // Stop at control flow barriers.
        if (MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
            break;

        // Stop if toReg is redefined (replacement would change semantics).
        if (microRegSpanContains(useDef.defs, toReg))
            break;

        // Collect mutable register operand refs.
        MicroInstrRegOperandRefs refs;
        inst.collectRegOperands(operands, refs, nullptr);

        bool replacedInThisInst = false;
        bool fromRegDefined     = false;
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg)
                continue;

            if (*ref.reg == fromReg && ref.def)
                fromRegDefined = true;

            if (*ref.reg == fromReg && ref.use)
            {
                *ref.reg           = toReg;
                replacedInThisInst = true;
            }
        }

        if (replacedInThisInst)
            ++replacedCount;

        // Stop if fromReg is redefined (subsequent uses see a new value).
        if (fromRegDefined)
            break;
    }

    return replacedCount;
}

namespace
{
    bool mapMicroOpToFoldOp(Math::FoldBinaryOp& outOp, bool& outIsSigned, MicroOp microOp)
    {
        outIsSigned = false;
        switch (microOp)
        {
            case MicroOp::Add:
                outOp = Math::FoldBinaryOp::Add;
                return true;
            case MicroOp::Subtract:
                outOp = Math::FoldBinaryOp::Subtract;
                return true;
            case MicroOp::MultiplySigned:
                outOp       = Math::FoldBinaryOp::Multiply;
                outIsSigned = true;
                return true;
            case MicroOp::MultiplyUnsigned:
                outOp = Math::FoldBinaryOp::Multiply;
                return true;
            case MicroOp::DivideSigned:
                outOp       = Math::FoldBinaryOp::Divide;
                outIsSigned = true;
                return true;
            case MicroOp::DivideUnsigned:
                outOp = Math::FoldBinaryOp::Divide;
                return true;
            case MicroOp::ModuloSigned:
                outOp       = Math::FoldBinaryOp::Modulo;
                outIsSigned = true;
                return true;
            case MicroOp::ModuloUnsigned:
                outOp = Math::FoldBinaryOp::Modulo;
                return true;
            case MicroOp::And:
                outOp = Math::FoldBinaryOp::BitwiseAnd;
                return true;
            case MicroOp::Or:
                outOp = Math::FoldBinaryOp::BitwiseOr;
                return true;
            case MicroOp::Xor:
                outOp = Math::FoldBinaryOp::BitwiseXor;
                return true;
            case MicroOp::ShiftLeft:
                outOp = Math::FoldBinaryOp::ShiftLeft;
                return true;
            case MicroOp::ShiftRight:
                outOp = Math::FoldBinaryOp::ShiftRight;
                return true;
            case MicroOp::ShiftArithmeticRight:
                outOp       = Math::FoldBinaryOp::ShiftArithmeticRight;
                outIsSigned = true;
                return true;
            default:
                return false;
        }
    }
}

Math::FoldStatus MicroPassHelpers::foldBinaryImmediate(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits)
{
    Math::FoldBinaryOp foldOp;
    bool               isSigned;
    if (!mapMicroOpToFoldOp(foldOp, isSigned, op))
        return Math::FoldStatus::Unsupported;

    const uint32_t bitWidth = getNumBits(opBits);
    if (!bitWidth)
        return Math::FoldStatus::Unsupported;

    const bool   isUnsigned = !isSigned;
    const ApsInt lhsInt(static_cast<int64_t>(lhs), bitWidth, isUnsigned);
    const ApsInt rhsInt(static_cast<int64_t>(rhs), bitWidth, isUnsigned);
    ApsInt       result;

    const Math::FoldStatus status = Math::foldBinaryInt(result, lhsInt, rhsInt, foldOp);
    if (status != Math::FoldStatus::Ok)
        return status;

    outValue = result.as64() & getBitsMask(opBits);
    return Math::FoldStatus::Ok;
}

namespace
{
    bool tryFoldAddSub(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm)
    {
        const uint64_t mask        = getBitsMask(opBits);
        const uint64_t a           = firstImm & mask;
        const uint64_t b           = secondImm & mask;
        const bool     firstIsSub  = firstOp == MicroOp::Subtract;
        const bool     secondIsSub = secondOp == MicroOp::Subtract;

        uint64_t addImm = 0;
        if (firstIsSub == secondIsSub)
            addImm = firstIsSub ? ((0u - (a + b)) & mask) : ((a + b) & mask);
        else if (firstIsSub)
            addImm = (b - a) & mask;
        else
            addImm = (a - b) & mask;

        const uint64_t subImm = (0u - addImm) & mask;
        if (addImm <= subImm)
        {
            outOp  = MicroOp::Add;
            outImm = addImm;
        }
        else
        {
            outOp  = MicroOp::Subtract;
            outImm = subImm;
        }
        return true;
    }

    bool foldSameBitwise(MicroOp op, uint64_t lhs, uint64_t rhs, MicroOpBits opBits, uint64_t& outImm)
    {
        uint64_t   value  = 0;
        const auto status = MicroPassHelpers::foldBinaryImmediate(value, lhs, rhs, op, opBits);
        if (status != Math::FoldStatus::Ok)
            return false;
        outImm = value & getBitsMask(opBits);
        return true;
    }
}

bool MicroPassHelpers::tryReassociateBinaryImmediate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm)
{
    const bool firstIsAddSub  = firstOp == MicroOp::Add || firstOp == MicroOp::Subtract;
    const bool secondIsAddSub = secondOp == MicroOp::Add || secondOp == MicroOp::Subtract;
    if (firstIsAddSub && secondIsAddSub)
        return tryFoldAddSub(firstOp, firstImm, secondOp, secondImm, opBits, outOp, outImm);

    // Equal right/left shifts discard the low bits, including an arithmetic
    // right shift: its sign fill is shifted back out. Keep 64-bit masks within
    // a sign-extended immediate so folding cannot introduce a mask register.
    const bool firstRight = firstOp == MicroOp::ShiftRight || firstOp == MicroOp::ShiftArithmeticRight;
    const bool secondLeft = secondOp == MicroOp::ShiftLeft || secondOp == MicroOp::ShiftArithmeticLeft;
    if (firstRight && secondLeft && firstImm == secondImm && firstImm > 0 && firstImm <= 31 &&
        (opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64))
    {
        outOp  = MicroOp::And;
        outImm = (~0ull << firstImm) & getBitsMask(opBits);
        return true;
    }

    if (firstOp != secondOp)
        return false;

    switch (firstOp)
    {
        case MicroOp::And:
        case MicroOp::Or:
        case MicroOp::Xor:
        case MicroOp::MultiplySigned:
        case MicroOp::MultiplyUnsigned:
            outOp = firstOp;
            return foldSameBitwise(firstOp, firstImm, secondImm, opBits, outImm);

        case MicroOp::ShiftLeft:
        case MicroOp::ShiftRight:
        case MicroOp::ShiftArithmeticRight:
        {
            const uint32_t width = getNumBits(opBits);
            if (firstImm >= width || secondImm >= width)
                return false;
            const uint64_t sum = firstImm + secondImm;
            if (sum >= width)
                return false;
            outOp  = firstOp;
            outImm = sum;
            return true;
        }

        default:
            return false;
    }
}

uint32_t MicroPassHelpers::findSingleCfgEntry(const MicroControlFlowGraph& cfg)
{
    const uint32_t n     = cfg.instructionCount();
    uint32_t       entry = MicroDomTree::K_INVALID_NODE;
    for (uint32_t i = 0; i < n; ++i)
    {
        if (cfg.predecessors(i).empty())
        {
            if (entry != MicroDomTree::K_INVALID_NODE)
                return MicroDomTree::K_INVALID_NODE;
            entry = i;
        }
    }
    return entry;
}

namespace
{
    struct GraphWalkScratch
    {
        std::vector<uint8_t>  marks;
        std::vector<uint32_t> stack;
        std::vector<uint32_t> childCursor;
        std::vector<uint32_t> postorder;
        std::vector<uint64_t> useMasks;
        std::vector<uint64_t> defMasks;
    };

    GraphWalkScratch& graphWalkScratch()
    {
        thread_local GraphWalkScratch scratch;
        return scratch;
    }
}

void MicroPassHelpers::computePhysicalLiveness(MicroPhysLiveness& out, const MicroPassContext& context, const MicroPhysLivenessMode mode)
{
    out.valid = false;
    if (!context.builder || !context.instructions || !context.operands)
        return;

    const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
    if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
        return;

    const auto     instructionRefs = cfg.instructionRefs();
    const auto     successors      = cfg.successors();
    const auto     predecessors    = cfg.predecessors();
    const uint32_t instCount       = static_cast<uint32_t>(instructionRefs.size());
    if (!instCount)
        return;

    // A register the mask cannot name (a special, or an index past the word)
    // contributes nothing to the set, and isLiveOut answers "live" for it, so
    // dropping it here stays conservative on both sides.
    auto maskOf = [](const MicroReg reg) -> uint64_t {
        const uint32_t bit = MicroPhysLiveness::bitOf(reg);
        return bit < MicroPhysLiveness::K_INVALID_BIT ? 1ull << bit : 0ull;
    };

    auto&      scratch        = graphWalkScratch();
    const bool retainUseDefs  = mode == MicroPhysLivenessMode::WithUseDefs;
    const bool recordDeadDefs = mode == MicroPhysLivenessMode::DeadDefs || mode == MicroPhysLivenessMode::DeadDefsBeforePrologue;
    if (retainUseDefs)
        out.useDefs.resize(instCount);
    else
        out.useDefs.clear();
    if (recordDeadDefs)
        out.deadDefs.resize(instCount);
    else
        out.deadDefs.clear();
    scratch.useMasks.resize(instCount);
    scratch.defMasks.resize(instCount);
    MicroInstrUseDef scratchUseDef;
    for (uint32_t i = 0; i < instCount; ++i)
    {
        const MicroInstr* inst = context.instructions->ptr(instructionRefs[i]);
        if (!inst)
            return;
        const MicroInstrDef& info = MicroInstr::info(inst->op);
        if (!retainUseDefs &&
            !info.flags.has(MicroInstrFlagsE::IsCallInstruction) &&
            (!context.encoder || !info.flags.has(MicroInstrFlagsE::EncoderRegUseDef)))
        {
            uint64_t useMask       = 0;
            uint64_t defMask       = 0;
            bool     hasDef        = false;
            bool     hasUnknownDef = false;
            if (const MicroInstrOperand* ops = inst->ops(*context.operands))
            {
                const auto modes = info.resolvedRegModes(ops);
                for (size_t operand = 0; operand < modes.size(); ++operand)
                {
                    if (modes[operand] == MicroInstrRegMode::None)
                        continue;
                    const uint64_t bit = maskOf(ops[operand].reg);
                    if (modes[operand] == MicroInstrRegMode::Use || modes[operand] == MicroInstrRegMode::UseDef)
                        useMask |= bit;
                    if (modes[operand] == MicroInstrRegMode::Def || modes[operand] == MicroInstrRegMode::UseDef)
                    {
                        defMask |= bit;
                        if (recordDeadDefs && ops[operand].reg.isValid() && !ops[operand].reg.isNoBase())
                        {
                            hasDef = true;
                            hasUnknownDef |= bit == 0;
                        }
                    }
                }
            }
            scratch.useMasks[i] = useMask;
            scratch.defMasks[i] = defMask;
            if (recordDeadDefs)
                out.deadDefs[i] = hasDef && !hasUnknownDef;
            continue;
        }

        MicroInstrUseDef& useDef = retainUseDefs ? out.useDefs[i] : scratchUseDef;
        inst->collectUseDef(useDef, *context.operands, context.encoder);
        uint64_t useMask = 0;
        uint64_t defMask = 0;
        for (const MicroReg reg : useDef.uses)
            useMask |= maskOf(reg);
        if (recordDeadDefs)
        {
            bool hasUnknownDef = false;
            for (const MicroReg reg : useDef.defs)
            {
                const uint64_t bit = maskOf(reg);
                defMask |= bit;
                hasUnknownDef |= bit == 0;
            }
            out.deadDefs[i] = !useDef.defs.empty() && !hasUnknownDef;
        }
        else
        {
            for (const MicroReg reg : useDef.defs)
                defMask |= maskOf(reg);
        }
        scratch.useMasks[i] = useMask;
        scratch.defMasks[i] = defMask;
    }

    const CallConv& conv        = CallConv::get(context.callConvKind);
    uint64_t        exitLiveOut = 0;
    if (context.usesIntReturnRegOnRet)
        exitLiveOut |= maskOf(conv.intReturn);
    if (context.usesFloatReturnRegOnRet)
        exitLiveOut |= maskOf(conv.floatReturn);
    exitLiveOut |= maskOf(conv.stackPointer);
    exitLiveOut |= maskOf(conv.framePointer);
    if (mode != MicroPhysLivenessMode::DeadDefsBeforePrologue)
    {
        for (const MicroReg reg : conv.intPersistentRegs)
            exitLiveOut |= maskOf(reg);
        for (const MicroReg reg : conv.floatPersistentRegs)
            exitLiveOut |= maskOf(reg);
    }

    // Every node is visited below. Its live-out is overwritten on its first
    // visit; propagation reads only live-in, so no seed is needed.
    out.liveOut.resize(instCount);

    const auto computeLiveIn = [&](const uint32_t i) {
        uint64_t newOut = 0;
        if (successors[i].empty())
        {
            newOut = exitLiveOut;
        }
        else
        {
            for (const uint32_t succ : successors[i])
                newOut |= out.liveIn[succ];
        }

        out.liveOut[i] = newOut;

        // live_in = (live_out \ defs) | uses
        return (newOut & ~scratch.defMasks[i]) | scratch.useMasks[i];
    };

    // With no back-edge, every successor has already been solved by a single
    // reverse sweep. Only cyclic graphs need predecessor requeues.
    if (!cfg.hasLoop())
    {
        // Every successor has been written before it is read, so retained
        // entries need no zeroing on the acyclic path.
        out.liveIn.resize(instCount);
        for (uint32_t i = instCount; i != 0;)
        {
            --i;
            out.liveIn[i] = computeLiveIn(i);
        }
    }
    else
    {
        out.liveIn.assign(instCount, 0);
        // Graph walks run sequentially on a worker and reuse the same buffers.
        auto& inWorklist = scratch.marks;
        auto& worklist   = scratch.stack;
        inWorklist.assign(instCount, 1);
        worklist.clear();
        worklist.reserve(instCount);
        for (uint32_t i = 0; i < instCount; ++i)
            worklist.push_back(i);

        while (!worklist.empty())
        {
            const uint32_t i = worklist.back();
            worklist.pop_back();
            inWorklist[i]        = 0;
            const uint64_t newIn = computeLiveIn(i);
            if (newIn == out.liveIn[i])
                continue;
            out.liveIn[i] = newIn;

            for (const uint32_t pred : predecessors[i])
            {
                if (!inWorklist[pred])
                {
                    worklist.push_back(pred);
                    inWorklist[pred] = 1;
                }
            }
        }
    }

    if (recordDeadDefs)
    {
        for (uint32_t i = 0; i < instCount; ++i)
            out.deadDefs[i] &= (scratch.defMasks[i] & out.liveOut[i]) == 0;
    }

    out.valid = true;
}

void MicroPassHelpers::NaturalLoop::collectBody(const MicroControlFlowGraph& cfg)
{
    const uint32_t n = cfg.instructionCount();
    inBody.assign(n, 0);
    inBody[header] = 1;
    bodySize       = 1;
    bodyBegin      = header;
    bodyEnd        = header + 1;

    // Backward reachability from every tail, stopping at the header: that is exactly the set of
    // instructions the loop can execute.
    auto& stack = graphWalkScratch().stack;
    stack.clear();
    for (const uint32_t tail : tails)
    {
        if (tail < n && !inBody[tail])
        {
            inBody[tail] = 1;
            ++bodySize;
            bodyBegin = std::min(bodyBegin, tail);
            bodyEnd   = std::max(bodyEnd, tail + 1);
            stack.push_back(tail);
        }
    }

    while (!stack.empty())
    {
        const uint32_t node = stack.back();
        stack.pop_back();
        for (const uint32_t pred : cfg.predecessors(node))
        {
            SWC_ASSERT(pred < n);
            if (!inBody[pred])
            {
                inBody[pred] = 1;
                ++bodySize;
                bodyBegin = std::min(bodyBegin, pred);
                bodyEnd   = std::max(bodyEnd, pred + 1);
                stack.push_back(pred);
            }
        }
    }
}

std::unordered_map<uint32_t, MicroPassHelpers::NaturalLoop> MicroPassHelpers::findNaturalLoops(const MicroControlFlowGraph& cfg, const MicroDomTree& dom)
{
    const uint32_t                            n = cfg.instructionCount();
    std::unordered_map<uint32_t, NaturalLoop> loopsByHeader;

    for (uint32_t u = 0; u < n; ++u)
    {
        if (!dom.reachable(u))
            continue;
        for (const uint32_t v : cfg.successors(u))
        {
            // A back edge is an edge to a node that dominates its own source.
            SWC_ASSERT(v < n);
            if (dom.dominates(v, u))
            {
                NaturalLoop& loop = loopsByHeader[v];
                loop.header       = v;
                loop.tails.push_back(u);
            }
        }
    }

    for (NaturalLoop& loop : loopsByHeader | std::views::values)
        loop.collectBody(cfg);

    return loopsByHeader;
}

MicroPassHelpers::MicroDomTree MicroPassHelpers::computeInstructionDominators(const MicroControlFlowGraph& cfg, const uint32_t entry, const MicroSsaState* ssa)
{
    MicroDomTree reused;
    if (entry == 0 && ssa && ssa->copyInstructionDominators(reused, cfg))
        return reused;

    const uint32_t n = cfg.instructionCount();
    if (entry >= n)
        return {};
    std::vector<uint32_t> idom(n, MicroDomTree::K_INVALID_NODE);
    std::vector<uint32_t> rpoPosition(n, MicroDomTree::K_INVALID_NODE);

    auto& scratch     = graphWalkScratch();
    auto& postorder   = scratch.postorder;
    auto& childCursor = scratch.childCursor;
    auto& rpo         = scratch.stack;
    rpo.clear();

    auto intersect = [&](uint32_t a, uint32_t b) {
        while (a != b)
        {
            while (rpoPosition[a] > rpoPosition[b])
                a = idom[a];
            while (rpoPosition[b] > rpoPosition[a])
                b = idom[b];
        }
        return a;
    };

    idom[entry] = entry;
    if (!cfg.hasLoop())
    {
        // Every edge points forward. Process reachable nodes in instruction
        // order; an unreachable predecessor still has no dominator and is
        // ignored exactly as it is in the general traversal.
        rpoPosition[entry] = 0;
        rpo.push_back(entry);
        for (uint32_t node = entry + 1; node < n; ++node)
        {
            uint32_t newIdom = MicroDomTree::K_INVALID_NODE;
            for (const uint32_t pred : cfg.predecessors(node))
            {
                SWC_ASSERT(pred < n);
                if (idom[pred] == MicroDomTree::K_INVALID_NODE)
                    continue;
                newIdom = (newIdom == MicroDomTree::K_INVALID_NODE) ? pred : intersect(pred, newIdom);
            }
            if (newIdom == MicroDomTree::K_INVALID_NODE)
                continue;
            idom[node]        = newIdom;
            rpoPosition[node] = static_cast<uint32_t>(rpo.size());
            rpo.push_back(node);
        }
    }
    else
    {
        postorder.clear();
        postorder.reserve(n);
        auto& visited = scratch.marks;
        visited.assign(n, 0);
        childCursor.assign(n, 0);
        rpo.push_back(entry);
        visited[entry] = 1;
        while (!rpo.empty())
        {
            const uint32_t u    = rpo.back();
            const auto&    succ = cfg.successors(u);
            if (childCursor[u] < succ.size())
            {
                const uint32_t v = succ[childCursor[u]++];
                SWC_ASSERT(v < n);
                if (!visited[v])
                {
                    visited[v] = 1;
                    rpo.push_back(v);
                }
            }
            else
            {
                postorder.push_back(u);
                rpo.pop_back();
            }
        }

        const uint32_t count = static_cast<uint32_t>(postorder.size());
        rpo.reserve(count);
        for (uint32_t i = count; i-- > 0;)
        {
            const uint32_t node = postorder[i];
            rpoPosition[node]   = static_cast<uint32_t>(rpo.size());
            rpo.push_back(node);
        }

        bool changed = true;
        while (changed)
        {
            changed = false;
            for (const uint32_t node : rpo)
            {
                if (node == entry)
                    continue;
                uint32_t    newIdom      = MicroDomTree::K_INVALID_NODE;
                const auto& predecessors = cfg.predecessors(node);
                if (predecessors.size() == 1)
                {
                    // A non-entry DFS node's sole predecessor is its tree parent,
                    // already processed in reverse postorder. It is also its idom.
                    newIdom = predecessors.front();
                    SWC_ASSERT(newIdom < n && idom[newIdom] != MicroDomTree::K_INVALID_NODE);
                }
                else
                {
                    for (const uint32_t pred : predecessors)
                    {
                        SWC_ASSERT(pred < n);
                        if (idom[pred] == MicroDomTree::K_INVALID_NODE)
                            continue;
                        newIdom = (newIdom == MicroDomTree::K_INVALID_NODE) ? pred : intersect(pred, newIdom);
                    }
                }
                if (newIdom != MicroDomTree::K_INVALID_NODE && newIdom != idom[node])
                {
                    idom[node] = newIdom;
                    changed    = true;
                }
            }
        }
    }

    // Reuse the CFG traversal buffers for dominator-tree child links. The
    // result still retains only two arrays; no ancestor table is needed.
    auto& firstChild  = childCursor;
    auto& nextSibling = postorder;
    firstChild.assign(n, MicroDomTree::K_INVALID_NODE);
    // Each reachable non-entry node gets a sibling link below before the
    // subtree walk can read it; retained entries need no clearing.
    nextSibling.resize(n);
    for (const uint32_t node : rpo)
    {
        if (node == entry)
            continue;
        const uint32_t parent = idom[node];
        nextSibling[node]     = firstChild[parent];
        firstChild[parent]    = node;
    }

    // Immediate dominators and RPO positions are no longer queried. Their
    // buffers become the subtree intervals returned to the optimization passes.
    // Both started with invalid entries; the tree walk overwrites every
    // reachable node, leaving unreachable entries invalid without another fill.
    auto& subtreeBegin = rpoPosition;
    auto& subtreeEnd   = idom;
    auto& pending      = rpo;
    pending.clear();
    pending.push_back(entry);
    uint32_t position   = 0;
    subtreeBegin[entry] = position++;
    while (!pending.empty())
    {
        const uint32_t node  = pending.back();
        const uint32_t child = firstChild[node];
        if (child != MicroDomTree::K_INVALID_NODE)
        {
            firstChild[node]    = nextSibling[child];
            subtreeBegin[child] = position++;
            pending.push_back(child);
        }
        else
        {
            subtreeEnd[node] = position;
            pending.pop_back();
        }
    }

    return {.subtreeBegin = std::move(subtreeBegin), .subtreeEnd = std::move(subtreeEnd)};
}

bool MicroPassHelpers::amcLayoutFor(AmcLayout& out, MicroInstrOpcode op)
{
    switch (op)
    {
        case MicroInstrOpcode::LoadAmcRegMem:
        case MicroInstrOpcode::LoadSignedExtAmcRegMem:
        case MicroInstrOpcode::LoadZeroExtAmcRegMem:
        case MicroInstrOpcode::LoadAddrAmcRegMem:
        case MicroInstrOpcode::VecUnaryAmcRegMem:
        case MicroInstrOpcode::OpBinaryRegAmcMem:
        case MicroInstrOpcode::CmpRegAmc:
            return true;
        case MicroInstrOpcode::LoadAmcMemReg:
        case MicroInstrOpcode::LoadAmcMemImm:
        case MicroInstrOpcode::OpBinaryAmcMemReg:
        case MicroInstrOpcode::OpUnaryAmcMem:
        case MicroInstrOpcode::OpBinaryAmcMemImm:
            out.baseIdx  = 0;
            out.indexIdx = 1;
            if (op == MicroInstrOpcode::OpBinaryAmcMemImm)
            {
                out.mulIdx = 4;
                out.addIdx = 5;
            }
            return true;
        case MicroInstrOpcode::CmpAmcImm:
            out.baseIdx  = 0;
            out.indexIdx = 1;
            out.mulIdx   = 4;
            out.addIdx   = 5;
            return true;
        case MicroInstrOpcode::CmpAmcReg:
            out.baseIdx  = 0;
            out.indexIdx = 1;
            out.mulIdx   = 5;
            out.addIdx   = 6;
            return true;
        default:
            return false;
    }
}

bool MicroPassHelpers::dereferenceBaseOperandIndex(uint8_t& outIndex, MicroInstrOpcode op, const MicroInstrDef& def)
{
    // Forming an address is not reading through it: one past the end is legal to compute.
    if (op == MicroInstrOpcode::LoadAddrRegMem || op == MicroInstrOpcode::LoadAddrAmcRegMem)
        return false;

    AmcLayout layout;
    if (amcLayoutFor(layout, op))
    {
        outIndex = layout.baseIdx;
        return true;
    }

    if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return false;

    outIndex = def.memBaseOperandIndex;
    return true;
}

void MicroPassHelpers::collectImmutableStorageBases(FlatKeySet& out, const MicroPassContext& context)
{
    out = {};
    if (!context.builder || !context.instructions || !context.operands)
        return;
    const std::unordered_set<MicroReg>& marked = context.builder->immutableStorageBases();
    if (marked.empty())
        return;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    // Registers by packed form. The defined ones are also listed, for the final pass.
    FlatKeySet                                    defined;
    SmallVector<MicroReg, 4>                      definedList;
    FlatKeySet                                    rejected;
    SmallVector<std::pair<MicroReg, MicroReg>, 4> copies;
    for (const MicroInstr& inst : storage.view())
    {
        if (!inst.numOperands)
            continue;
        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;

        const MicroInstrDef& info      = MicroInstr::info(inst.op);
        uint8_t              baseIndex = 0;
        const bool           readsBase = !info.flags.has(MicroInstrFlagsE::WritesMemory) &&
                               !info.flags.has(MicroInstrFlagsE::IsCallInstruction) &&
                               dereferenceBaseOperandIndex(baseIndex, inst.op, info);
        const auto modes = info.resolvedRegModes(ops);
        for (size_t operandIndex = 0; operandIndex < modes.size(); ++operandIndex)
        {
            const MicroInstrRegMode mode = modes[operandIndex];
            if (mode == MicroInstrRegMode::None)
                continue;
            const MicroReg reg = ops[operandIndex].reg;
            if (!reg.isValid() || reg.isNoBase() || !marked.contains(reg))
                continue;

            if (mode == MicroInstrRegMode::Def || mode == MicroInstrRegMode::UseDef)
            {
                // The one definition takes the incoming argument: a copy of its register or
                // of another marked base, or a read of its stack slot.
                const bool fromArgument = mode == MicroInstrRegMode::Def && operandIndex == 0 &&
                                          ((inst.op == MicroInstrOpcode::LoadRegReg && ops[2].opBits == MicroOpBits::B64 &&
                                            (!ops[1].reg.isVirtual() || marked.contains(ops[1].reg))) ||
                                           (inst.op == MicroInstrOpcode::LoadRegMem && ops[2].opBits == MicroOpBits::B64 &&
                                            !ops[1].reg.isVirtual()));
                if (!fromArgument || !defined.insert(reg.packed))
                {
                    if (rejected.insert(reg.packed) && rejected.size() == marked.size())
                        return;
                }
                else
                {
                    definedList.push_back(reg);
                }
                continue;
            }

            if (readsBase && operandIndex == baseIndex)
                continue;

            // A value handle handed to a callee in an argument register stays immutable:
            // the callee takes it by value and cannot write through the address either.
            if (inst.op == MicroInstrOpcode::LoadRegReg && operandIndex == 1 && ops[2].opBits == MicroOpBits::B64 &&
                ops[0].reg.isAnyInt() && !ops[0].reg.isVirtual() && context.builder->forwardableStorageBases().contains(reg))
                continue;

            // A copy into another marked base names the same storage: the two stand or
            // fall together.
            if (inst.op == MicroInstrOpcode::LoadRegReg && operandIndex == 1 &&
                ops[2].opBits == MicroOpBits::B64 && marked.contains(ops[0].reg))
            {
                copies.push_back({reg, ops[0].reg});
                continue;
            }

            // Rejection is permanent. Once every marked base is rejected,
            // neither later operands nor copy propagation can add an output.
            if (rejected.insert(reg.packed) && rejected.size() == marked.size())
                return;
        }
    }

    for (bool changed = !rejected.empty() && !copies.empty(); changed;)
    {
        changed = false;
        for (const auto& [from, to] : copies)
        {
            const bool fromRejected = rejected.contains(from.packed);
            const bool toRejected   = rejected.contains(to.packed);
            if (fromRejected != toRejected)
            {
                rejected.insert(fromRejected ? to.packed : from.packed);
                if (rejected.size() == marked.size())
                    return;
                changed = true;
            }
        }
    }

    for (const MicroReg reg : definedList)
    {
        if (!rejected.contains(reg.packed))
            out.insert(reg.packed);
    }
}

bool MicroPassHelpers::definesZeroHighBits(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!ops)
        return false;

    switch (inst.op)
    {
        // The width operand sits at a different index per opcode; each of these is the one
        // that governs the destination register.
        case MicroInstrOpcode::ClearReg:
        case MicroInstrOpcode::LoadRegImm:
        case MicroInstrOpcode::OpUnaryReg:
        case MicroInstrOpcode::OpBinaryRegImm:
            return ops[1].opBits == MicroOpBits::B32;

        case MicroInstrOpcode::LoadRegReg:
        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadAddrRegMem:
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::OpBinaryRegMem:
            return ops[2].opBits == MicroOpBits::B32;

        case MicroInstrOpcode::LoadAmcRegMem:
        case MicroInstrOpcode::LoadAddrAmcRegMem:
        case MicroInstrOpcode::LoadCondRegReg:
            return ops[3].opBits == MicroOpBits::B32;

        // The three-register form also carries the vector operations, whose narrow widths name
        // a lane rather than a cleared half.
        case MicroInstrOpcode::OpBinaryRegRegReg:
            return ops[0].reg.isAnyInt() && ops[3].opBits == MicroOpBits::B32;

        // A zero-extension writes the whole register with the top half clear whatever the
        // width it reads.
        case MicroInstrOpcode::LoadZeroExtRegReg:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        case MicroInstrOpcode::LoadZeroExtAmcRegMem:
            return true;

        default:
            return false;
    }
}

SWC_END_NAMESPACE();
