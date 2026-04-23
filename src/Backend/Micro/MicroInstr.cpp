#include "pch.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

void MicroInstrUseDef::addUse(MicroReg reg)
{
    if (reg.isValid() && !reg.isNoBase())
        uses.push_back(reg);
}

void MicroInstrUseDef::addDef(MicroReg reg)
{
    if (reg.isValid() && !reg.isNoBase())
        defs.push_back(reg);
}

void MicroInstrUseDef::addUseDef(MicroReg reg)
{
    addUse(reg);
    addDef(reg);
}

namespace
{
    constexpr uint8_t K_CALL_ARG_MASK_ALL = 0xFF;

    std::array<MicroInstrRegMode, 3> resolveRegModes(const MicroInstrDef& info, const MicroInstrOperand* ops)
    {
        auto modes = info.regModes;

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

    void collectRegUseDefFromModes(MicroInstrUseDef& info, const MicroInstrOperand* ops, const std::array<MicroInstrRegMode, 3>& modes)
    {
        if (!ops)
            return;

        for (size_t i = 0; i < modes.size(); ++i)
        {
            switch (modes[i])
            {
                case MicroInstrRegMode::None:
                    break;
                case MicroInstrRegMode::Use:
                    info.addUse(ops[i].reg);
                    break;
                case MicroInstrRegMode::Def:
                    info.addDef(ops[i].reg);
                    break;
                case MicroInstrRegMode::UseDef:
                    info.addUseDef(ops[i].reg);
                    break;
            }
        }
    }

    void addOperand(SmallVector<MicroInstrRegOperandRef>& out, MicroReg* reg, bool use, bool def)
    {
        if (!reg || !reg->isValid() || reg->isNoBase())
            return;
        out.push_back({reg, use, def});
    }

    void collectRegOperandsFromModes(SmallVector<MicroInstrRegOperandRef>& out, MicroInstrOperand* ops, const std::array<MicroInstrRegMode, 3>& modes)
    {
        if (!ops)
            return;

        for (size_t i = 0; i < modes.size(); ++i)
        {
            switch (modes[i])
            {
                case MicroInstrRegMode::None:
                    break;
                case MicroInstrRegMode::Use:
                    addOperand(out, &ops[i].reg, true, false);
                    break;
                case MicroInstrRegMode::Def:
                    addOperand(out, &ops[i].reg, false, true);
                    break;
                case MicroInstrRegMode::UseDef:
                    addOperand(out, &ops[i].reg, true, true);
                    break;
            }
        }
    }

    uint8_t resolveCallArgMask(const MicroInstr& inst, const MicroInstrOperand* ops, const bool floatMask)
    {
        uint8_t maskOperandIndex = 0xFF;
        switch (inst.op)
        {
            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                maskOperandIndex = floatMask ? 2 : 1;
                break;
            case MicroInstrOpcode::CallIndirect:
                maskOperandIndex = floatMask ? 3 : 2;
                break;
            default:
                return K_CALL_ARG_MASK_ALL;
        }

        if (!ops || inst.numOperands <= maskOperandIndex)
            return K_CALL_ARG_MASK_ALL;

        return static_cast<uint8_t>(ops[maskOperandIndex].valueU32);
    }

    size_t countMaskedCallArgRegs(const MicroRegSpan regs, const uint8_t mask)
    {
        if (mask == K_CALL_ARG_MASK_ALL)
            return regs.size();

        const auto maskableCount = std::min<size_t>(regs.size(), 8);
        size_t     count         = 0;
        for (size_t i = 0; i < maskableCount; ++i)
        {
            if (mask & static_cast<uint8_t>(1u << i))
                ++count;
        }

        return count;
    }

    void reserveCallUseDefCapacity(MicroInstrUseDef& useDef, const MicroInstr& inst, const MicroInstrOperand* ops, const CallConv& callConv)
    {
        const uint8_t intMask      = resolveCallArgMask(inst, ops, false);
        const uint8_t floatMask    = resolveCallArgMask(inst, ops, true);
        const size_t  implicitUses = countMaskedCallArgRegs(callConv.intArgRegs, intMask) +
                                     countMaskedCallArgRegs(callConv.floatArgRegs, floatMask);
        const size_t  explicitUses = inst.op == MicroInstrOpcode::CallIndirect ? 1u : 0u;
        const size_t  implicitDefs = callConv.intTransientRegs.size() + callConv.floatTransientRegs.size();

        useDef.uses.reserve(implicitUses + explicitUses);
        useDef.defs.reserve(implicitDefs);
    }

    void addMaskedCallArgRegs(MicroInstrUseDef& useDef, const MicroRegSpan regs, const uint8_t mask)
    {
        if (mask == K_CALL_ARG_MASK_ALL)
        {
            for (const MicroReg reg : regs)
                useDef.addUse(reg);
            return;
        }

        const auto maskableCount = std::min<size_t>(regs.size(), 8);
        for (size_t i = 0; i < maskableCount; ++i)
        {
            if (mask & static_cast<uint8_t>(1u << i))
                useDef.addUse(regs[i]);
        }
    }
}

MicroInstrOperand* MicroInstr::ops(MicroOperandStorage& operands) const
{
    if (!numOperands)
        return nullptr;
    return operands.ptr(opsRef);
}

const MicroInstrOperand* MicroInstr::ops(const MicroOperandStorage& operands) const
{
    if (!numOperands)
        return nullptr;
    return operands.ptr(opsRef);
}

MicroInstrUseDef MicroInstr::collectUseDef(const MicroOperandStorage& operands, const Encoder* encoder) const
{
    const MicroInstrDef&     opcodeInfo = info(op);
    const MicroInstrOperand* ops        = this->ops(operands);
    const auto               modes      = resolveRegModes(opcodeInfo, ops);

    MicroInstrUseDef useDef;
    if (opcodeInfo.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        useDef.isCall   = true;
        useDef.callConv = ops[opcodeInfo.callConvIndex].callConv;

        // Call instructions consume ABI argument registers implicitly. Keep them live so
        // register allocation and later rewrites cannot reuse them before the call.
        const CallConv& callConv = CallConv::get(useDef.callConv);
        reserveCallUseDefCapacity(useDef, *this, ops, callConv);
        addMaskedCallArgRegs(useDef, callConv.intArgRegs, resolveCallArgMask(*this, ops, false));
        addMaskedCallArgRegs(useDef, callConv.floatArgRegs, resolveCallArgMask(*this, ops, true));
        for (const MicroReg reg : callConv.intTransientRegs)
            useDef.addDef(reg);
        for (const MicroReg reg : callConv.floatTransientRegs)
            useDef.addDef(reg);
    }

    collectRegUseDefFromModes(useDef, ops, modes);

    if (encoder)
        encoder->updateRegUseDef(*this, ops, useDef);

    return useDef;
}

void MicroInstr::collectRegOperands(MicroOperandStorage& operands, SmallVector<MicroInstrRegOperandRef>& out, const Encoder*) const
{
    const MicroInstrDef& opcodeInfo = info(op);
    MicroInstrOperand*   ops        = this->ops(operands);
    const auto           modes      = resolveRegModes(opcodeInfo, ops);
    collectRegOperandsFromModes(out, ops, modes);
}

SWC_END_NAMESPACE();
