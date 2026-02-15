#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrPrinter.h"
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string_view opcodeEnumName(MicroInstrOpcode op)
    {
        switch (op)
        {
#define SWC_MICRO_INSTR_DEF(__enum, ...) \
    case MicroInstrOpcode::__enum: return #__enum;
#include "Backend/MachineCode/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
            default:
                return "Unknown";
        }
    }

    std::string opcodeName(MicroInstrOpcode op)
    {
        return Utf8Helper::toLowerSnake(opcodeEnumName(op));
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

    std::string regName(MicroReg reg, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        if (!reg.isValid())
            return "inv";

        if (reg.isInstructionPointer())
            return regPrintMode == MicroInstrRegPrintMode::Virtual ? "ip" : "rip";
        if (reg.isNoBase())
            return "nobase";

        if (regPrintMode == MicroInstrRegPrintMode::Concrete && encoder)
        {
            if (reg.isInt() || reg.isFloat())
                return encoder->formatRegisterName(reg);
        }

        if (reg.isInt())
            return std::format("r{}", reg.index());

        if (reg.isFloat())
            return std::format("f{}", reg.index());

        if (reg.isVirtualInt())
            return std::format("%{}", reg.index());

        if (reg.isVirtualFloat())
            return std::format("%f{}", reg.index());

        return std::format("reg#{}", reg.packed);
    }

    bool hasVirtualRegisterToken(std::string_view value)
    {
        for (size_t i = 0; i < value.size(); ++i)
        {
            if (value[i] != '%')
                continue;

            size_t j = i + 1;
            if (j < value.size() && value[j] == 'f')
                ++j;

            if (j >= value.size() || !std::isdigit(static_cast<unsigned char>(value[j])))
                continue;

            while (j < value.size() && std::isdigit(static_cast<unsigned char>(value[j])))
                ++j;

            if (j == value.size())
                return true;
        }

        return false;
    }

    std::string hexU64(uint64_t value)
    {
        return std::format("0x{:X}", value);
    }

    void appendColored(std::string& out, const TaskContext& ctx, bool colorize, SyntaxColor color, std::string_view value)
    {
        SyntaxColor effectiveColor = color;
        if (color == SyntaxColor::Register && hasVirtualRegisterToken(value))
            effectiveColor = SyntaxColor::RegisterVirtual;

        if (colorize)
            out += SyntaxColorHelper::toAnsi(ctx, effectiveColor);
        out += value;
        if (colorize)
            out += SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default);
    }

    void appendRegister(std::string& out, const TaskContext& ctx, bool colorize, MicroReg reg, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        const auto color = reg.isVirtual() ? SyntaxColor::RegisterVirtual : SyntaxColor::Register;
        appendColored(out, ctx, colorize, color, regName(reg, regPrintMode, encoder));
    }

    void appendMemBaseOffset(std::string& out, const TaskContext& ctx, bool colorize, MicroReg baseReg, uint64_t offset, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        out += "[";
        appendRegister(out, ctx, colorize, baseReg, regPrintMode, encoder);
        if (offset != 0)
        {
            out += " + ";
            appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(offset));
        }
        out += "]";
    }

    void appendMemAmc(std::string& out, const TaskContext& ctx, bool colorize, MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        out += "[";
        if (!baseReg.isNoBase())
            appendRegister(out, ctx, colorize, baseReg, regPrintMode, encoder);

        if (!mulReg.isNoBase())
        {
            if (!baseReg.isNoBase())
                out += " + ";
            appendRegister(out, ctx, colorize, mulReg, regPrintMode, encoder);
            if (mulValue != 1)
            {
                out += " * ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(mulValue));
            }
        }

        if (addValue != 0)
        {
            if (!baseReg.isNoBase() || !mulReg.isNoBase())
                out += " + ";
            appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(addValue));
        }

        if (baseReg.isNoBase() && mulReg.isNoBase() && addValue == 0)
            appendColored(out, ctx, colorize, SyntaxColor::Number, "0");

        out += "]";
    }

    void appendInstFlags(std::string& out, const TaskContext& ctx, bool colorize, EncodeFlags flags)
    {
        if (flags.none())
            return;

        out += "  ; ";
        appendColored(out, ctx, colorize, SyntaxColor::Compiler, "flags=");

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

std::string MicroInstrPrinter::format(const TaskContext& ctx, const MicroInstrStorage& instructions, const MicroOperandStorage& operands, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize)
{
    std::string out;
    auto&       storeOps      = operands;
    auto&       instructionsV = const_cast<MicroInstrStorage&>(instructions);

    uint32_t idx = 0;
    for (const auto& inst : instructionsV.view())
    {
        const auto* ops = inst.numOperands ? inst.ops(storeOps) : nullptr;

        appendColored(out, ctx, colorize, SyntaxColor::InstructionIndex, std::format("{:04}", idx));
        out += "  ";
        appendColored(out, ctx, colorize, SyntaxColor::Function, std::format("{:>26}", opcodeName(inst.op)));
        out += " ";

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
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("sym#{}", ops[1].valueU32));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[2].valueU32));
                break;

            case MicroInstrOpcode::SymbolRelocValue:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("sym#{}", ops[2].valueU32));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[3].valueU32));
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                appendColored(out, ctx, colorize, SyntaxColor::Code, ops[0].name.isValid() ? ctx.idMgr().get(ops[0].name).name : "<invalid-symbol>");
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::CallIndirect:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::JumpTable:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("ip={}", ops[2].valueI32));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("table={}", ops[3].valueU32));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("count={}", ops[4].valueU32));
                break;

            case MicroInstrOpcode::JumpCond:
                appendColored(out, ctx, colorize, SyntaxColor::Type, condJumpName(ops[0].jumpType));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::PatchJump:
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("from={}", ops[0].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("to={}", ops[1].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("imm={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::JumpCondImm:
                appendColored(out, ctx, colorize, SyntaxColor::Type, condJumpName(ops[0].jumpType));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("to={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadRegImm:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendMemBaseOffset(out, ctx, colorize, ops[1].reg, ops[3].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendMemBaseOffset(out, ctx, colorize, ops[1].reg, ops[4].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(ops[2].opBits), opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(ops[2].opBits), opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendMemAmc(out, ctx, colorize, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                appendMemAmc(out, ctx, colorize, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[2].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                appendMemAmc(out, ctx, colorize, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[7].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAddrAmcRegMem:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendMemAmc(out, ctx, colorize, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadMemReg:
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[3].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadMemImm:
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[2].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CmpRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::CmpRegImm:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[2].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CmpMemReg:
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[3].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::CmpMemImm:
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[2].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::SetCondReg:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, condName(ops[1].cpuCond));
                break;

            case MicroInstrOpcode::LoadCondRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, condName(ops[2].cpuCond));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::ClearReg:
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpUnaryMem:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                out += ", ";
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[3].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpUnaryReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendMemBaseOffset(out, ctx, colorize, ops[1].reg, ops[4].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[3].microOp));
                out += ", ";
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[4].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegImm:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryMemImm:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                out += ", ";
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[3].valueU64, regPrintMode, encoder);
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[4].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[4].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Register, regName(ops[2].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
                appendColored(out, ctx, colorize, SyntaxColor::Compiler, std::format("{} operand(s)", inst.numOperands));
                break;

            default:
                appendColored(out, ctx, colorize, SyntaxColor::Compiler, std::format("{} operand(s)", inst.numOperands));
                break;
        }

        appendInstFlags(out, ctx, colorize, inst.emitFlags);
        out += '\n';
        ++idx;
    }

    return out;
}

void MicroInstrPrinter::print(const TaskContext& ctx, const MicroInstrStorage& instructions, const MicroOperandStorage& operands, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize)
{
    Logger::print(ctx, format(ctx, instructions, operands, regPrintMode, encoder, colorize));
    Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
}

SWC_END_NAMESPACE();
