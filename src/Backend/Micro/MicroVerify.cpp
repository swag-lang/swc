#include "pch.h"
#include "Backend/Micro/MicroVerify.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/Command/CommandLine.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_HASH_OFFSET_BASIS = 1469598103934665603ull;
    constexpr uint64_t K_HASH_PRIME        = 1099511628211ull;
    constexpr uint64_t K_HASH_INVALID      = std::numeric_limits<uint64_t>::max();

    void mixHash(uint64_t& inOutHash, uint64_t value)
    {
        inOutHash ^= value;
        inOutHash *= K_HASH_PRIME;
    }

    bool shouldLogVerifyError(const MicroPassContext& context)
    {
        if (!context.taskContext)
            return false;

#if SWC_DEV_MODE
        return context.taskContext->cmdLine().microVerify;
#else
        return false;
#endif
    }

    Result reportError(const MicroPassContext& context, std::string_view phase, std::string_view message)
    {
        return MicroVerify::reportError(context, phase, message);
    }

    bool isValidOpcode(const MicroInstrOpcode op)
    {
        return static_cast<size_t>(op) < MICRO_INSTR_OPCODE_INFOS.size();
    }

    bool isValidOpBits(const MicroOpBits opBits)
    {
        switch (opBits)
        {
            case MicroOpBits::Zero:
            case MicroOpBits::B8:
            case MicroOpBits::B16:
            case MicroOpBits::B32:
            case MicroOpBits::B64:
            case MicroOpBits::B128:
                return true;
        }

        return false;
    }

    bool isValidCondition(const MicroCond cond)
    {
        return static_cast<uint8_t>(cond) <= static_cast<uint8_t>(MicroCond::NotZero);
    }

    bool isValidCallConv(const CallConvKind kind)
    {
        return static_cast<uint8_t>(kind) <= static_cast<uint8_t>(CallConvKind::Host);
    }

    bool isValidAnyRegister(const MicroReg reg)
    {
        if (!reg.isValid())
            return false;

        if (reg.isInt())
            return reg.index() < 16;
        if (reg.isFloat())
            return reg.index() < 4;
        if (reg.isVirtual())
            return true;
        if (reg.isInstructionPointer() || reg.isNoBase())
            return true;

        return false;
    }

    bool isValidNonMemoryOperandRegister(const MicroReg reg)
    {
        if (!isValidAnyRegister(reg))
            return false;
        if (reg.isInstructionPointer() || reg.isNoBase())
            return false;
        return true;
    }

    bool isValidMemoryBaseRegister(const MicroInstrOpcode op, const MicroReg reg)
    {
        if (!isValidAnyRegister(reg))
            return false;

        switch (op)
        {
            case MicroInstrOpcode::LoadAddrRegMem:
                return reg.isInt() || reg.isVirtualInt() || reg.isInstructionPointer();

            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                return reg.isInt() || reg.isVirtualInt() || reg.isNoBase();

            default:
                return reg.isInt() || reg.isVirtualInt();
        }
    }

    bool isValidAmcIndexRegister(const MicroReg reg)
    {
        if (!isValidAnyRegister(reg))
            return false;
        if (reg.isInstructionPointer() || reg.isNoBase())
            return false;
        return reg.isInt() || reg.isVirtualInt();
    }

    bool expectsRelocation(const MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
            case MicroInstrOpcode::LoadRegPtrReloc:
                return true;

            default:
                return false;
        }
    }

    uint8_t minimumOperandCount(const MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Breakpoint:
            case MicroInstrOpcode::Ret:
                return 0;

            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
            case MicroInstrOpcode::JumpReg:
                return 1;

            case MicroInstrOpcode::CallIndirect:
            case MicroInstrOpcode::SetCondReg:
            case MicroInstrOpcode::ClearReg:
                return 2;

            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegPtrReloc:
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::OpUnaryReg:
                return 3;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::LoadCondRegReg:
            case MicroInstrOpcode::OpUnaryMem:
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegImm:
                return 4;

            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::OpBinaryRegMem:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::OpTernaryRegRegReg:
                return 5;

            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                return 7;

            case MicroInstrOpcode::LoadAmcMemImm:
                return 8;

            default:
                break;
        }

        return 0;
    }

    std::array<MicroInstrRegMode, 3> resolveRegModes(const MicroInstrDef& info, const MicroInstrOperand* ops)
    {
        auto modes = info.regModes;
        if (!ops)
            return modes;

        switch (info.special)
        {
            case MicroInstrRegSpecial::None:
                break;

            case MicroInstrRegSpecial::OpBinaryRegReg:
                if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                {
                    modes[0] = MicroInstrRegMode::UseDef;
                    modes[1] = MicroInstrRegMode::UseDef;
                }
                break;

            case MicroInstrRegSpecial::OpBinaryMemReg:
                if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                    modes[1] = MicroInstrRegMode::UseDef;
                break;

            case MicroInstrRegSpecial::OpTernaryRegRegReg:
                if (ops[info.microOpIndex].microOp == MicroOp::CompareExchange)
                    modes[1] = MicroInstrRegMode::UseDef;
                break;
        }

        return modes;
    }

    Result verifyInstructionShape(const MicroPassContext& context, std::string_view phase, uint32_t instructionIndex, MicroInstrRef instructionRef, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!isValidOpcode(inst.op))
        {
            return reportError(context, phase, std::format("instruction #{} (ref={}) uses invalid opcode {}", instructionIndex, instructionRef.get(), static_cast<uint32_t>(inst.op)));
        }

        const uint8_t minOperands = minimumOperandCount(inst.op);
        if (inst.numOperands < minOperands)
        {
            return reportError(context, phase, std::format("instruction #{} (ref={}) has {} operands, expected at least {} for opcode {}", instructionIndex, instructionRef.get(), inst.numOperands, minOperands, static_cast<uint32_t>(inst.op)));
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::Label:
                if (ops[0].valueU64 > std::numeric_limits<uint32_t>::max())
                    return reportError(context, phase, std::format("label instruction #{} stores out-of-range label id {}", instructionIndex, ops[0].valueU64));
                break;

            case MicroInstrOpcode::JumpCond:
                if (!isValidCondition(ops[0].cpuCond))
                    return reportError(context, phase, std::format("jump instruction #{} uses invalid condition {}", instructionIndex, static_cast<uint32_t>(ops[0].cpuCond)));
                if (!isValidOpBits(ops[1].opBits))
                    return reportError(context, phase, std::format("jump instruction #{} uses invalid op bits {}", instructionIndex, static_cast<uint32_t>(ops[1].opBits)));
                if (ops[2].valueU64 > std::numeric_limits<uint32_t>::max())
                    return reportError(context, phase, std::format("jump instruction #{} targets out-of-range label {}", instructionIndex, ops[2].valueU64));
                break;

            case MicroInstrOpcode::JumpCondImm:
                if (!isValidCondition(ops[0].cpuCond))
                    return reportError(context, phase, std::format("jump-immediate instruction #{} uses invalid condition {}", instructionIndex, static_cast<uint32_t>(ops[0].cpuCond)));
                if (!isValidOpBits(ops[1].opBits))
                    return reportError(context, phase, std::format("jump-immediate instruction #{} uses invalid op bits {}", instructionIndex, static_cast<uint32_t>(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
            case MicroInstrOpcode::CallIndirect:
                if (!isValidCallConv(ops[MicroInstr::info(inst.op).callConvIndex].callConv))
                    return reportError(context, phase, std::format("call instruction #{} uses invalid calling convention {}", instructionIndex, static_cast<uint32_t>(ops[MicroInstr::info(inst.op).callConvIndex].callConv)));
                break;

            case MicroInstrOpcode::SetCondReg:
                if (!isValidCondition(ops[1].cpuCond))
                    return reportError(context, phase, std::format("setcc instruction #{} uses invalid condition {}", instructionIndex, static_cast<uint32_t>(ops[1].cpuCond)));
                break;

            case MicroInstrOpcode::LoadCondRegReg:
                if (!isValidCondition(ops[2].cpuCond))
                    return reportError(context, phase, std::format("conditional move instruction #{} uses invalid condition {}", instructionIndex, static_cast<uint32_t>(ops[2].cpuCond)));
                break;

            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegPtrReloc:
                if (ops[1].opBits != MicroOpBits::B64)
                    return reportError(context, phase, std::format("pointer load instruction #{} must use B64 op bits", instructionIndex));
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result verifyInstructionRegisters(const MicroPassContext& context, std::string_view phase, uint32_t instructionIndex, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        const MicroInstrDef& info  = MicroInstr::info(inst.op);
        const auto           modes = resolveRegModes(info, ops);

        for (size_t operandIndex = 0; operandIndex < modes.size(); ++operandIndex)
        {
            if (modes[operandIndex] == MicroInstrRegMode::None)
                continue;

            if (info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) && operandIndex == info.memBaseOperandIndex)
                continue;

            if (!isValidNonMemoryOperandRegister(ops[operandIndex].reg))
            {
                return reportError(context, phase, std::format("instruction #{} uses invalid register {} at operand {}", instructionIndex, ops[operandIndex].reg.packed, operandIndex));
            }
        }

        if (!info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
            return Result::Continue;

        if (info.memBaseOperandIndex >= inst.numOperands || info.memOffsetOperandIndex >= inst.numOperands)
        {
            return reportError(context, phase, std::format("instruction #{} advertises memory operands outside its operand range", instructionIndex));
        }

        if (!isValidMemoryBaseRegister(inst.op, ops[info.memBaseOperandIndex].reg))
        {
            return reportError(context, phase, std::format("instruction #{} uses invalid memory base register {} at operand {}", instructionIndex, ops[info.memBaseOperandIndex].reg.packed, info.memBaseOperandIndex));
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                if (!isValidAmcIndexRegister(ops[2].reg))
                {
                    return reportError(context, phase, std::format("instruction #{} uses invalid AMC index register {} at operand 2", instructionIndex, ops[2].reg.packed));
                }
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result verifyRelocation(const MicroPassContext& context, std::string_view phase, uint32_t relocationIndex, const MicroRelocation& relocation, const MicroInstr& inst)
    {
        if (relocation.constantRef.isValid())
        {
            if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
            {
                return reportError(context, phase, std::format("relocation #{} has constant payload but kind {}", relocationIndex, static_cast<uint32_t>(relocation.kind)));
            }
        }
        else if (relocation.targetSymbol)
        {
            const bool validKind = relocation.kind == MicroRelocation::Kind::LocalFunctionAddress || relocation.kind == MicroRelocation::Kind::ForeignFunctionAddress;
            if (!validKind || !relocation.targetSymbol->isFunction())
            {
                return reportError(context, phase, std::format("relocation #{} uses incompatible symbol target", relocationIndex));
            }
        }
        else
        {
            const bool validKind = relocation.kind == MicroRelocation::Kind::CompilerAddress ||
                                   relocation.kind == MicroRelocation::Kind::GlobalZeroAddress ||
                                   relocation.kind == MicroRelocation::Kind::GlobalInitAddress;
            if (!validKind)
            {
                return reportError(context, phase, std::format("relocation #{} is missing its target payload", relocationIndex));
            }

            if (relocation.targetAddress > std::numeric_limits<uint32_t>::max())
            {
                return reportError(context, phase, std::format("relocation #{} stores out-of-range data-segment offset {}", relocationIndex, relocation.targetAddress));
            }
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::CallLocal:
                if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress)
                    return reportError(context, phase, std::format("call-local instruction uses relocation kind {}", static_cast<uint32_t>(relocation.kind)));
                break;

            case MicroInstrOpcode::CallExtern:
                if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress)
                    return reportError(context, phase, std::format("call-extern instruction uses relocation kind {}", static_cast<uint32_t>(relocation.kind)));
                break;

            case MicroInstrOpcode::LoadRegPtrReloc:
                break;

            default:
                return reportError(context, phase, std::format("relocation #{} points to non-relocatable opcode {}", relocationIndex, static_cast<uint32_t>(inst.op)));
        }

        return Result::Continue;
    }

    Result verifyForbiddenRegisterMap(const MicroPassContext& context, std::string_view phase)
    {
        if (!context.builder)
            return Result::Continue;

        std::vector<const std::pair<const MicroReg, SmallVector<MicroReg>>*> entries;
        entries.reserve(context.builder->virtualRegForbiddenPhysRegs().size());
        for (const auto& entry : context.builder->virtualRegForbiddenPhysRegs())
            entries.push_back(&entry);

        std::ranges::sort(entries, [](const auto* lhs, const auto* rhs) { return lhs->first.packed < rhs->first.packed; });

        for (const auto* entry : entries)
        {
            const MicroReg virtualReg = entry->first;
            if (!virtualReg.isVirtual())
            {
                return reportError(context, phase, std::format("forbidden-register map uses non-virtual key {}", virtualReg.packed));
            }

            std::vector<uint32_t> regs;
            regs.reserve(entry->second.size());
            for (const MicroReg reg : entry->second)
            {
                if (!isValidAnyRegister(reg) || reg.isVirtual() || reg.isInstructionPointer() || reg.isNoBase())
                {
                    return reportError(context, phase, std::format("forbidden-register map for {} contains invalid concrete register {}", virtualReg.packed, reg.packed));
                }

                regs.push_back(reg.packed);
            }

            std::ranges::sort(regs);
            if (std::ranges::adjacent_find(regs) != regs.end())
            {
                return reportError(context, phase, std::format("forbidden-register map for {} contains duplicate concrete registers", virtualReg.packed));
            }
        }

        return Result::Continue;
    }
}

bool MicroVerify::isEnabled(const MicroPassContext& context)
{
#if SWC_DEV_MODE
    return context.microVerify;
#else
    (void) context;
    return false;
#endif
}

Result MicroVerify::reportError(const MicroPassContext& context, std::string_view phase, std::string_view message)
{
    if (shouldLogVerifyError(context))
        Logger::print(*context.taskContext, std::format("[micro-verify] {}: {}\n", phase, message));
    return Result::Error;
}

uint64_t MicroVerify::computeStructuralHash(const MicroPassContext& context)
{
    if (!isEnabled(context))
        return 0;

    if (!context.instructions || !context.operands)
        return 0;

    uint64_t hash = K_HASH_OFFSET_BASIS;

    std::unordered_map<uint32_t, uint32_t> instructionOrdinalByRef;
    instructionOrdinalByRef.reserve(context.instructions->count());

    uint32_t instructionOrdinal = 0;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        instructionOrdinalByRef[it.current.get()] = instructionOrdinal++;
        const MicroInstr& inst                    = *it;

        mixHash(hash, static_cast<uint8_t>(inst.op));
        mixHash(hash, inst.numOperands);
        mixHash(hash, inst.debugNoStep ? 1 : 0);
        mixHash(hash, inst.sourceCodeRef.srcViewRef.isValid() ? inst.sourceCodeRef.srcViewRef.get() : K_HASH_INVALID);
        mixHash(hash, inst.sourceCodeRef.tokRef.isValid() ? inst.sourceCodeRef.tokRef.get() : K_HASH_INVALID);

        if (!inst.numOperands)
        {
            mixHash(hash, 0);
            continue;
        }

        const bool hasValidOperandStorage = inst.opsRef.isValid() && inst.opsRef.get() + inst.numOperands <= context.operands->count();
        mixHash(hash, hasValidOperandStorage ? 1 : 0);
        if (!hasValidOperandStorage)
        {
            mixHash(hash, inst.opsRef.isValid() ? inst.opsRef.get() : K_HASH_INVALID);
            continue;
        }

        const MicroInstrOperand* ops = context.operands->ptr(inst.opsRef);
        for (uint32_t operandIndex = 0; operandIndex < inst.numOperands; ++operandIndex)
        {
            mixHash(hash, ops[operandIndex].valueU64);
            mixHash(hash, ops[operandIndex].valueInt.hash());
        }
    }

    if (context.builder)
    {
        const auto& relocations = context.builder->codeRelocations();
        mixHash(hash, relocations.size());
        for (const auto& relocation : relocations)
        {
            mixHash(hash, static_cast<uint8_t>(relocation.kind));
            mixHash(hash, relocation.targetAddress);
            mixHash(hash, relocation.constantRef.isValid() ? relocation.constantRef.get() : K_HASH_INVALID);
            mixHash(hash, relocation.targetSymbol ? reinterpret_cast<uintptr_t>(relocation.targetSymbol) : 0);

            if (relocation.instructionRef.isInvalid())
            {
                mixHash(hash, K_HASH_INVALID);
            }
            else
            {
                const auto found = instructionOrdinalByRef.find(relocation.instructionRef.get());
                mixHash(hash, found == instructionOrdinalByRef.end() ? K_HASH_INVALID : found->second);
            }
        }

        std::vector<const std::pair<const MicroReg, SmallVector<MicroReg>>*> entries;
        entries.reserve(context.builder->virtualRegForbiddenPhysRegs().size());
        for (const auto& entry : context.builder->virtualRegForbiddenPhysRegs())
            entries.push_back(&entry);

        std::ranges::sort(entries, [](const auto* lhs, const auto* rhs) { return lhs->first.packed < rhs->first.packed; });
        mixHash(hash, entries.size());
        for (const auto* entry : entries)
        {
            mixHash(hash, entry->first.packed);

            std::vector<uint32_t> regs;
            regs.reserve(entry->second.size());
            for (const MicroReg reg : entry->second)
                regs.push_back(reg.packed);

            std::ranges::sort(regs);
            mixHash(hash, regs.size());
            for (const uint32_t regPacked : regs)
                mixHash(hash, regPacked);
        }
    }

    return hash;
}

Result MicroVerify::verify(const MicroPassContext& context, std::string_view phase)
{
    if (!isEnabled(context))
        return Result::Continue;

    if (!context.instructions)
        return reportError(context, phase, "missing instruction storage");
    if (!context.operands)
        return reportError(context, phase, "missing operand storage");

    uint32_t                             iteratedInstructionCount = 0;
    std::unordered_set<uint32_t>         definedLabels;
    std::vector<uint32_t>                jumpTargets;
    std::unordered_set<uint32_t>         relocationExpectedRefs;
    std::unordered_map<uint32_t, size_t> relocationCountByRef;

    definedLabels.reserve(context.instructions->count());
    jumpTargets.reserve(context.instructions->count() / 2 + 1);

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        const MicroInstrRef instructionRef = it.current;
        const MicroInstr&   inst           = *it;
        const uint32_t      instructionIdx = iteratedInstructionCount++;

        const MicroInstrOperand* ops = nullptr;
        if (inst.numOperands == 0)
        {
            if (inst.opsRef.isValid())
            {
                return reportError(context, phase, std::format("instruction #{} (ref={}) has zero operands but a valid operand ref {}", instructionIdx, instructionRef.get(), inst.opsRef.get()));
            }
        }
        else
        {
            if (inst.opsRef.isInvalid())
            {
                return reportError(context, phase, std::format("instruction #{} (ref={}) has {} operands but an invalid operand ref", instructionIdx, instructionRef.get(), inst.numOperands));
            }

            const uint64_t operandEnd = static_cast<uint64_t>(inst.opsRef.get()) + inst.numOperands;
            if (operandEnd > context.operands->count())
            {
                return reportError(context, phase, std::format("instruction #{} (ref={}) references operands [{}..{}) outside storage size {}", instructionIdx, instructionRef.get(), inst.opsRef.get(), operandEnd, context.operands->count()));
            }

            ops = context.operands->ptr(inst.opsRef);
            if (!ops)
                return reportError(context, phase, std::format("instruction #{} (ref={}) cannot resolve operand storage", instructionIdx, instructionRef.get()));
        }

        SWC_RESULT(verifyInstructionShape(context, phase, instructionIdx, instructionRef, inst, ops));
        if (ops)
            SWC_RESULT(verifyInstructionRegisters(context, phase, instructionIdx, inst, ops));

        if (inst.op == MicroInstrOpcode::Label)
        {
            const uint32_t label = static_cast<uint32_t>(ops[0].valueU64);
            if (!definedLabels.insert(label).second)
            {
                return reportError(context, phase, std::format("duplicate label definition for id {}", label));
            }
        }
        else if (inst.op == MicroInstrOpcode::JumpCond)
        {
            jumpTargets.push_back(static_cast<uint32_t>(ops[2].valueU64));
        }

        if (expectsRelocation(inst.op))
            relocationExpectedRefs.insert(instructionRef.get());
    }

    if (iteratedInstructionCount != context.instructions->count())
    {
        return reportError(context, phase, std::format("instruction count mismatch: iterated {} entries, storage reports {}", iteratedInstructionCount, context.instructions->count()));
    }

    for (const uint32_t label : jumpTargets)
    {
        if (!definedLabels.contains(label))
            return reportError(context, phase, std::format("jump targets undefined label {}", label));
    }

    if (context.builder)
    {
        const auto& relocations = context.builder->codeRelocations();
        for (size_t relocationIdx = 0; relocationIdx < relocations.size(); ++relocationIdx)
        {
            const MicroRelocation& relocation = relocations[relocationIdx];
            if (relocation.instructionRef.isInvalid())
            {
                return reportError(context, phase, std::format("relocation #{} has an invalid instruction ref", relocationIdx));
            }

            const MicroInstr* inst = context.instructions->ptr(relocation.instructionRef);
            if (!inst)
            {
                return reportError(context, phase, std::format("relocation #{} points to dead or missing instruction ref {}", relocationIdx, relocation.instructionRef.get()));
            }

            SWC_RESULT(verifyRelocation(context, phase, static_cast<uint32_t>(relocationIdx), relocation, *inst));
            relocationCountByRef[relocation.instructionRef.get()]++;
        }

        for (const uint32_t instructionRefValue : relocationExpectedRefs)
        {
            const auto found = relocationCountByRef.find(instructionRefValue);
            const auto count = found == relocationCountByRef.end() ? 0ull : found->second;
            if (count != 1)
            {
                return reportError(context, phase, std::format("instruction ref {} expects exactly one relocation, found {}", instructionRefValue, count));
            }
        }

        SWC_RESULT(verifyForbiddenRegisterMap(context, phase));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
