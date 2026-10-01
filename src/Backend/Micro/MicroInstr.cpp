#include "pch.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

MicroOpBits MicroInstr::packedFloatInputBits(const MicroInstrOperand* operands) const
{
    switch (op)
    {
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::OpBinaryRegRegReg:
        {
            const MicroOp operation = operands[info(op).microOpIndex].microOp;
            // Every low-half interleave consumes eight bytes from each input,
            // regardless of the element width; only its result needs 16 bytes.
            if (operation >= MicroOp::VecUnpackLo8 && operation <= MicroOp::VecUnpackLo64)
                return MicroOpBits::B64;
            break;
        }
        case MicroInstrOpcode::VecShuffleRegRegImm:
            // The high bit of each two-bit selector chooses an upper dword.
            if (!(operands[3].valueU64 & 0xAA))
                return MicroOpBits::B64;
            break;
        default:
            break;
    }
    return MicroOpBits::B128;
}

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
    if (reg.isValid() && !reg.isNoBase())
    {
        uses.push_back(reg);
        defs.push_back(reg);
    }
}

namespace
{
    constexpr uint8_t K_CALL_ARG_MASK_ALL = 0xFF;

    void collectRegUseDefFromModes(MicroInstrUseDef& info, const MicroInstrOperand* ops, const std::array<MicroInstrRegMode, 3>& modes)
    {
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

    uint8_t resolveCallArgMask(const MicroInstr& inst, const MicroInstrOperand* ops, const uint8_t maskOperandIndex)
    {
        if (!ops || inst.numOperands <= maskOperandIndex)
            return K_CALL_ARG_MASK_ALL;

        return static_cast<uint8_t>(ops[maskOperandIndex].valueU32);
    }

    void addMaskedCallArgRegs(MicroInstrUseDef& useDef, const MicroRegSpan regs, const uint8_t mask, size_t defaultCount)
    {
        if (mask == K_CALL_ARG_MASK_ALL)
        {
            const size_t count = std::min(regs.size(), defaultCount);
            for (size_t i = 0; i < count; ++i)
                useDef.addUse(regs[i]);
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

MicroInstrUseDef MicroInstr::collectUseDef(const MicroOperandStorage& operands, const Encoder* encoder) const
{
    MicroInstrUseDef useDef;
    collectUseDef(useDef, operands, encoder);
    return useDef;
}

CallFloatArgs MicroInstr::callFloatArgs(const MicroOperandStorage& operands) const
{
    SWC_ASSERT(info(op).flags.has(MicroInstrFlagsE::IsCallInstruction));
    const uint32_t index = info(op).callConvIndex + 2;
    CallFloatArgs  result(K_CALL_ARG_MASK_ALL);
    if (numOperands > index)
        result.widths = static_cast<uint16_t>(ops(operands)[index].valueU32);
    return result;
}

void MicroInstr::collectUseDef(MicroInstrUseDef& useDef, const MicroOperandStorage& operands, const Encoder* encoder) const
{
    const MicroInstrDef&     opcodeInfo = info(op);
    const MicroInstrOperand* ops        = this->ops(operands);

    useDef.uses.clear();
    useDef.defs.clear();
    useDef.isCall   = false;
    useDef.callConv = CallConvKind::Swag;
    if (opcodeInfo.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        useDef.isCall   = true;
        useDef.callConv = ops[opcodeInfo.callConvIndex].callConv;

        // Call instructions consume ABI argument registers implicitly. Keep them live so
        // register allocation and later rewrites cannot reuse them before the call.
        const CallConv& callConv        = CallConv::get(useDef.callConv);
        const size_t    defaultArgCount = callConv.numArgRegisterSlots();
        // Every call stores its integer and float masks immediately after the convention.
        addMaskedCallArgRegs(useDef, callConv.intArgRegs, resolveCallArgMask(*this, ops, opcodeInfo.callConvIndex + 1), defaultArgCount);
        const CallFloatArgs floatArgs = callFloatArgs(operands);
        for (uint32_t index = 0; index < std::min<size_t>(callConv.floatArgRegs.size(), 8); ++index)
        {
            if (floatArgs.laneMask(index))
                useDef.addUse(callConv.floatArgRegs[index]);
        }
        for (const MicroReg reg : callConv.intTransientRegs)
            useDef.addDef(reg);
        for (const MicroReg reg : callConv.floatTransientRegs)
            useDef.addDef(reg);
    }

    if (ops)
    {
        const auto modes = opcodeInfo.resolvedRegModes(ops);
        collectRegUseDefFromModes(useDef, ops, modes);
    }

    if (encoder && opcodeInfo.flags.has(MicroInstrFlagsE::EncoderRegUseDef))
        encoder->updateRegUseDef(*this, ops, useDef);
}

SWC_END_NAMESPACE();
