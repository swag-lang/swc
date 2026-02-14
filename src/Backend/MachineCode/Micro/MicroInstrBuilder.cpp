#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string toLowerSnake(std::string_view src)
    {
        std::string out;
        out.reserve(src.size() * 2);
        for (size_t i = 0; i < src.size(); ++i)
        {
            const char c = src[i];
            if (c >= 'A' && c <= 'Z')
            {
                if (i && out.back() != '_')
                    out.push_back('_');
                out.push_back(static_cast<char>(c - 'A' + 'a'));
            }
            else
            {
                out.push_back(c);
            }
        }

        return out;
    }

    std::string_view opcodeEnumName(MicroInstrOpcode op)
    {
        switch (op)
        {
#define SWC_MICRO_INSTR_DEF(__enum, ...) case MicroInstrOpcode::__enum: return #__enum;
#include "Backend/MachineCode/Micro/MicroInstr.Def.inc"
#undef SWC_MICRO_INSTR_DEF
            default:
                return "Unknown";
        }
    }

    std::string opcodeName(MicroInstrOpcode op)
    {
        return toLowerSnake(opcodeEnumName(op));
    }

    std::string_view opBitsName(MicroOpBits opBits)
    {
        switch (opBits)
        {
            case MicroOpBits::Zero:
                return "0";
            case MicroOpBits::B8:
                return "8";
            case MicroOpBits::B16:
                return "16";
            case MicroOpBits::B32:
                return "32";
            case MicroOpBits::B64:
                return "64";
            case MicroOpBits::B128:
                return "128";
            default:
                return "?";
        }
    }

    std::string_view microOpName(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
                return "add";
            case MicroOp::And:
                return "and";
            case MicroOp::BitScanForward:
                return "bsf";
            case MicroOp::BitScanReverse:
                return "bsr";
            case MicroOp::BitwiseNot:
                return "not";
            case MicroOp::ByteSwap:
                return "bswap";
            case MicroOp::CompareExchange:
                return "cmpxchg";
            case MicroOp::ConvertFloatToFloat:
                return "cvtf2f";
            case MicroOp::ConvertFloatToInt:
                return "cvtf2i";
            case MicroOp::ConvertIntToFloat:
                return "cvti2f";
            case MicroOp::ConvertUIntToFloat64:
                return "cvtu2f64";
            case MicroOp::DivideSigned:
                return "idiv";
            case MicroOp::DivideUnsigned:
                return "div";
            case MicroOp::Exchange:
                return "xchg";
            case MicroOp::FloatAdd:
                return "fadd";
            case MicroOp::FloatAnd:
                return "fand";
            case MicroOp::FloatDivide:
                return "fdiv";
            case MicroOp::FloatMax:
                return "fmax";
            case MicroOp::FloatMin:
                return "fmin";
            case MicroOp::FloatMultiply:
                return "fmul";
            case MicroOp::FloatSqrt:
                return "fsqrt";
            case MicroOp::FloatSubtract:
                return "fsub";
            case MicroOp::FloatXor:
                return "fxor";
            case MicroOp::LoadEffectiveAddress:
                return "lea";
            case MicroOp::ModuloSigned:
                return "imod";
            case MicroOp::ModuloUnsigned:
                return "mod";
            case MicroOp::Move:
                return "mov";
            case MicroOp::MoveSignExtend:
                return "movsx";
            case MicroOp::MultiplyAdd:
                return "madd";
            case MicroOp::MultiplySigned:
                return "imul";
            case MicroOp::MultiplyUnsigned:
                return "mul";
            case MicroOp::Negate:
                return "neg";
            case MicroOp::Or:
                return "or";
            case MicroOp::PopCount:
                return "popcnt";
            case MicroOp::RotateLeft:
                return "rol";
            case MicroOp::RotateRight:
                return "ror";
            case MicroOp::ShiftArithmeticLeft:
                return "sal";
            case MicroOp::ShiftArithmeticRight:
                return "sar";
            case MicroOp::ShiftLeft:
                return "shl";
            case MicroOp::ShiftRight:
                return "shr";
            case MicroOp::Subtract:
                return "sub";
            case MicroOp::Xor:
                return "xor";
            default:
                return "?";
        }
    }

    std::string_view condName(MicroCond cond)
    {
        switch (cond)
        {
            case MicroCond::Above:
                return "a";
            case MicroCond::AboveOrEqual:
                return "ae";
            case MicroCond::Below:
                return "b";
            case MicroCond::BelowOrEqual:
                return "be";
            case MicroCond::Equal:
                return "e";
            case MicroCond::EvenParity:
                return "pe";
            case MicroCond::Greater:
                return "g";
            case MicroCond::GreaterOrEqual:
                return "ge";
            case MicroCond::Less:
                return "l";
            case MicroCond::LessOrEqual:
                return "le";
            case MicroCond::NotAbove:
                return "na";
            case MicroCond::NotEqual:
                return "ne";
            case MicroCond::NotEvenParity:
                return "po";
            case MicroCond::NotParity:
                return "np";
            case MicroCond::Overflow:
                return "o";
            case MicroCond::Parity:
                return "p";
            default:
                return "?";
        }
    }

    std::string_view condJumpName(MicroCondJump cond)
    {
        switch (cond)
        {
            case MicroCondJump::Above:
                return "a";
            case MicroCondJump::AboveOrEqual:
                return "ae";
            case MicroCondJump::Below:
                return "b";
            case MicroCondJump::BelowOrEqual:
                return "be";
            case MicroCondJump::Greater:
                return "g";
            case MicroCondJump::GreaterOrEqual:
                return "ge";
            case MicroCondJump::Less:
                return "l";
            case MicroCondJump::LessOrEqual:
                return "le";
            case MicroCondJump::NotOverflow:
                return "no";
            case MicroCondJump::NotParity:
                return "np";
            case MicroCondJump::NotZero:
                return "nz";
            case MicroCondJump::Parity:
                return "p";
            case MicroCondJump::Sign:
                return "s";
            case MicroCondJump::Unconditional:
                return "jmp";
            case MicroCondJump::Zero:
                return "z";
            default:
                return "?";
        }
    }

    std::string_view callConvName(CallConvKind callConv)
    {
        switch (callConv)
        {
            case CallConvKind::C:
                return "c";
            case CallConvKind::WindowsX64:
                return "win64";
            case CallConvKind::Host:
                return "host";
            default:
                return "?";
        }
    }

    std::string regName(MicroReg reg)
    {
        if (!reg.isValid())
            return "inv";

        if (reg.isInstructionPointer())
            return "rip";
        if (reg.isNoBase())
            return "nobase";

        if (reg.isInt())
        {
            static constexpr std::array K_INT_REG_NAMES = {
                "rax",
                "rbx",
                "rcx",
                "rdx",
                "rsp",
                "rbp",
                "rsi",
                "rdi",
                "r8",
                "r9",
                "r10",
                "r11",
                "r12",
                "r13",
                "r14",
                "r15",
            };

            if (reg.index() < K_INT_REG_NAMES.size())
                return std::string(K_INT_REG_NAMES[reg.index()]);

            return std::format("r{}", reg.index());
        }

        if (reg.isFloat())
            return std::format("xmm{}", reg.index());

        if (reg.isVirtualInt())
            return std::format("v{}", reg.index());

        if (reg.isVirtualFloat())
            return std::format("vf{}", reg.index());

        return std::format("reg#{}", reg.packed);
    }

    std::string hexU64(uint64_t value)
    {
        return std::format("0x{:X}", value);
    }

    std::string memBaseOffset(MicroReg baseReg, uint64_t offset)
    {
        if (offset == 0)
            return std::format("[{}]", regName(baseReg));
        return std::format("[{} + {}]", regName(baseReg), hexU64(offset));
    }

    std::string memAmc(MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue)
    {
        std::string out = "[";
        if (!baseReg.isNoBase())
            out += regName(baseReg);

        if (!mulReg.isNoBase())
        {
            if (!baseReg.isNoBase())
                out += " + ";
            out += regName(mulReg);
            if (mulValue != 1)
                out += std::format(" * {}", hexU64(mulValue));
        }

        if (addValue != 0)
        {
            if (!baseReg.isNoBase() || !mulReg.isNoBase())
                out += " + ";
            out += hexU64(addValue);
        }

        if (baseReg.isNoBase() && mulReg.isNoBase() && addValue == 0)
            out += "0";

        out += "]";
        return out;
    }

    void appendColored(std::string& out, const TaskContext& ctx, bool colorize, LogColor color, std::string_view value)
    {
        if (colorize)
            out += LogColorHelper::toAnsi(ctx, color);
        out += value;
        if (colorize)
            out += LogColorHelper::toAnsi(ctx, LogColor::Reset);
    }

    void appendInstFlags(std::string& out, const TaskContext& ctx, bool colorize, EncodeFlags flags)
    {
        if (flags.none())
            return;

        out += "  ; ";
        appendColored(out, ctx, colorize, LogColor::Dim, "flags=");

        bool first = true;
        if (flags.has(EncodeFlagsE::Overflow))
        {
            out += first ? "" : "|";
            out += "overflow";
            first = false;
        }

        if (flags.has(EncodeFlagsE::Lock))
        {
            out += first ? "" : "|";
            out += "lock";
            first = false;
        }

        if (flags.has(EncodeFlagsE::B64))
        {
            out += first ? "" : "|";
            out += "b64";
            first = false;
        }

        if (flags.has(EncodeFlagsE::CanEncode))
        {
            out += first ? "" : "|";
            out += "can_encode";
        }
    }
}

MicroInstr& MicroInstrBuilder::addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands)
{
    auto [_, inst]    = instructions_.emplaceUninit();
    inst->op          = op;
    inst->emitFlags   = emitFlags;
    inst->numOperands = numOperands;
    if (numOperands)
    {
        auto [opsRef, ops] = operands_.emplaceUninitArray(numOperands);
        inst->opsRef       = opsRef;
        for (uint8_t idx = 0; idx < numOperands; ++idx)
            new (ops + idx) MicroInstrOperand();
    }
    else
    {
        inst->opsRef = std::numeric_limits<Ref>::max();
    }
    return *inst;
}

EncodeResult MicroInstrBuilder::encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SymbolRelocAddr, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].valueU32  = symbolIndex;
    ops[2].valueU32  = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SymbolRelocValue, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU32  = symbolIndex;
    ops[3].valueU32  = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePush(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Push, emitFlags, 1);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePop(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Pop, emitFlags, 1);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeNop(EncodeFlags emitFlags)
{
    addInstruction(MicroInstrOpcode::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeRet(EncodeFlags emitFlags)
{
    addInstruction(MicroInstrOpcode::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallLocal, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].name      = symbolName;
    ops[1].callConv  = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallExtern, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].name      = symbolName;
    ops[1].callConv  = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallIndirect, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].callConv  = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpTable, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = tableReg;
    ops[1].reg       = offsetReg;
    ops[2].valueI32  = currentIp;
    ops[3].valueU32  = offsetTable;
    ops[4].valueU32  = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const uint32_t instructionIndex = instructions_.count();
    jump.offsetStart                = static_cast<uint64_t>(instructionIndex) * sizeof(MicroInstr);
    jump.opBits                     = opBits;
    const auto& inst                = addInstruction(MicroInstrOpcode::JumpCond, emitFlags, 2);
    auto*       ops                 = inst.ops(operands_.store());
    ops[0].jumpType                 = jumpType;
    ops[1].opBits                   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].valueU64  = jump.offsetStart;
    ops[1].valueU64  = offsetDestination;
    ops[2].valueU64  = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].valueU64  = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpReg, emitFlags, 1);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegImm, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAddrRegMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcRegMem, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regBase;
    ops[2].reg       = regMul;
    ops[3].opBits    = opBitsDst;
    ops[4].opBits    = opBitsSrc;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcMemReg, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regBase;
    ops[1].reg       = regMul;
    ops[2].reg       = regSrc;
    ops[3].opBits    = opBitsBaseMul;
    ops[4].opBits    = opBitsSrc;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcMemImm, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regBase;
    ops[1].reg       = regMul;
    ops[3].opBits    = opBitsBaseMul;
    ops[4].opBits    = opBitsValue;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    ops[7].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAddrAmcRegMem, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regBase;
    ops[2].reg       = regMul;
    ops[3].opBits    = opBitsDst;
    ops[4].opBits    = opBitsValue;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadMemReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadMemImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = memOffset;
    ops[3].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpRegReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg0;
    ops[1].reg       = reg1;
    ops[2].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpMemReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpMemImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = memOffset;
    ops[3].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpRegImm, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SetCondReg, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].cpuCond   = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadCondRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].cpuCond   = setType;
    ops[3].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::ClearReg, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpUnaryMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpUnaryReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryMemReg, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryMemImm, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = memOffset;
    ops[4].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpTernaryRegRegReg, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg0;
    ops[1].reg       = reg1;
    ops[2].reg       = reg2;
    ops[3].opBits    = opBits;
    ops[4].microOp   = op;
    return EncodeResult::Zero;
}

void MicroInstrBuilder::runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context)
{
    context.encoder      = encoder;
    context.instructions = &instructions_;
    context.operands     = &operands_;
    passes.run(context);
}

std::string MicroInstrBuilder::formatInstructions(bool colorize) const
{
    std::string out;
    auto&       storeOps = operands_.store();
    auto&       instructions = const_cast<PagedStoreTyped<MicroInstr>&>(instructions_);

    const uint32_t count = instructions_.count();
    out += std::format("micro-instructions: {}\n", count);

    uint32_t idx = 0;
    for (const auto& inst : instructions.view())
    {
        const auto* ops = inst.ops(storeOps);

        appendColored(out, ctx(), colorize, LogColor::Dim, std::format("{:04}", idx));
        out += "  ";
        appendColored(out, ctx(), colorize, LogColor::BrightCyan, std::format("{:<26}", opcodeName(inst.op)));

        switch (inst.op)
        {
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Enter:
            case MicroInstrOpcode::Leave:
            case MicroInstrOpcode::Ignore:
            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::Debug:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Ret:
                break;

            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
            case MicroInstrOpcode::JumpReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("sym#{}", ops[1].valueU32));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[2].valueU32));
                break;

            case MicroInstrOpcode::SymbolRelocValue:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("sym#{}", ops[2].valueU32));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[3].valueU32));
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                appendColored(out, ctx(), colorize, LogColor::White, ops[0].name.isValid() ? ctx().idMgr().get(ops[0].name).name : "<invalid-symbol>");
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::CallIndirect:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::JumpTable:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("ip={}", ops[2].valueI32));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("table={}", ops[3].valueU32));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("count={}", ops[4].valueU32));
                break;

            case MicroInstrOpcode::JumpCond:
                appendColored(out, ctx(), colorize, LogColor::Magenta, condJumpName(ops[0].jumpType));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::PatchJump:
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("from={}", ops[0].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("to={}", ops[1].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("imm={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::JumpCondImm:
                appendColored(out, ctx(), colorize, LogColor::Magenta, condJumpName(ops[0].jumpType));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, std::format("to={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadRegImm:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[1].reg, ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[1].reg, ops[4].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[2].opBits), opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[2].opBits), opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memAmc(ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, memAmc(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[2].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                appendColored(out, ctx(), colorize, LogColor::Yellow, memAmc(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[7].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAddrAmcRegMem:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memAmc(ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadMemReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadMemImm:
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[2].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CmpRegReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::CmpRegImm:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[2].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CmpMemReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::CmpMemImm:
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[2].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::SetCondReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, condName(ops[1].cpuCond));
                break;

            case MicroInstrOpcode::LoadCondRegReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, condName(ops[2].cpuCond));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::ClearReg:
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpUnaryMem:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpUnaryReg:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[1].reg, ops[4].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[4].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegImm:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryMemImm:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Green, hexU64(ops[4].valueU64));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
                appendColored(out, ctx(), colorize, LogColor::White, microOpName(ops[4].microOp));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[0].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[1].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Yellow, regName(ops[2].reg));
                out += ", ";
                appendColored(out, ctx(), colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
                appendColored(out, ctx(), colorize, LogColor::Dim, std::format("{} operand(s)", inst.numOperands));
                break;

            default:
                appendColored(out, ctx(), colorize, LogColor::Dim, std::format("{} operand(s)", inst.numOperands));
                break;
        }

        appendInstFlags(out, ctx(), colorize, inst.emitFlags);
        out += '\n';
        ++idx;
    }

    return out;
}

void MicroInstrBuilder::printInstructions(bool colorize) const
{
    Logger::print(ctx(), formatInstructions(colorize));
}

SWC_END_NAMESPACE();
