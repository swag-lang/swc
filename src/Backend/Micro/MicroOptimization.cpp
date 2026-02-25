#include "pch.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Compiler/Lexer/SourceView.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

uint64_t MicroOptimization::normalizeToOpBits(uint64_t value, MicroOpBits opBits)
{
    if (opBits == MicroOpBits::B64)
        return value;

    const uint64_t mask = getOpBitsMask(opBits);
    return value & mask;
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

Math::FoldStatus MicroOptimization::foldBinaryImmediate(uint64_t& outValue, uint64_t inValue, uint64_t immediate, MicroOp microOp, MicroOpBits opBits)
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

Result MicroOptimization::raiseFoldSafetyError(MicroPassContext& context, Ref instructionRef, Math::FoldStatus status)
{
    const DiagnosticId diagId = Math::foldStatusDiagnosticId(status);
    if (diagId == DiagnosticId::None)
        return Result::Continue;

    TaskContext* const taskContext = context.taskContext;
    if (!taskContext)
        return Result::Error;

    Diagnostic    diag;
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();
    if (context.instructions && instructionRef != INVALID_REF)
    {
        if (const MicroInstr* inst = context.instructions->ptr(instructionRef))
            sourceCodeRef = inst->sourceCodeRef;
    }

    if (!sourceCodeRef.isValid() && context.builder && instructionRef != INVALID_REF)
    {
        const MicroDebugInfo* debugInfo = context.builder->debugInfo(instructionRef);
        if (debugInfo && debugInfo->sourceCodeRef.isValid())
            sourceCodeRef = debugInfo->sourceCodeRef;
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
                const uint64_t mask = getOpBitsMask(opBits);
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

bool MicroOptimization::isNoOpEncoderInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
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
        case MicroInstrOpcode::CallIndirect:
        case MicroInstrOpcode::JumpTable:
        case MicroInstrOpcode::JumpCond:
        case MicroInstrOpcode::JumpReg:
        case MicroInstrOpcode::JumpCondImm:
        case MicroInstrOpcode::LoadRegImm:
        case MicroInstrOpcode::LoadRegPtrImm:
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

bool MicroOptimization::violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!context.encoder || !ops)
        return false;

    MicroConformanceIssue issue;
    return context.encoder->queryConformanceIssue(issue, inst, ops);
}

SWC_END_NAMESPACE();
