#include "pch.h"
#include "Backend/CodeGen/Micro/MicroInstrPrinter.h"
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/Lexer/SourceView.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr auto K_JUMP_LABEL_COLOR     = SyntaxColor::Function;
    constexpr auto K_NATURAL_COLUMN_WIDTH = 56U;

    bool tryGetInstructionSourceLine(const TaskContext& ctx, const MicroInstrBuilder* builder, Ref instRef, uint32_t& outSourceLine)
    {
        outSourceLine = 0;
        if (!builder || !builder->hasFlag(MicroInstrBuilderFlagsE::DebugInfo))
            return false;

        const MicroInstrDebugInfo* dbgInfo = builder->debugInfo(instRef);
        if (!dbgInfo || !dbgInfo->sourceCodeRef.isValid())
            return false;

        const auto& srcView = ctx.compiler().srcView(dbgInfo->sourceCodeRef.srcViewRef);
        const auto  range   = srcView.tokenCodeRange(ctx, dbgInfo->sourceCodeRef.tokRef);
        if (range.line == 0)
            return false;

        outSourceLine = range.line;
        return true;
    }

    std::string_view opcodeEnumName(MicroInstrOpcode op)
    {
        switch (op)
        {
#define SWC_MICRO_INSTR_DEF(__enum, ...) \
    case MicroInstrOpcode::__enum: return #__enum;
#include "Backend/CodeGen/Micro/MicroInstr.Def.inc"

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

    std::string_view condJumpName(MicroCond cond)
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
            case MicroCond::Greater:
                return "g";
            case MicroCond::GreaterOrEqual:
                return "ge";
            case MicroCond::Less:
                return "l";
            case MicroCond::LessOrEqual:
                return "le";
            case MicroCond::NotOverflow:
                return "no";
            case MicroCond::NotParity:
                return "np";
            case MicroCond::NotZero:
                return "nz";
            case MicroCond::Parity:
                return "p";
            case MicroCond::Sign:
                return "s";
            case MicroCond::Unconditional:
                return "jmp";
            case MicroCond::Zero:
                return "z";
            default:
                return "?";
        }
    }

    bool isUnconditionalJump(MicroCond cond)
    {
        return cond == MicroCond::Unconditional;
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

    bool isJumpLabelToken(std::string_view token)
    {
        if (token.size() < 2 || token[0] != 'L')
            return false;

        size_t end = token.size();
        if (token.back() == ':')
        {
            if (token.size() < 3)
                return false;
            --end;
        }

        for (size_t i = 1; i < end; ++i)
        {
            if (!std::isdigit(static_cast<unsigned char>(token[i])))
                return false;
        }

        return true;
    }

    std::string hexU64(uint64_t value)
    {
        return std::format("0x{:X}", value);
    }

    std::string memBaseOffsetString(MicroReg baseReg, uint64_t offset, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        std::string out = "[";
        out += regName(baseReg, regPrintMode, encoder);
        if (offset != 0)
            out += std::format(" + {}", hexU64(offset));
        out += "]";
        return out;
    }

    std::string memAmcString(MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
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

    std::string_view binaryAssignOperator(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::FloatAdd:
                return "+=";
            case MicroOp::Subtract:
            case MicroOp::FloatSubtract:
                return "-=";
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
            case MicroOp::FloatMultiply:
                return "*=";
            case MicroOp::DivideSigned:
            case MicroOp::DivideUnsigned:
            case MicroOp::FloatDivide:
                return "/=";
            case MicroOp::ModuloSigned:
            case MicroOp::ModuloUnsigned:
                return "%=";
            case MicroOp::And:
            case MicroOp::FloatAnd:
                return "&=";
            case MicroOp::Or:
                return "|=";
            case MicroOp::Xor:
            case MicroOp::FloatXor:
                return "^=";
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftArithmeticLeft:
                return "<<=";
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return ">>=";
            default:
                return {};
        }
    }

    std::string_view binaryInfixOperator(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::FloatAdd:
                return "+";
            case MicroOp::Subtract:
            case MicroOp::FloatSubtract:
                return "-";
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
            case MicroOp::FloatMultiply:
                return "*";
            case MicroOp::DivideSigned:
            case MicroOp::DivideUnsigned:
            case MicroOp::FloatDivide:
                return "/";
            case MicroOp::ModuloSigned:
            case MicroOp::ModuloUnsigned:
                return "%";
            case MicroOp::And:
            case MicroOp::FloatAnd:
                return "&";
            case MicroOp::Or:
                return "|";
            case MicroOp::Xor:
            case MicroOp::FloatXor:
                return "^";
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftArithmeticLeft:
                return "<<";
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return ">>";
            default:
                return {};
        }
    }

    std::string naturalBinaryExpression(std::string_view lhs, MicroOp op, std::string_view rhs)
    {
        const auto assignOp = binaryAssignOperator(op);
        if (!assignOp.empty())
            return std::format("{} {} {}", lhs, assignOp, rhs);
        return std::format("{} = {}({}, {})", lhs, microOpName(op), lhs, rhs);
    }

    std::string naturalInstruction(const TaskContext& ctx, const MicroInstr& inst, const MicroInstrOperand* ops, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::Label:
                if (inst.numOperands >= 1)
                    return std::format("L{}:", static_cast<Ref>(ops[0].valueU64));
                return "label";

            case MicroInstrOpcode::LoadRegReg:
                return std::format("{} = {}", regName(ops[0].reg, regPrintMode, encoder), regName(ops[1].reg, regPrintMode, encoder));
            case MicroInstrOpcode::LoadRegImm:
                return std::format("{} = {}", regName(ops[0].reg, regPrintMode, encoder), hexU64(ops[2].valueU64));
            case MicroInstrOpcode::LoadRegMem:
                return std::format("{} = {}", regName(ops[0].reg, regPrintMode, encoder), memBaseOffsetString(ops[1].reg, ops[3].valueU64, regPrintMode, encoder));
            case MicroInstrOpcode::LoadAddrRegMem:
                return std::format("{} = &{}", regName(ops[0].reg, regPrintMode, encoder), memBaseOffsetString(ops[1].reg, ops[3].valueU64, regPrintMode, encoder));
            case MicroInstrOpcode::LoadMemReg:
                return std::format("{} = {}", memBaseOffsetString(ops[0].reg, ops[3].valueU64, regPrintMode, encoder), regName(ops[1].reg, regPrintMode, encoder));
            case MicroInstrOpcode::LoadMemImm:
                return std::format("{} = {}", memBaseOffsetString(ops[0].reg, ops[2].valueU64, regPrintMode, encoder), hexU64(ops[3].valueU64));
            case MicroInstrOpcode::LoadAmcRegMem:
                return std::format("{} = {}", regName(ops[0].reg, regPrintMode, encoder), memAmcString(ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder));
            case MicroInstrOpcode::LoadAmcMemReg:
                return std::format("{} = {}", memAmcString(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder), regName(ops[2].reg, regPrintMode, encoder));
            case MicroInstrOpcode::LoadAmcMemImm:
                return std::format("{} = {}", memAmcString(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder), hexU64(ops[7].valueU64));
            case MicroInstrOpcode::ClearReg:
                return std::format("{} = 0", regName(ops[0].reg, regPrintMode, encoder));

            case MicroInstrOpcode::OpUnaryReg:
                return std::format("{} = {} {}", regName(ops[0].reg, regPrintMode, encoder), microOpName(ops[2].microOp), regName(ops[0].reg, regPrintMode, encoder));
            case MicroInstrOpcode::OpUnaryMem:
                return std::format("{} {}", microOpName(ops[2].microOp), memBaseOffsetString(ops[0].reg, ops[3].valueU64, regPrintMode, encoder));

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                const auto lhs = regName(ops[0].reg, regPrintMode, encoder);
                const auto rhs = hexU64(ops[3].valueU64);
                return naturalBinaryExpression(lhs, ops[2].microOp, rhs);
            }

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                const auto lhs = regName(ops[0].reg, regPrintMode, encoder);
                const auto rhs = regName(ops[1].reg, regPrintMode, encoder);
                return naturalBinaryExpression(lhs, ops[3].microOp, rhs);
            }

            case MicroInstrOpcode::OpBinaryRegMem:
            {
                const auto lhs      = regName(ops[0].reg, regPrintMode, encoder);
                const auto rhs      = memBaseOffsetString(ops[1].reg, ops[4].valueU64, regPrintMode, encoder);
                return naturalBinaryExpression(lhs, ops[3].microOp, rhs);
            }

            case MicroInstrOpcode::OpBinaryMemReg:
            {
                const auto lhs      = memBaseOffsetString(ops[0].reg, ops[4].valueU64, regPrintMode, encoder);
                const auto rhs      = regName(ops[1].reg, regPrintMode, encoder);
                return naturalBinaryExpression(lhs, ops[3].microOp, rhs);
            }

            case MicroInstrOpcode::OpBinaryMemImm:
            {
                const auto lhs      = memBaseOffsetString(ops[0].reg, ops[3].valueU64, regPrintMode, encoder);
                const auto rhs      = hexU64(ops[4].valueU64);
                return naturalBinaryExpression(lhs, ops[2].microOp, rhs);
            }

            case MicroInstrOpcode::OpTernaryRegRegReg:
            {
                const auto infixOp = binaryInfixOperator(ops[4].microOp);
                if (!infixOp.empty())
                    return std::format("{} = {} {} {}", regName(ops[0].reg, regPrintMode, encoder), regName(ops[1].reg, regPrintMode, encoder), infixOp, regName(ops[2].reg, regPrintMode, encoder));
                return std::format("{} = {}({}, {}, {})",
                                   regName(ops[0].reg, regPrintMode, encoder),
                                   microOpName(ops[4].microOp),
                                   regName(ops[1].reg, regPrintMode, encoder),
                                   regName(ops[2].reg, regPrintMode, encoder),
                                   std::format("b{}", opBitsName(ops[3].opBits)));
            }

            case MicroInstrOpcode::CmpRegReg:
                return std::format("cmp({}, {})", regName(ops[0].reg, regPrintMode, encoder), regName(ops[1].reg, regPrintMode, encoder));
            case MicroInstrOpcode::CmpRegImm:
                return std::format("cmp({}, {})", regName(ops[0].reg, regPrintMode, encoder), hexU64(ops[2].valueU64));
            case MicroInstrOpcode::CmpMemReg:
                return std::format("cmp({}, {})", memBaseOffsetString(ops[0].reg, ops[3].valueU64, regPrintMode, encoder), regName(ops[1].reg, regPrintMode, encoder));
            case MicroInstrOpcode::CmpMemImm:
                return std::format("cmp({}, {})", memBaseOffsetString(ops[0].reg, ops[2].valueU64, regPrintMode, encoder), hexU64(ops[3].valueU64));

            case MicroInstrOpcode::SetCondReg:
                return std::format("{} = set{}", regName(ops[0].reg, regPrintMode, encoder), condName(ops[1].cpuCond));
            case MicroInstrOpcode::LoadCondRegReg:
                return std::format("{} = {} if {}", regName(ops[0].reg, regPrintMode, encoder), regName(ops[1].reg, regPrintMode, encoder), condName(ops[2].cpuCond));

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                return std::format("call {}", ops[0].name.isValid() ? std::string(ctx.idMgr().get(ops[0].name).name) : std::string("<invalid-symbol>"));
            case MicroInstrOpcode::CallIndirect:
                return std::format("call {}", regName(ops[0].reg, regPrintMode, encoder));

            case MicroInstrOpcode::JumpReg:
                return std::format("jump {}", regName(ops[0].reg, regPrintMode, encoder));
            case MicroInstrOpcode::JumpCond:
                if (isUnconditionalJump(ops[0].cpuCond))
                {
                    if (inst.numOperands >= 3)
                        return std::format("jump L{}", static_cast<Ref>(ops[2].valueU64));
                    return "jump";
                }
                if (inst.numOperands >= 3)
                    return std::format("if {} jump L{}", condJumpName(ops[0].cpuCond), static_cast<Ref>(ops[2].valueU64));
                return std::format("if {} jump", condJumpName(ops[0].cpuCond));
            case MicroInstrOpcode::JumpCondImm:
                if (isUnconditionalJump(ops[0].cpuCond))
                    return std::format("jump {}", ops[2].valueU64);
                return std::format("if {} jump {}", condJumpName(ops[0].cpuCond), ops[2].valueU64);

            case MicroInstrOpcode::Ret:
                return "ret";
            case MicroInstrOpcode::Enter:
                return "enter";
            case MicroInstrOpcode::Leave:
                return "leave";
            case MicroInstrOpcode::Push:
                return std::format("push {}", regName(ops[0].reg, regPrintMode, encoder));
            case MicroInstrOpcode::Pop:
                return std::format("pop {}", regName(ops[0].reg, regPrintMode, encoder));
            default:
                return std::string(opcodeName(inst.op));
        }
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

    void appendNaturalColumn(std::string&                           out,
                             const TaskContext&                     ctx,
                             bool                                   colorize,
                             std::string                            value,
                             const std::unordered_set<std::string>& concreteRegs,
                             const std::unordered_set<std::string>& virtualRegs,
                             const std::optional<std::string>&      jumpTargetInstIndex)
    {
        size_t jumpTargetIndexStart = std::string::npos;
        if (jumpTargetInstIndex)
        {
            value += " ";
            jumpTargetIndexStart = value.size();
            value += *jumpTargetInstIndex;
        }

        if (value.size() > K_NATURAL_COLUMN_WIDTH)
            value = std::format("{}...", value.substr(0, K_NATURAL_COLUMN_WIDTH - 3));
        auto appendNaturalToken = [&](std::string_view token, size_t tokenStart) {
            if (tokenStart == jumpTargetIndexStart && jumpTargetInstIndex && token == *jumpTargetInstIndex)
            {
                appendColored(out, ctx, colorize, SyntaxColor::InstructionIndex, token);
                return;
            }

            auto isHex = [](std::string_view t) {
                if (t.size() < 3 || t[0] != '0' || (t[1] != 'x' && t[1] != 'X'))
                    return false;
                for (size_t i = 2; i < t.size(); ++i)
                {
                    const unsigned char c = static_cast<unsigned char>(t[i]);
                    if (!std::isxdigit(c))
                        return false;
                }
                return true;
            };

            const std::string tokenStr(token);
            if (virtualRegs.contains(tokenStr))
            {
                appendColored(out, ctx, colorize, SyntaxColor::RegisterVirtual, token);
            }
            else if (concreteRegs.contains(tokenStr))
            {
                appendColored(out, ctx, colorize, SyntaxColor::Register, token);
            }
            else if (isHex(token))
            {
                appendColored(out, ctx, colorize, SyntaxColor::Number, token);
            }
            else if (isJumpLabelToken(token))
            {
                appendColored(out, ctx, colorize, K_JUMP_LABEL_COLOR, token);
            }
            else if (token == "=" || token == "+=" || token == "-=" || token == "*=" || token == "/=" || token == "%=" || token == "&=" || token == "|=" || token == "^=" || token == "<<=" || token == ">>=" || token == "+" || token == "-" || token == "*" || token == "/" || token == "%" || token == "&" || token == "|" || token == "^" || token == "<<" || token == ">>")
            {
                appendColored(out, ctx, colorize, SyntaxColor::Logic, token);
            }
            else
            {
                appendColored(out, ctx, colorize, SyntaxColor::Code, token);
            }
        };

        const auto padded = std::format("{:<{}}", value, K_NATURAL_COLUMN_WIDTH);
        size_t     pos    = 0;
        while (pos < padded.size())
        {
            if (std::isspace(static_cast<unsigned char>(padded[pos])))
            {
                size_t start = pos;
                while (pos < padded.size() && std::isspace(static_cast<unsigned char>(padded[pos])))
                    ++pos;
                appendColored(out, ctx, colorize, SyntaxColor::Code, std::string_view(padded).substr(start, pos - start));
                continue;
            }

            const char c = padded[pos];
            if (std::ispunct(static_cast<unsigned char>(c)) && c != '_' && c != '%' && c != 'x' && c != ':')
            {
                if (pos + 2 < padded.size())
                {
                    const auto three = std::string_view(padded).substr(pos, 3);
                    if (three == "<<=" || three == ">>=")
                    {
                        appendNaturalToken(three, pos);
                        pos += 3;
                        continue;
                    }
                }

                if (pos + 1 < padded.size())
                {
                    const auto two = std::string_view(padded).substr(pos, 2);
                    if (two == "+=" || two == "-=" || two == "*=" || two == "/=" || two == "%=" || two == "&=" || two == "|=" || two == "^=" || two == "<<" || two == ">>")
                    {
                        appendNaturalToken(two, pos);
                        pos += 2;
                        continue;
                    }
                }

                appendNaturalToken(std::string_view(padded).substr(pos, 1), pos);
                ++pos;
                continue;
            }

            size_t start = pos;
            while (pos < padded.size())
            {
                const char cc = padded[pos];
                if (std::isspace(static_cast<unsigned char>(cc)))
                    break;
                if (std::ispunct(static_cast<unsigned char>(cc)) && cc != '_' && cc != '%' && cc != 'x' && cc != ':')
                    break;
                ++pos;
            }

            appendNaturalToken(std::string_view(padded).substr(start, pos - start), start);
        }

        appendColored(out, ctx, colorize, SyntaxColor::Compiler, " | ");
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

    void appendSep(std::string& out)
    {
        out += ", ";
    }

    void appendTypeBits(std::string& out, const TaskContext& ctx, bool colorize, MicroOpBits bits)
    {
        appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}", opBitsName(bits)));
    }

    void appendTypeBitsCast(std::string& out, const TaskContext& ctx, bool colorize, MicroOpBits dstBits, MicroOpBits srcBits)
    {
        appendColored(out, ctx, colorize, SyntaxColor::Type, std::format("b{}<-b{}", opBitsName(dstBits), opBitsName(srcBits)));
    }

    void appendRegRegBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t regA, uint32_t regB, uint32_t bits, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendRegister(out, ctx, colorize, ops[regA].reg, regPrintMode, encoder);
        appendSep(out);
        appendRegister(out, ctx, colorize, ops[regB].reg, regPrintMode, encoder);
        appendSep(out);
        appendTypeBits(out, ctx, colorize, ops[bits].opBits);
    }

    void appendRegImmBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t reg, uint32_t bits, uint32_t imm, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendRegister(out, ctx, colorize, ops[reg].reg, regPrintMode, encoder);
        appendSep(out);
        appendTypeBits(out, ctx, colorize, ops[bits].opBits);
        appendSep(out);
        appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[imm].valueU64));
    }

    void appendRegNumberBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t reg, uint32_t number, uint32_t bits, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendRegister(out, ctx, colorize, ops[reg].reg, regPrintMode, encoder);
        appendSep(out);
        appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[number].valueU64));
        appendSep(out);
        appendTypeBits(out, ctx, colorize, ops[bits].opBits);
    }

    void appendRegMemBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t reg, uint32_t baseReg, uint32_t bits, uint32_t offset, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendRegister(out, ctx, colorize, ops[reg].reg, regPrintMode, encoder);
        appendSep(out);
        appendMemBaseOffset(out, ctx, colorize, ops[baseReg].reg, ops[offset].valueU64, regPrintMode, encoder);
        appendSep(out);
        appendTypeBits(out, ctx, colorize, ops[bits].opBits);
    }

    void appendMemRegBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t baseReg, uint32_t reg, uint32_t bits, uint32_t offset, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendMemBaseOffset(out, ctx, colorize, ops[baseReg].reg, ops[offset].valueU64, regPrintMode, encoder);
        appendSep(out);
        appendRegister(out, ctx, colorize, ops[reg].reg, regPrintMode, encoder);
        appendSep(out);
        appendTypeBits(out, ctx, colorize, ops[bits].opBits);
    }

    void appendMemImmBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t baseReg, uint32_t bits, uint32_t offset, uint32_t imm, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendMemBaseOffset(out, ctx, colorize, ops[baseReg].reg, ops[offset].valueU64, regPrintMode, encoder);
        appendSep(out);
        appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[imm].valueU64));
        appendSep(out);
        appendTypeBits(out, ctx, colorize, ops[bits].opBits);
    }

    void appendRegRegCastBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t regA, uint32_t regB, uint32_t dstBits, uint32_t srcBits, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendRegister(out, ctx, colorize, ops[regA].reg, regPrintMode, encoder);
        appendSep(out);
        appendRegister(out, ctx, colorize, ops[regB].reg, regPrintMode, encoder);
        appendSep(out);
        appendTypeBitsCast(out, ctx, colorize, ops[dstBits].opBits, ops[srcBits].opBits);
    }

    void appendRegMemCastBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, uint32_t reg, uint32_t baseReg, uint32_t dstBits, uint32_t srcBits, uint32_t offset, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        appendRegister(out, ctx, colorize, ops[reg].reg, regPrintMode, encoder);
        appendSep(out);
        appendMemBaseOffset(out, ctx, colorize, ops[baseReg].reg, ops[offset].valueU64, regPrintMode, encoder);
        appendSep(out);
        appendTypeBitsCast(out, ctx, colorize, ops[dstBits].opBits, ops[srcBits].opBits);
    }

    void appendAmcRegMemCastBits(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrOperand* ops, bool withDestReg, uint32_t dstReg, uint32_t baseReg, uint32_t mulReg, uint32_t dstBits, uint32_t srcBits, uint32_t mulValue, uint32_t addValue, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder)
    {
        if (withDestReg)
        {
            appendRegister(out, ctx, colorize, ops[dstReg].reg, regPrintMode, encoder);
            appendSep(out);
        }

        appendMemAmc(out, ctx, colorize, ops[baseReg].reg, ops[mulReg].reg, ops[mulValue].valueU64, ops[addValue].valueU64, regPrintMode, encoder);
        appendSep(out);
        appendTypeBitsCast(out, ctx, colorize, ops[dstBits].opBits, ops[srcBits].opBits);
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

    bool appendInstructionDebugInfo(std::string& out, const TaskContext& ctx, bool colorize, const MicroInstrBuilder* builder, Ref instRef, std::unordered_set<uint64_t>& seenDebugLines)
    {
        uint32_t sourceLine = 0;
        if (!tryGetInstructionSourceLine(ctx, builder, instRef, sourceLine))
            return false;

        const MicroInstrDebugInfo* dbgInfo  = SWC_CHECK_NOT_NULL(builder->debugInfo(instRef));
        const auto&                srcView  = ctx.compiler().srcView(dbgInfo->sourceCodeRef.srcViewRef);
        const uint64_t             debugKey = (static_cast<uint64_t>(dbgInfo->sourceCodeRef.srcViewRef.get()) << 32) | static_cast<uint64_t>(sourceLine);
        if (seenDebugLines.contains(debugKey))
            return false;
        seenDebugLines.insert(debugKey);

        out += '\n';
        appendColored(out, ctx, colorize, SyntaxColor::Compiler, std::format("{:04}", sourceLine));
        out += "  ";
        Utf8 codeLine = srcView.codeLine(ctx, sourceLine);
        codeLine.trim();
        out += SyntaxColorHelper::colorize(ctx, SyntaxColorMode::ForLog, codeLine, colorize);
        return true;
    }
}

std::string MicroInstrPrinter::format(const TaskContext& ctx, const MicroInstrStorage& instructions, const MicroOperandStorage& operands, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize, const MicroInstrBuilder* builder)
{
    std::string                       out;
    auto&                             storeOps      = operands;
    auto&                             storeOpsMut   = const_cast<MicroOperandStorage&>(operands);
    auto&                             instructionsV = const_cast<MicroInstrStorage&>(instructions);
    auto                              view          = instructionsV.view();
    std::unordered_set<uint64_t>      seenDebugLines;
    std::unordered_map<Ref, uint32_t> instIndexByRef;
    std::unordered_map<Ref, uint32_t> labelIndexByRef;

    uint32_t scanIdx = 0;
    for (auto it = view.begin(); it != view.end(); ++it)
    {
        instIndexByRef[it.current] = scanIdx;
        const MicroInstr& inst     = *it;
        if (inst.op == MicroInstrOpcode::Label && inst.numOperands >= 1)
        {
            const auto* ops                                    = inst.ops(storeOps);
            labelIndexByRef[static_cast<Ref>(ops[0].valueU64)] = scanIdx;
        }
        ++scanIdx;
    }

    uint32_t idx = 0;
    for (auto it = view.begin(); it != view.end(); ++it)
    {
        const Ref                       instRef = it.current;
        const MicroInstr&               inst    = *it;
        const auto*                     ops     = inst.numOperands ? inst.ops(storeOps) : nullptr;
        auto                            natural = naturalInstruction(ctx, inst, ops, regPrintMode, encoder);
        std::optional<std::string>      naturalJumpTargetIndex;
        std::unordered_set<std::string> concreteRegs;
        std::unordered_set<std::string> virtualRegs;
        if (inst.numOperands)
        {
            SmallVector<MicroInstrRegOperandRef> regRefs;
            inst.collectRegOperands(storeOpsMut, regRefs, encoder);
            for (const auto& regRef : regRefs)
            {
                if (!regRef.reg || !regRef.reg->isValid())
                    continue;

                const auto regToken = regName(*regRef.reg, regPrintMode, encoder);
                if (regRef.reg->isVirtual())
                    virtualRegs.insert(regToken);
                else
                    concreteRegs.insert(regToken);
            }
        }

        if (inst.op == MicroInstrOpcode::JumpCond && inst.numOperands >= 3)
        {
            const Ref labelRef = static_cast<Ref>(ops[2].valueU64);
            auto      labelIt  = labelIndexByRef.find(labelRef);
            if (labelIt != labelIndexByRef.end())
                naturalJumpTargetIndex = std::format("{:04}", labelIt->second);
            else
                naturalJumpTargetIndex = "????";
        }

        appendColored(out, ctx, colorize, SyntaxColor::InstructionIndex, std::format("{:04}", idx));
        out += "  ";
        appendNaturalColumn(out, ctx, colorize, natural, concreteRegs, virtualRegs, naturalJumpTargetIndex);

        if (inst.op == MicroInstrOpcode::Label)
        {
            if (inst.numOperands >= 1)
            {
                const Ref labelRef = static_cast<Ref>(ops[0].valueU64);
                appendColored(out, ctx, colorize, K_JUMP_LABEL_COLOR, std::format("L{}:", labelRef));
            }

            appendInstFlags(out, ctx, colorize, inst.emitFlags);
            appendInstructionDebugInfo(out, ctx, colorize, builder, instRef, seenDebugLines);
            out += '\n';
            ++idx;
            continue;
        }

        appendColored(out, ctx, colorize, SyntaxColor::MicroInstruction, std::format("{:>26}", opcodeName(inst.op)));
        out += " ";

        switch (inst.op)
        {
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Enter:
            case MicroInstrOpcode::Leave:
            case MicroInstrOpcode::Ignore:
            case MicroInstrOpcode::Debug:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Ret:
                break;
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
            case MicroInstrOpcode::JumpReg:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("sym#{}", ops[1].valueU32));
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[2].valueU32));
                break;

            case MicroInstrOpcode::SymbolRelocValue:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendTypeBits(out, ctx, colorize, ops[1].opBits);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("sym#{}", ops[2].valueU32));
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[3].valueU32));
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                appendColored(out, ctx, colorize, SyntaxColor::Code, ops[0].name.isValid() ? ctx.idMgr().get(ops[0].name).name : "<invalid-symbol>");
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Type, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::CallIndirect:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Type, callConvName(ops[1].callConv));
                break;

            case MicroInstrOpcode::JumpTable:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[1].reg, regPrintMode, encoder);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("ip={}", ops[2].valueI32));
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("table={}", ops[3].valueU32));
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("count={}", ops[4].valueU32));
                break;

            case MicroInstrOpcode::JumpCond:
                if (!isUnconditionalJump(ops[0].cpuCond))
                {
                    appendColored(out, ctx, colorize, SyntaxColor::Type, condJumpName(ops[0].cpuCond));
                    appendSep(out);
                    appendTypeBits(out, ctx, colorize, ops[1].opBits);
                }
                else
                {
                    appendColored(out, ctx, colorize, SyntaxColor::Code, "jump");
                }
                if (inst.numOperands >= 3)
                {
                    const Ref labelRef = static_cast<Ref>(ops[2].valueU64);
                    out += " ";
                    appendColored(out, ctx, colorize, K_JUMP_LABEL_COLOR, std::format("L{}", labelRef));
                    auto labelIt = labelIndexByRef.find(labelRef);
                    if (labelIt != labelIndexByRef.end())
                    {
                        out += " ";
                        appendColored(out, ctx, colorize, SyntaxColor::InstructionIndex, std::format("{:04}", labelIt->second));
                    }
                    else
                    {
                        out += " ";
                        appendColored(out, ctx, colorize, SyntaxColor::InstructionIndex, "????");
                    }
                }
                break;

            case MicroInstrOpcode::PatchJump:
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("from={}", ops[0].valueU64));
                appendSep(out);
                if (ops[2].valueU64 == 2)
                {
                    const Ref targetRef = static_cast<Ref>(ops[1].valueU64);
                    appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("to_ref={}", targetRef));
                    auto itDst = instIndexByRef.find(targetRef);
                    if (itDst != instIndexByRef.end())
                    {
                        out += " ";
                        appendColored(out, ctx, colorize, SyntaxColor::Compiler, std::format("(idx={})", itDst->second));
                    }
                }
                else
                {
                    appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("to={}", ops[1].valueU64));
                }
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("imm={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::JumpCondImm:
                if (!isUnconditionalJump(ops[0].cpuCond))
                {
                    appendColored(out, ctx, colorize, SyntaxColor::Type, condJumpName(ops[0].cpuCond));
                    appendSep(out);
                    appendTypeBits(out, ctx, colorize, ops[1].opBits);
                    appendSep(out);
                }
                else
                {
                    appendColored(out, ctx, colorize, SyntaxColor::Code, "jump");
                    appendSep(out);
                }
                appendColored(out, ctx, colorize, SyntaxColor::Number, std::format("to={}", ops[2].valueU64));
                break;

            case MicroInstrOpcode::LoadRegReg:
                appendRegRegBits(out, ctx, colorize, ops, 0, 1, 2, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadRegImm:
                appendRegImmBits(out, ctx, colorize, ops, 0, 1, 2, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                appendRegMemBits(out, ctx, colorize, ops, 0, 1, 2, 3, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                appendRegMemCastBits(out, ctx, colorize, ops, 0, 1, 2, 3, 4, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                appendRegRegCastBits(out, ctx, colorize, ops, 0, 1, 2, 3, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
                appendAmcRegMemCastBits(out, ctx, colorize, ops, true, 0, 1, 2, 3, 4, 5, 6, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                appendMemAmc(out, ctx, colorize, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder);
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[2].reg, regPrintMode, encoder);
                appendSep(out);
                appendTypeBitsCast(out, ctx, colorize, ops[3].opBits, ops[4].opBits);
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                appendMemAmc(out, ctx, colorize, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, regPrintMode, encoder);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Number, hexU64(ops[7].valueU64));
                appendSep(out);
                appendTypeBitsCast(out, ctx, colorize, ops[3].opBits, ops[4].opBits);
                break;

            case MicroInstrOpcode::LoadAddrAmcRegMem:
                appendAmcRegMemCastBits(out, ctx, colorize, ops, true, 0, 1, 2, 3, 4, 5, 6, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadMemReg:
                appendMemRegBits(out, ctx, colorize, ops, 0, 1, 2, 3, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::LoadMemImm:
                appendMemImmBits(out, ctx, colorize, ops, 0, 1, 2, 3, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::CmpRegReg:
                appendRegRegBits(out, ctx, colorize, ops, 0, 1, 2, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::CmpRegImm:
                appendRegNumberBits(out, ctx, colorize, ops, 0, 2, 1, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::CmpMemReg:
                appendMemRegBits(out, ctx, colorize, ops, 0, 1, 2, 3, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::CmpMemImm:
                appendMemImmBits(out, ctx, colorize, ops, 0, 1, 2, 3, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::SetCondReg:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Type, condName(ops[1].cpuCond));
                break;

            case MicroInstrOpcode::LoadCondRegReg:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[1].reg, regPrintMode, encoder);
                appendSep(out);
                appendColored(out, ctx, colorize, SyntaxColor::Type, condName(ops[2].cpuCond));
                appendSep(out);
                appendTypeBits(out, ctx, colorize, ops[3].opBits);
                break;

            case MicroInstrOpcode::ClearReg:
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendTypeBits(out, ctx, colorize, ops[1].opBits);
                break;

            case MicroInstrOpcode::OpUnaryMem:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                appendSep(out);
                appendMemBaseOffset(out, ctx, colorize, ops[0].reg, ops[3].valueU64, regPrintMode, encoder);
                appendSep(out);
                appendTypeBits(out, ctx, colorize, ops[1].opBits);
                break;

            case MicroInstrOpcode::OpUnaryReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendTypeBits(out, ctx, colorize, ops[1].opBits);
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[3].microOp));
                appendSep(out);
                appendRegRegBits(out, ctx, colorize, ops, 0, 1, 2, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[3].microOp));
                appendSep(out);
                appendRegMemBits(out, ctx, colorize, ops, 0, 1, 2, 4, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[3].microOp));
                appendSep(out);
                appendMemRegBits(out, ctx, colorize, ops, 0, 1, 2, 4, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::OpBinaryRegImm:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                appendSep(out);
                appendRegNumberBits(out, ctx, colorize, ops, 0, 3, 1, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::OpBinaryMemImm:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[2].microOp));
                appendSep(out);
                appendMemImmBits(out, ctx, colorize, ops, 0, 1, 3, 4, regPrintMode, encoder);
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
                appendColored(out, ctx, colorize, SyntaxColor::Code, microOpName(ops[4].microOp));
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[0].reg, regPrintMode, encoder);
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[1].reg, regPrintMode, encoder);
                appendSep(out);
                appendRegister(out, ctx, colorize, ops[2].reg, regPrintMode, encoder);
                appendSep(out);
                appendTypeBits(out, ctx, colorize, ops[3].opBits);
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
        appendInstructionDebugInfo(out, ctx, colorize, builder, instRef, seenDebugLines);
        out += '\n';
        ++idx;
    }

    return out;
}

void MicroInstrPrinter::print(const TaskContext& ctx, const MicroInstrStorage& instructions, const MicroOperandStorage& operands, MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize, const MicroInstrBuilder* builder)
{
    Logger::print(ctx, format(ctx, instructions, operands, regPrintMode, encoder, colorize, builder));
    Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
}

SWC_END_NAMESPACE();
