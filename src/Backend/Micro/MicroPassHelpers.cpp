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

bool MicroPassHelpers::instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    const MicroInstrDef& info = MicroInstr::info(inst.op);
    if (!info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
        return false;

    if ((inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm) &&
        ops &&
        ops[0].cpuCond == MicroCond::Unconditional)
    {
        return false;
    }

    return true;
}

bool MicroPassHelpers::areCpuFlagsDeadAfter(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstrRef afterRef)
{
    for (MicroInstrRef scanRef = storage.findNextInstructionRef(afterRef); scanRef.isValid(); scanRef = storage.findNextInstructionRef(scanRef))
    {
        const MicroInstr* scanInst = storage.ptr(scanRef);
        if (!scanInst)
            return false;

        const MicroInstrOperand* scanOps = scanInst->ops(operands);
        if (instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            return false;

        const MicroInstrDef& info = MicroInstr::info(scanInst->op);
        if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags) ||
            info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
            info.flags.has(MicroInstrFlagsE::JumpInstruction))
        {
            return true;
        }
    }

    return true;
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

    const bool   isUnsigned = !isSigned;
    const ApsInt lhsInt(static_cast<int64_t>(lhs), bitWidth, isUnsigned);
    const ApsInt rhsInt(static_cast<int64_t>(rhs), bitWidth, isUnsigned);
    ApsInt       result;

    const Math::FoldStatus status = Math::foldBinaryInt(result, lhsInt, rhsInt, foldOp);
    if (status != Math::FoldStatus::Ok)
        return status;

    outValue = result.as64() & getBitsMask(opBits);
    return Math::FoldStatus::Ok;
}

namespace
{
    bool tryFoldAddSub(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm)
    {
        const uint64_t mask        = getBitsMask(opBits);
        const uint64_t a           = firstImm & mask;
        const uint64_t b           = secondImm & mask;
        const bool     firstIsSub  = firstOp == MicroOp::Subtract;
        const bool     secondIsSub = secondOp == MicroOp::Subtract;

        uint64_t addImm = 0;
        if (firstIsSub == secondIsSub)
            addImm = firstIsSub ? ((0u - (a + b)) & mask) : ((a + b) & mask);
        else if (firstIsSub)
            addImm = (b - a) & mask;
        else
            addImm = (a - b) & mask;

        const uint64_t subImm = (0u - addImm) & mask;
        if (addImm <= subImm)
        {
            outOp  = MicroOp::Add;
            outImm = addImm;
        }
        else
        {
            outOp  = MicroOp::Subtract;
            outImm = subImm;
        }
        return true;
    }

    bool foldSameBitwise(MicroOp op, uint64_t lhs, uint64_t rhs, MicroOpBits opBits, uint64_t& outImm)
    {
        uint64_t   value  = 0;
        const auto status = MicroPassHelpers::foldBinaryImmediate(value, lhs, rhs, op, opBits);
        if (status != Math::FoldStatus::Ok)
            return false;
        outImm = value & getBitsMask(opBits);
        return true;
    }
}

bool MicroPassHelpers::tryReassociateBinaryImmediate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm)
{
    const bool firstIsAddSub  = firstOp == MicroOp::Add || firstOp == MicroOp::Subtract;
    const bool secondIsAddSub = secondOp == MicroOp::Add || secondOp == MicroOp::Subtract;
    if (firstIsAddSub && secondIsAddSub)
        return tryFoldAddSub(firstOp, firstImm, secondOp, secondImm, opBits, outOp, outImm);

    if (firstOp != secondOp)
        return false;

    switch (firstOp)
    {
        case MicroOp::And:
        case MicroOp::Or:
        case MicroOp::Xor:
        case MicroOp::MultiplySigned:
        case MicroOp::MultiplyUnsigned:
            outOp = firstOp;
            return foldSameBitwise(firstOp, firstImm, secondImm, opBits, outImm);

        case MicroOp::ShiftLeft:
        case MicroOp::ShiftRight:
        case MicroOp::ShiftArithmeticRight:
        {
            const uint64_t sum = firstImm + secondImm;
            if (sum >= getNumBits(opBits))
                return false;
            outOp  = firstOp;
            outImm = sum;
            return true;
        }

        default:
            return false;
    }
}

SWC_END_NAMESPACE();
