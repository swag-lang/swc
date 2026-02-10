#include "pch.h"
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"

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
    std::array<MicroInstrRegMode, 3> resolveRegModes(const MicroInstrOpcodeInfo& info, const MicroInstrOperand* ops)
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

    void addOperand(SmallVector<MicroInstrRegOperandRef, 8>& out, MicroReg* reg, bool use, bool def)
    {
        if (!reg || !reg->isValid() || reg->isNoBase())
            return;
        out.push_back({reg, use, def});
    }

    void collectRegOperandsFromModes(MicroInstrOperand* ops, const std::array<MicroInstrRegMode, 3>& modes, SmallVector<MicroInstrRegOperandRef, 8>& out)
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

MicroInstrUseDef MicroInstr::collectUseDef(const MicroInstr& inst, const PagedStore& store, const Encoder* encoder)
{
    MicroInstrUseDef info;

    const auto& opcodeInfo = MicroInstr::info(inst.op);
    const auto* ops        = inst.ops(store);

    if (opcodeInfo.isCall)
    {
        info.isCall   = true;
        info.callConv = ops[opcodeInfo.callConvIndex].callConv;
    }

    const auto modes = resolveRegModes(opcodeInfo, ops);
    collectRegUseDefFromModes(info, ops, modes);

    if (encoder)
        encoder->updateRegUseDef(inst, ops, info);

    return info;
}

void MicroInstr::collectRegOperands(const MicroInstr& inst, PagedStore& store, SmallVector<MicroInstrRegOperandRef, 8>& out, const Encoder* encoder)
{
    const auto& opcodeInfo = MicroInstr::info(inst.op);
    auto*       ops        = inst.ops(store);
    const auto  modes      = resolveRegModes(opcodeInfo, ops);
    collectRegOperandsFromModes(ops, modes, out);
    (void) encoder;
}

SWC_END_NAMESPACE();
