#include "pch.h"
#include "Backend/Micro/Passes/Pass.StackAdjustNormalize.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct StackAdjustInfo
    {
        MicroOp  op     = MicroOp::Add;
        uint64_t amount = 0;
    };

    struct AnalyzeResult
    {
        std::unordered_map<uint32_t, uint64_t> depthBeforeByRef;
        std::vector<MicroInstrRef>             stackAdjustRefs;
        uint64_t                               frameSize = 0;
    };

    bool tryParseStackAdjust(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, StackAdjustInfo& outInfo)
    {
        outInfo = {};
        if (!ops || inst.op != MicroInstrOpcode::OpBinaryRegImm || inst.numOperands < 4)
            return false;
        if (ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64)
            return false;
        if (ops[2].microOp != MicroOp::Subtract && ops[2].microOp != MicroOp::Add)
            return false;

        const ApInt immediate = ops[3].immediateValue(64);
        if (!immediate.fit64())
            return false;

        const uint64_t amount = immediate.as64();
        if (!amount)
            return false;

        outInfo.op     = ops[2].microOp;
        outInfo.amount = amount;
        return true;
    }

    bool tryGetJumpTargetLabelId(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t& outLabelId)
    {
        outLabelId = 0;
        if (!ops || inst.numOperands < 3)
            return false;
        if (inst.op != MicroInstrOpcode::JumpCond && inst.op != MicroInstrOpcode::JumpCondImm)
            return false;
        if (ops[2].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[2].valueU64);
        return true;
    }

    void mergeLabelDepth(std::unordered_map<uint32_t, uint64_t>& labelDepthById, uint32_t labelId, uint64_t depth)
    {
        const auto it = labelDepthById.find(labelId);
        if (it == labelDepthById.end())
        {
            labelDepthById.emplace(labelId, depth);
            return;
        }

        if (it->second != depth)
            return;
    }

    bool tryAddOffset(uint64_t& value, uint64_t delta, bool apply)
    {
        if (!delta)
            return true;
        if (value > std::numeric_limits<uint64_t>::max() - delta)
            return false;
        if (apply)
            value += delta;
        return true;
    }

    bool rebaseInstructionStackOffsets(const MicroInstr& inst, MicroInstrOperand* ops, MicroReg stackPointer, uint64_t delta, bool apply)
    {
        if (!ops || !delta)
            return true;

        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        {
            if (info.memBaseOperandIndex < inst.numOperands && info.memOffsetOperandIndex < inst.numOperands && ops[info.memBaseOperandIndex].reg == stackPointer)
            {
                if (!tryAddOffset(ops[info.memOffsetOperandIndex].valueU64, delta, apply))
                    return false;
            }
        }

        uint8_t amcBaseIndex = 0;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                amcBaseIndex = 1;
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
                amcBaseIndex = 0;
                break;

            default:
                return true;
        }

        if (inst.numOperands < 7)
            return true;
        if (ops[amcBaseIndex].reg != stackPointer)
            return true;
        return tryAddOffset(ops[6].valueU64, delta, apply);
    }

    bool parseStackPointerCopyForRebase(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroReg& outDstReg)
    {
        outDstReg = MicroReg::invalid();

        if (!ops || inst.op != MicroInstrOpcode::LoadRegReg || inst.numOperands < 3)
            return true;
        if (ops[1].reg != stackPointer)
            return true;
        if (ops[0].reg == stackPointer)
            return true;
        if (ops[2].opBits != MicroOpBits::B64)
            return false;

        outDstReg = ops[0].reg;
        return true;
    }

    bool analyzeFunctionStackAdjustments(const MicroPassContext& context, const CallConv& conv, AnalyzeResult& outResult)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        outResult = {};
        outResult.depthBeforeByRef.reserve(context.instructions->count() * 2 + 1);
        outResult.stackAdjustRefs.reserve(context.instructions->count() / 4 + 1);

        std::unordered_map<uint32_t, uint64_t> labelDepthById;
        labelDepthById.reserve(context.instructions->count() / 8 + 1);

        uint64_t depth = 0;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            const MicroInstrOperand* const ops = it->ops(*context.operands);

            if (it->op == MicroInstrOpcode::Label && it->numOperands >= 1 && ops && ops[0].valueU64 <= std::numeric_limits<uint32_t>::max())
            {
                const uint32_t labelId = static_cast<uint32_t>(ops[0].valueU64);
                const auto     labelIt = labelDepthById.find(labelId);
                if (labelIt != labelDepthById.end())
                    depth = labelIt->second;
            }

            outResult.depthBeforeByRef[it.current.get()] = depth;
            outResult.frameSize                          = std::max(outResult.frameSize, depth);

            StackAdjustInfo adjustInfo;
            if (tryParseStackAdjust(*it, ops, conv.stackPointer, adjustInfo))
            {
                outResult.stackAdjustRefs.push_back(it.current);
                if (adjustInfo.op == MicroOp::Subtract)
                {
                    if (depth > std::numeric_limits<uint64_t>::max() - adjustInfo.amount)
                        return false;

                    depth += adjustInfo.amount;
                    outResult.frameSize = std::max(outResult.frameSize, depth);
                }
                else
                {
                    if (depth < adjustInfo.amount)
                        return false;

                    depth -= adjustInfo.amount;
                }
            }

            uint32_t jumpLabelId = 0;
            if (tryGetJumpTargetLabelId(*it, ops, jumpLabelId))
                mergeLabelDepth(labelDepthById, jumpLabelId, depth);
        }

        return true;
    }

    bool validateOffsetRebase(const MicroPassContext& context, const AnalyzeResult& analysisResult, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            const auto depthIt = analysisResult.depthBeforeByRef.find(it.current.get());
            if (depthIt == analysisResult.depthBeforeByRef.end())
                continue;
            if (analysisResult.frameSize < depthIt->second)
                return false;

            const uint64_t delta = analysisResult.frameSize - depthIt->second;
            if (!delta)
                continue;

            auto nextIt = it;
            ++nextIt;

            MicroInstrOperand* const ops = it->ops(*context.operands);
            if (!rebaseInstructionStackOffsets(*it, ops, conv.stackPointer, delta, false))
                return false;

            MicroReg copiedStackReg = MicroReg::invalid();
            if (!parseStackPointerCopyForRebase(*it, ops, conv.stackPointer, copiedStackReg))
                return false;
            if (copiedStackReg.isValid() && nextIt == context.instructions->view().end())
                return false;
        }

        return true;
    }

    void applyOffsetRebase(const MicroPassContext& context, const AnalyzeResult& analysisResult, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        auto it = context.instructions->view().begin();
        while (it != context.instructions->view().end())
        {
            auto currentIt = it;
            ++it;

            auto nextIt = currentIt;
            ++nextIt;

            const auto depthIt = analysisResult.depthBeforeByRef.find(currentIt.current.get());
            if (depthIt == analysisResult.depthBeforeByRef.end())
                continue;
            if (analysisResult.frameSize < depthIt->second)
                continue;

            const uint64_t delta = analysisResult.frameSize - depthIt->second;
            if (!delta)
                continue;

            MicroInstrOperand* const ops = currentIt->ops(*context.operands);
            SWC_ASSERT(rebaseInstructionStackOffsets(*currentIt, ops, conv.stackPointer, delta, true));

            MicroReg copiedStackReg = MicroReg::invalid();
            const bool parseOk = parseStackPointerCopyForRebase(*currentIt, ops, conv.stackPointer, copiedStackReg);
            SWC_ASSERT(parseOk);
            if (!parseOk)
                continue;
            if (!copiedStackReg.isValid())
                continue;

            SWC_ASSERT(nextIt != context.instructions->view().end());
            if (nextIt == context.instructions->view().end())
                continue;

            MicroInstrOperand addOps[4];
            addOps[0].reg      = copiedStackReg;
            addOps[1].opBits   = MicroOpBits::B64;
            addOps[2].microOp  = MicroOp::Add;
            addOps[3].valueU64 = delta;
            context.instructions->insertBefore(*context.operands, nextIt.current, MicroInstrOpcode::OpBinaryRegImm, addOps);
        }
    }
}

Result MicroStackAdjustNormalizePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    const CallConv& conv = CallConv::get(context.callConvKind);

    AnalyzeResult analysisResult;
    if (!analyzeFunctionStackAdjustments(context, conv, analysisResult))
        return Result::Continue;
    if (analysisResult.stackAdjustRefs.empty())
        return Result::Continue;
    if (!analysisResult.frameSize)
        return Result::Continue;
    if (!validateOffsetRebase(context, analysisResult, conv))
        return Result::Continue;

    applyOffsetRebase(context, analysisResult, conv);

    for (const MicroInstrRef adjustRef : analysisResult.stackAdjustRefs)
        context.instructions->erase(adjustRef);

    const auto beginIt = context.instructions->view().begin();
    if (beginIt == context.instructions->view().end())
        return Result::Continue;

    std::vector<MicroInstrRef> retRefs;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        if (it->op == MicroInstrOpcode::Ret)
            retRefs.push_back(it.current);
    }

    MicroInstrOperand subOps[4];
    subOps[0].reg      = conv.stackPointer;
    subOps[1].opBits   = MicroOpBits::B64;
    subOps[2].microOp  = MicroOp::Subtract;
    subOps[3].valueU64 = analysisResult.frameSize;
    context.instructions->insertBefore(*context.operands, beginIt.current, MicroInstrOpcode::OpBinaryRegImm, subOps);

    for (const MicroInstrRef retRef : retRefs)
    {
        if (!context.instructions->ptr(retRef))
            continue;

        MicroInstrOperand addOps[4];
        addOps[0].reg      = conv.stackPointer;
        addOps[1].opBits   = MicroOpBits::B64;
        addOps[2].microOp  = MicroOp::Add;
        addOps[3].valueU64 = analysisResult.frameSize;
        context.instructions->insertBefore(*context.operands, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
    }

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
