#include "pch.h"
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstrPrinter.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

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

    std::string regNameDefault(MicroReg reg)
    {
        if (!reg.isValid())
            return "inv";

        if (reg.isInstructionPointer())
            return "rip";
        if (reg.isNoBase())
            return "nobase";

        if (reg.isInt())
            return std::format("r{}", reg.index());

        if (reg.isFloat())
            return std::format("f{}", reg.index());

        if (reg.isVirtualInt())
            return std::format("v{}", reg.index());

        if (reg.isVirtualFloat())
            return std::format("vf{}", reg.index());

        return std::format("reg#{}", reg.packed);
    }

    std::string regNameVirtual(MicroReg reg)
    {
        if (!reg.isValid())
            return "inv";

        if (reg.isInstructionPointer())
            return "ip";
        if (reg.isNoBase())
            return "nobase";

        if (reg.isInt() || reg.isVirtualInt())
            return std::format("v{}", reg.index());

        if (reg.isFloat() || reg.isVirtualFloat())
            return std::format("vf{}", reg.index());

        return std::format("reg#{}", reg.packed);
    }

    std::string regName(MicroReg reg, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        if (regPrintMode == MicroInstrRegPrintMode::Virtual)
            return regNameVirtual(reg);

        if (regPrintMode == MicroInstrRegPrintMode::Concrete)
        {
            if (encoder)
                return encoder->formatRegisterName(reg);
            return regNameDefault(reg);
        }

        return regNameDefault(reg);
    }

    std::string hexU64(uint64_t value)
    {
        return std::format("0x{:X}", value);
    }

    std::string memBaseOffset(MicroReg baseReg, uint64_t offset, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        if (offset == 0)
            return std::format("[{}]", regName(baseReg, regPrintMode, encoder));
        return std::format("[{} + {}]", regName(baseReg, regPrintMode, encoder), hexU64(offset));
    }

    std::string memAmc(MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        std::string out = "[";
        if (!baseReg.isNoBase())
            out += regName(baseReg, regPrintMode, encoder);

        if (!mulReg.isNoBase())
        {
            if (!baseReg.isNoBase())
                out += " + ";
            out += regName(mulReg, regPrintMode, encoder);
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

std::string MicroInstrPrinter::format(const TaskContext& ctx, const PagedStoreTyped<MicroInstr>& instructions, const PagedStoreTyped<MicroInstrOperand>& operands, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize)
{
    std::string out;
    auto&       storeOps      = operands.store();
    auto&       instructionsV = const_cast<PagedStoreTyped<MicroInstr>&>(instructions);

    uint32_t idx = 0;
    for (const auto& inst : instructionsV.view())
    {
        const auto* ops = inst.numOperands ? inst.ops(storeOps) : nullptr;

        appendColored(out, ctx, colorize, LogColor::Dim, std::format("{:04}", idx));
        out += "  ";
        appendColored(out, ctx, colorize, LogColor::BrightCyan, std::format("{:>26}", opcodeName(inst.op)));
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
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("sym#{}", ops[1].valueU32));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[2].valueU32));
                break;

            case MicroInstrOpcode::SymbolRelocValue:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("sym#{}", ops[2].valueU32));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[3].valueU32));
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                appendColored(out, ctx, colorize, LogColor::White, ops[0].name.isValid() ? ctx.idMgr().get(ops[0].name).name : "<invalid-symbol>");
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::CallIndirect:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::JumpTable:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("ip={}", ops[2].valueI32));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("table={}", ops[3].valueU32));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("count={}", ops[4].valueU32));
                break;

            case MicroInstrOpcode::JumpCond:
                appendColored(out, ctx, colorize, LogColor::Magenta, condJumpName(ops[0].jumpType));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::PatchJump:
                appendColored(out, ctx, colorize, LogColor::Green, std::format("from={}", ops[0].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("to={}", ops[1].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("imm={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::JumpCondImm:
                appendColored(out, ctx, colorize, LogColor::Magenta, condJumpName(ops[0].jumpType));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, std::format("to={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadRegImm:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[1].reg, ops[3].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[1].reg, ops[4].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[2].opBits), opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[2].opBits), opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memAmc(ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, memAmc(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[2].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                appendColored(out, ctx, colorize, LogColor::Yellow, memAmc(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[7].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadAddrAmcRegMem:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memAmc(ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}<-b{}", opBitsName(ops[3].opBits), opBitsName(ops[4].opBits)));
                break;

            case MicroInstrOpcode::LoadMemReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::LoadMemImm:
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[2].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CmpRegReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::CmpRegImm:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[2].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::CmpMemReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::CmpMemImm:
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[2].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::SetCondReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, condName(ops[1].cpuCond));
                break;

            case MicroInstrOpcode::LoadCondRegReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, condName(ops[2].cpuCond));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::ClearReg:
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpUnaryMem:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpUnaryReg:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[1].reg, ops[4].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[3].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[4].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[2].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryRegImm:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[3].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpBinaryMemImm:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[2].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, memBaseOffset(ops[0].reg, ops[3].valueU64, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Green, hexU64(ops[4].valueU64));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[1].opBits)));
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
                appendColored(out, ctx, colorize, LogColor::White, microOpName(ops[4].microOp));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[0].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[1].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Yellow, regName(ops[2].reg, regPrintMode, encoder));
                out += ", ";
                appendColored(out, ctx, colorize, LogColor::Magenta, std::format("b{}", opBitsName(ops[3].opBits)));
                break;

            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
                appendColored(out, ctx, colorize, LogColor::Dim, std::format("{} operand(s)", inst.numOperands));
                break;

            default:
                appendColored(out, ctx, colorize, LogColor::Dim, std::format("{} operand(s)", inst.numOperands));
                break;
        }

        appendInstFlags(out, ctx, colorize, inst.emitFlags);
        out += '\n';
        ++idx;
    }

    return out;
}

void MicroInstrPrinter::print(const TaskContext& ctx, const PagedStoreTyped<MicroInstr>& instructions, const PagedStoreTyped<MicroInstrOperand>& operands, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize)
{
    Logger::print(ctx, format(ctx, instructions, operands, regPrintMode, encoder, colorize));
}

SWC_END_NAMESPACE();

