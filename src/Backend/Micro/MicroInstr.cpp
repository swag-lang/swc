#include "pch.h"
#include "Backend/Micro/MicroInstr.h"
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

    MicroInstrUseDef useDef;
    if (opcodeInfo.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        useDef.isCall   = true;
        useDef.callConv = ops[opcodeInfo.callConvIndex].callConv;
    }

    const auto modes = resolveRegModes(opcodeInfo, ops);
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
