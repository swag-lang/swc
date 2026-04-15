#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Support/Math/ApsInt.h"

SWC_BEGIN_NAMESPACE();

bool MicroPassHelpers::violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    if (!context.encoder || !ops)
        return false;

    MicroConformanceIssue issue;
    return context.encoder->queryConformanceIssue(issue, inst, ops);
}

uint32_t MicroPassHelpers::replaceRegInLocalUses(MicroStorage&        storage,
                                                 MicroOperandStorage& operands,
                                                 MicroInstrRef        afterInstRef,
                                                 MicroReg             fromReg,
                                                 MicroReg             toReg)
{
    if (!fromReg.isValid() || fromReg.isNoBase())
        return 0;
    if (fromReg == toReg)
        return 0;

    uint32_t replacedCount = 0;

    const MicroStorage::View view = storage.view();
    auto                     it   = view.begin();
    while (it != view.end() && it.current != afterInstRef)
        ++it;
    if (it == view.end())
        return 0;
    ++it;

    for (; it != view.end(); ++it)
    {
        MicroInstr&            inst   = *it;
        const MicroInstrUseDef useDef = inst.collectUseDef(operands, nullptr);

        // Stop at control flow barriers.
        if (MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
            break;

        // Stop if toReg is redefined (replacement would change semantics).
        if (microRegSpanContains(useDef.defs, toReg))
            break;

        // Collect mutable register operand refs.
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(operands, refs, nullptr);

        bool replacedInThisInst = false;
        bool fromRegDefined     = false;
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg)
                continue;

            if (*ref.reg == fromReg && ref.def)
                fromRegDefined = true;

            if (*ref.reg == fromReg && ref.use)
            {
                *ref.reg           = toReg;
                replacedInThisInst = true;
            }
        }

        if (replacedInThisInst)
            ++replacedCount;

        // Stop if fromReg is redefined (subsequent uses see a new value).
        if (fromRegDefined)
            break;
    }

    return replacedCount;
}

namespace
{
    bool mapMicroOpToFoldOp(Math::FoldBinaryOp& outOp, bool& outIsSigned, MicroOp microOp)
    {
        outIsSigned = false;
        switch (microOp)
        {
            case MicroOp::Add:
                outOp = Math::FoldBinaryOp::Add;
                return true;
            case MicroOp::Subtract:
                outOp = Math::FoldBinaryOp::Subtract;
                return true;
            case MicroOp::MultiplySigned:
                outOp       = Math::FoldBinaryOp::Multiply;
                outIsSigned = true;
                return true;
            case MicroOp::MultiplyUnsigned:
                outOp = Math::FoldBinaryOp::Multiply;
                return true;
            case MicroOp::DivideSigned:
                outOp       = Math::FoldBinaryOp::Divide;
                outIsSigned = true;
                return true;
            case MicroOp::DivideUnsigned:
                outOp = Math::FoldBinaryOp::Divide;
                return true;
            case MicroOp::ModuloSigned:
                outOp       = Math::FoldBinaryOp::Modulo;
                outIsSigned = true;
                return true;
            case MicroOp::ModuloUnsigned:
                outOp = Math::FoldBinaryOp::Modulo;
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
                outOp       = Math::FoldBinaryOp::ShiftArithmeticRight;
                outIsSigned = true;
                return true;
            default:
                return false;
        }
    }
}

Math::FoldStatus MicroPassHelpers::foldBinaryImmediate(uint64_t&   outValue,
                                                       uint64_t    lhs,
                                                       uint64_t    rhs,
                                                       MicroOp     op,
                                                       MicroOpBits opBits)
{
    Math::FoldBinaryOp foldOp;
    bool               isSigned;
    if (!mapMicroOpToFoldOp(foldOp, isSigned, op))
        return Math::FoldStatus::Unsupported;

    const uint32_t bitWidth = getNumBits(opBits);
    if (!bitWidth)
        return Math::FoldStatus::Unsupported;

    const bool isUnsigned = !isSigned;
    ApsInt     lhsInt(static_cast<int64_t>(lhs), bitWidth, isUnsigned);
    ApsInt     rhsInt(static_cast<int64_t>(rhs), bitWidth, isUnsigned);
    ApsInt     result;

    const Math::FoldStatus status = Math::foldBinaryInt(result, lhsInt, rhsInt, foldOp);
    if (status != Math::FoldStatus::Ok)
        return status;

    outValue = result.as64() & getBitsMask(opBits);
    return Math::FoldStatus::Ok;
}

SWC_END_NAMESPACE();
