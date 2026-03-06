#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Compiler/Lexer/SourceView.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

uint64_t MicroPassHelpers::normalizeToOpBits(uint64_t value, MicroOpBits opBits)
{
    if (opBits == MicroOpBits::B64)
        return value;

    const uint64_t mask = getBitsMask(opBits);
    return value & mask;
}

int64_t MicroPassHelpers::toSignedValue(uint64_t value, MicroOpBits opBits)
{
    const uint64_t normalized = normalizeToOpBits(value, opBits);
    switch (opBits)
    {
        case MicroOpBits::B8:
            return static_cast<int8_t>(normalized);
        case MicroOpBits::B16:
            return static_cast<int16_t>(normalized);
        case MicroOpBits::B32:
            return static_cast<int32_t>(normalized);
        case MicroOpBits::B64:
            return static_cast<int64_t>(normalized);
        default:
            return static_cast<int64_t>(normalized);
    }
}

bool MicroPassHelpers::tryInvertCondition(MicroCond& outCond, MicroCond cond)
{
    switch (cond)
    {
        case MicroCond::Equal:
        case MicroCond::Zero:
            outCond = MicroCond::NotEqual;
            return true;
        case MicroCond::NotEqual:
        case MicroCond::NotZero:
            outCond = MicroCond::Equal;
            return true;
        case MicroCond::Above:
            outCond = MicroCond::BelowOrEqual;
            return true;
        case MicroCond::AboveOrEqual:
            outCond = MicroCond::Below;
            return true;
        case MicroCond::Below:
            outCond = MicroCond::AboveOrEqual;
            return true;
        case MicroCond::BelowOrEqual:
        case MicroCond::NotAbove:
            outCond = MicroCond::Above;
            return true;
        case MicroCond::Greater:
            outCond = MicroCond::LessOrEqual;
            return true;
        case MicroCond::GreaterOrEqual:
            outCond = MicroCond::Less;
            return true;
        case MicroCond::Less:
            outCond = MicroCond::GreaterOrEqual;
            return true;
        case MicroCond::LessOrEqual:
            outCond = MicroCond::Greater;
            return true;
        case MicroCond::Overflow:
            outCond = MicroCond::NotOverflow;
            return true;
        case MicroCond::NotOverflow:
            outCond = MicroCond::Overflow;
            return true;
        case MicroCond::Parity:
        case MicroCond::EvenParity:
            outCond = MicroCond::NotParity;
            return true;
        case MicroCond::NotParity:
        case MicroCond::NotEvenParity:
            outCond = MicroCond::Parity;
            return true;
        default:
            return false;
    }
}

std::optional<bool> MicroPassHelpers::evaluateCondition(MicroCond condition, uint64_t lhs, uint64_t rhs, MicroOpBits opBits)
{
    const uint64_t lhsUnsigned = normalizeToOpBits(lhs, opBits);
    const uint64_t rhsUnsigned = normalizeToOpBits(rhs, opBits);
    const int64_t  lhsSigned   = toSignedValue(lhs, opBits);
    const int64_t  rhsSigned   = toSignedValue(rhs, opBits);

    switch (condition)
    {
        case MicroCond::Unconditional:
            return true;
        case MicroCond::Equal:
        case MicroCond::Zero:
            return lhsUnsigned == rhsUnsigned;
        case MicroCond::NotEqual:
        case MicroCond::NotZero:
            return lhsUnsigned != rhsUnsigned;
        case MicroCond::Above:
            return lhsUnsigned > rhsUnsigned;
        case MicroCond::AboveOrEqual:
            return lhsUnsigned >= rhsUnsigned;
        case MicroCond::Below:
            return lhsUnsigned < rhsUnsigned;
        case MicroCond::BelowOrEqual:
        case MicroCond::NotAbove:
            return lhsUnsigned <= rhsUnsigned;
        case MicroCond::Greater:
            return lhsSigned > rhsSigned;
        case MicroCond::GreaterOrEqual:
            return lhsSigned >= rhsSigned;
        case MicroCond::Less:
            return lhsSigned < rhsSigned;
        case MicroCond::LessOrEqual:
            return lhsSigned <= rhsSigned;
        default:
            return std::nullopt;
    }
}

bool MicroPassHelpers::rangesOverlap(uint64_t lhsOffset, uint32_t lhsSize, uint64_t rhsOffset, uint32_t rhsSize)
{
    if (!lhsSize || !rhsSize)
        return false;

    const uint64_t lhsEnd = lhsOffset + lhsSize;
    const uint64_t rhsEnd = rhsOffset + rhsSize;
    return lhsOffset < rhsEnd && rhsOffset < lhsEnd;
}

bool MicroPassHelpers::isStackBaseRegister(const MicroPassContext& context, MicroReg reg)
{
    const CallConv& conv = CallConv::get(context.callConvKind);
    if (reg == conv.stackPointer)
        return true;

    if (conv.framePointer.isValid() && reg == conv.framePointer)
        return true;

    if (context.encoder)
    {
        const MicroReg stackPointerReg = context.encoder->stackPointerReg();
        if (stackPointerReg.isValid() && reg == stackPointerReg)
            return true;
    }

    return false;
}

bool MicroPassHelpers::getMemAccessOpBits(MicroOpBits& outOpBits, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!ops)
        return false;

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegMem:
            outOpBits = ops[2].opBits;
            return true;
        case MicroInstrOpcode::LoadMemReg:
            outOpBits = ops[2].opBits;
            return true;
        case MicroInstrOpcode::LoadMemImm:
            outOpBits = ops[1].opBits;
            return true;
        case MicroInstrOpcode::LoadSignedExtRegMem:
            outOpBits = ops[3].opBits;
            return true;
        case MicroInstrOpcode::LoadZeroExtRegMem:
            outOpBits = ops[3].opBits;
            return true;
        case MicroInstrOpcode::CmpMemReg:
            outOpBits = ops[2].opBits;
            return true;
        case MicroInstrOpcode::CmpMemImm:
            outOpBits = ops[1].opBits;
            return true;
        case MicroInstrOpcode::OpUnaryMem:
            outOpBits = ops[1].opBits;
            return true;
        case MicroInstrOpcode::OpBinaryRegMem:
            outOpBits = ops[2].opBits;
            return true;
        case MicroInstrOpcode::OpBinaryMemReg:
            outOpBits = ops[2].opBits;
            return true;
        case MicroInstrOpcode::OpBinaryMemImm:
            outOpBits = ops[1].opBits;
            return true;
        default:
            return false;
    }
}

void MicroPassHelpers::collectReferencedLabels(const MicroStorage& storage, const MicroOperandStorage& operands, std::unordered_set<MicroLabelRef>& outLabels, bool includeJumpCondImm)
{
    outLabels.clear();
    for (const MicroInstr& inst : storage.view())
    {
        const bool isJumpCond    = inst.op == MicroInstrOpcode::JumpCond;
        const bool isJumpCondImm = inst.op == MicroInstrOpcode::JumpCondImm;
        if (!isJumpCond && (!includeJumpCondImm || !isJumpCondImm))
            continue;
        if (inst.numOperands < 3)
            continue;

        const MicroInstrOperand* const ops = inst.ops(operands);
        if (!ops || ops[2].valueU64 > std::numeric_limits<uint32_t>::max())
            continue;

        outLabels.insert(MicroLabelRef(static_cast<uint32_t>(ops[2].valueU64)));
    }
}

bool MicroPassHelpers::shouldClearDataflowStateOnControlFlowBoundary(const MicroInstr& inst, const MicroInstrOperand* ops, const std::unordered_set<MicroLabelRef>& referencedLabels)
{
    if (inst.op == MicroInstrOpcode::Label)
    {
        if (!ops || inst.numOperands < 1 || ops[0].valueU64 > std::numeric_limits<uint32_t>::max())
            return true;

        const MicroLabelRef labelRef(static_cast<uint32_t>(ops[0].valueU64));
        return referencedLabels.contains(labelRef);
    }

    return MicroInstrInfo::isTerminatorInstruction(inst);
}

bool MicroPassHelpers::tryFoldAddSubSignedNoOverflow(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits)
{
    if (op != MicroOp::Add && op != MicroOp::Subtract)
        return false;

    const int64_t lhsSigned = toSignedValue(lhs, opBits);
    const int64_t rhsSigned = toSignedValue(rhs, opBits);
    int64_t       minValue  = std::numeric_limits<int64_t>::min();
    int64_t       maxValue  = std::numeric_limits<int64_t>::max();
    switch (opBits)
    {
        case MicroOpBits::B8:
            minValue = std::numeric_limits<int8_t>::min();
            maxValue = std::numeric_limits<int8_t>::max();
            break;
        case MicroOpBits::B16:
            minValue = std::numeric_limits<int16_t>::min();
            maxValue = std::numeric_limits<int16_t>::max();
            break;
        case MicroOpBits::B32:
            minValue = std::numeric_limits<int32_t>::min();
            maxValue = std::numeric_limits<int32_t>::max();
            break;
        case MicroOpBits::B64:
            minValue = std::numeric_limits<int64_t>::min();
            maxValue = std::numeric_limits<int64_t>::max();
            break;
        default:
            return false;
    }

    int64_t resultSigned = 0;
    if (op == MicroOp::Add)
    {
        if ((rhsSigned > 0 && lhsSigned > maxValue - rhsSigned) ||
            (rhsSigned < 0 && lhsSigned < minValue - rhsSigned))
        {
            return false;
        }

        resultSigned = lhsSigned + rhsSigned;
    }
    else
    {
        if ((rhsSigned < 0 && lhsSigned > maxValue + rhsSigned) ||
            (rhsSigned > 0 && lhsSigned < minValue + rhsSigned))
        {
            return false;
        }

        resultSigned = lhsSigned - rhsSigned;
    }

    outValue = normalizeToOpBits(static_cast<uint64_t>(resultSigned), opBits);
    return true;
}

bool MicroPassHelpers::isAddOrSubMicroOp(MicroOp op)
{
    return op == MicroOp::Add || op == MicroOp::Subtract;
}

namespace
{
    bool mapMicroOpToFold(MicroOp microOp, Math::FoldBinaryOp& outOp, bool& outSignedLeft, bool& outSignedRight)
    {
        outSignedLeft  = false;
        outSignedRight = false;

        switch (microOp)
        {
            case MicroOp::Add:
                outOp = Math::FoldBinaryOp::Add;
                return true;
            case MicroOp::Subtract:
                outOp = Math::FoldBinaryOp::Subtract;
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
                outOp         = Math::FoldBinaryOp::ShiftArithmeticRight;
                outSignedLeft = true;
                return true;
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                outOp = Math::FoldBinaryOp::Multiply;
                return true;
            case MicroOp::DivideSigned:
                outOp          = Math::FoldBinaryOp::Divide;
                outSignedLeft  = true;
                outSignedRight = true;
                return true;
            case MicroOp::DivideUnsigned:
                outOp = Math::FoldBinaryOp::Divide;
                return true;
            case MicroOp::ModuloSigned:
                outOp          = Math::FoldBinaryOp::Modulo;
                outSignedLeft  = true;
                outSignedRight = true;
                return true;
            case MicroOp::ModuloUnsigned:
                outOp = Math::FoldBinaryOp::Modulo;
                return true;
            default:
                return false;
        }
    }
}

Math::FoldStatus MicroPassHelpers::foldBinaryImmediate(uint64_t& outValue, uint64_t inValue, uint64_t immediate, MicroOp microOp, MicroOpBits opBits)
{
    const uint64_t value    = normalizeToOpBits(inValue, opBits);
    const uint64_t imm      = normalizeToOpBits(immediate, opBits);
    const uint32_t bitWidth = getNumBits(opBits);
    if (!bitWidth)
        return Math::FoldStatus::Unsupported;

    Math::FoldBinaryOp foldOp;
    bool               signedLeft  = false;
    bool               signedRight = false;
    if (!mapMicroOpToFold(microOp, foldOp, signedLeft, signedRight))
        return Math::FoldStatus::Unsupported;

    const ApsInt leftInt(&value, bitWidth, !signedLeft);
    const ApsInt rightInt(&imm, bitWidth, !signedRight);

    Math::FoldBinaryIntOptions options;
    if (foldOp == Math::FoldBinaryOp::ShiftLeft || foldOp == Math::FoldBinaryOp::ShiftRight || foldOp == Math::FoldBinaryOp::ShiftArithmeticRight)
    {
        options.clampShiftCount     = true;
        options.ignoreShiftOverflow = true;
        options.shiftBitWidth       = bitWidth;
    }

    ApsInt                 foldedInt;
    const Math::FoldStatus status = Math::foldBinaryInt(foldedInt, leftInt, rightInt, foldOp, options);
    if (status != Math::FoldStatus::Ok)
        return status;

    outValue = normalizeToOpBits(foldedInt.as64(), opBits);
    return Math::FoldStatus::Ok;
}

Result MicroPassHelpers::raiseFoldSafetyError(const MicroPassContext& context, MicroInstrRef instructionRef, Math::FoldStatus status)
{
    const DiagnosticId diagId = Math::foldStatusDiagnosticId(status);
    if (diagId == DiagnosticId::None)
        return Result::Continue;

    TaskContext* const taskContext = context.taskContext;
    if (!taskContext)
        return Result::Error;

    Diagnostic    diag;
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();
    if (context.instructions && instructionRef.isValid())
    {
        if (const MicroInstr* inst = context.instructions->ptr(instructionRef))
            sourceCodeRef = inst->sourceCodeRef;
    }

    if (sourceCodeRef.isValid())
    {
        const SourceView& srcView = taskContext->compiler().srcView(sourceCodeRef.srcViewRef);
        diag                      = Diagnostic::get(diagId, srcView.fileRef());
        diag.last().addSpan(srcView.tokenCodeRange(*taskContext, sourceCodeRef.tokRef), "", DiagnosticSeverity::Error);
    }

    if (diag.elements().empty())
        diag = Diagnostic::get(diagId);

    diag.report(*taskContext);
    return Result::Error;
}

namespace
{
    bool isIdentityBinaryImm(MicroOp op, uint64_t value, MicroOpBits opBits)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return value == 0;
            case MicroOp::And:
            {
                const uint64_t mask = getBitsMask(opBits);
                return mask != 0 && value == mask;
            }
            default:
                return false;
        }
    }

    bool isNoOpLoadRegReg(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.numOperands >= 2 && ops[0].reg == ops[1].reg;
    }

    bool isNoOpLoadAddrRegMem(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_UNUSED(inst);
        if (ops[1].reg.isInstructionPointer())
            return false;
        return ops[3].valueU64 == 0 && ops[0].reg == ops[1].reg;
    }

    bool isNoOpLoadCondRegReg(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.numOperands >= 4 && ops[3].opBits == MicroOpBits::B64 && ops[0].reg == ops[1].reg;
    }

    bool isNoOpOpBinaryRegReg(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_UNUSED(inst);
        return ops[3].microOp == MicroOp::Exchange && ops[0].reg == ops[1].reg;
    }

    bool isNoOpOpBinaryRegImm(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_UNUSED(inst);
        return isIdentityBinaryImm(ops[2].microOp, ops[3].valueU64, ops[1].opBits);
    }
}

bool MicroPassHelpers::isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!ops && inst.numOperands != 0)
        return false;

    switch (inst.op)
    {
        case MicroInstrOpcode::End:
        case MicroInstrOpcode::Label:
        case MicroInstrOpcode::Push:
        case MicroInstrOpcode::Pop:
        case MicroInstrOpcode::Ret:
        case MicroInstrOpcode::Breakpoint:
        case MicroInstrOpcode::CallLocal:
        case MicroInstrOpcode::CallExtern:
        case MicroInstrOpcode::CallIndirect:
        case MicroInstrOpcode::JumpCond:
        case MicroInstrOpcode::JumpReg:
        case MicroInstrOpcode::JumpCondImm:
        case MicroInstrOpcode::LoadRegImm:
        case MicroInstrOpcode::LoadRegPtrImm:
        case MicroInstrOpcode::LoadRegPtrReloc:
        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadMemReg:
        case MicroInstrOpcode::LoadMemImm:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        case MicroInstrOpcode::LoadSignedExtRegReg:
        case MicroInstrOpcode::LoadZeroExtRegReg:
        case MicroInstrOpcode::LoadAmcRegMem:
        case MicroInstrOpcode::LoadAmcMemReg:
        case MicroInstrOpcode::LoadAmcMemImm:
        case MicroInstrOpcode::LoadAddrAmcRegMem:
        case MicroInstrOpcode::CmpRegReg:
        case MicroInstrOpcode::CmpRegImm:
        case MicroInstrOpcode::CmpMemReg:
        case MicroInstrOpcode::CmpMemImm:
        case MicroInstrOpcode::SetCondReg:
        case MicroInstrOpcode::ClearReg:
        case MicroInstrOpcode::OpUnaryMem:
        case MicroInstrOpcode::OpUnaryReg:
        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryMemReg:
        case MicroInstrOpcode::OpBinaryMemImm:
        case MicroInstrOpcode::OpTernaryRegRegReg:
            return false;
        case MicroInstrOpcode::Nop:
            return true;
        case MicroInstrOpcode::LoadRegReg:
            return isNoOpLoadRegReg(inst, ops);
        case MicroInstrOpcode::LoadAddrRegMem:
            return isNoOpLoadAddrRegMem(inst, ops);
        case MicroInstrOpcode::LoadCondRegReg:
            return isNoOpLoadCondRegReg(inst, ops);
        case MicroInstrOpcode::OpBinaryRegReg:
            return isNoOpOpBinaryRegReg(inst, ops);
        case MicroInstrOpcode::OpBinaryRegImm:
            return isNoOpOpBinaryRegImm(inst, ops);
    }

    return false;
}

bool MicroPassHelpers::violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!context.encoder || !ops)
        return false;

    MicroConformanceIssue issue;
    return context.encoder->queryConformanceIssue(issue, inst, ops);
}

SWC_END_NAMESPACE();
