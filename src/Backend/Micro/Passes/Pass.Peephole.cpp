#include "pch.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Backend/Micro/MicroPassContext.h"

SWC_BEGIN_NAMESPACE();

bool MicroPeepholePass::Rule::apply(MicroPeepholePass& pass, const Cursor& cursor) const
{
    if (applyMutable != nullptr)
        return applyMutable(pass, cursor);

    SWC_ASSERT(applyConst != nullptr);
    return applyConst(pass, cursor);
}

void MicroPeepholePass::initRunState(MicroPassContext& context)
{
    context_  = &context;
    storage_  = context.instructions;
    operands_ = context.operands;

    rules_.clear();
    rules_.reserve(48);
    buildRules(rules_);
    ruleDispatch_ = buildRuleDispatch(rules_);
}

bool MicroPeepholePass::isRuleApplicableToOpcode(const Rule& rule, const MicroInstrOpcode opcode)
{
    switch (rule.target)
    {
        case RuleTarget::AnyInstruction:
            return true;
        case RuleTarget::LoadRegReg:
            return opcode == MicroInstrOpcode::LoadRegReg;
        case RuleTarget::LoadRegImm:
            return opcode == MicroInstrOpcode::LoadRegImm;
        case RuleTarget::LoadRegMem:
            return opcode == MicroInstrOpcode::LoadRegMem;
        case RuleTarget::OpBinaryRegImm:
            return opcode == MicroInstrOpcode::OpBinaryRegImm;
        case RuleTarget::LoadAddrRegMem:
            return opcode == MicroInstrOpcode::LoadAddrRegMem;
        case RuleTarget::LoadAddrAmcRegMem:
            return opcode == MicroInstrOpcode::LoadAddrAmcRegMem;
        case RuleTarget::LoadMemImm:
            return opcode == MicroInstrOpcode::LoadMemImm;
        default:
            return false;
    }
}

void MicroPeepholePass::buildRules(RuleList& outRules) const
{
    appendAddressingRules(outRules);
    appendImmediateRules(outRules);
    appendCopyRules(outRules);
    appendCleanupRules(outRules);
}

MicroPeepholePass::RuleDispatch MicroPeepholePass::buildRuleDispatch(const RuleList& rules)
{
    RuleDispatch dispatch;
    for (size_t opcodeIndex = 0; opcodeIndex < RuleDispatch::K_MICRO_OPCODE_COUNT; ++opcodeIndex)
    {
        const auto opcode = static_cast<MicroInstrOpcode>(opcodeIndex);
        auto&      bucket = dispatch.rulesByOpcode[opcodeIndex];
        for (const Rule& rule : rules)
        {
            if (isRuleApplicableToOpcode(rule, opcode))
                bucket.push_back(&rule);
        }
    }

    return dispatch;
}

bool MicroPeepholePass::applyOpcodeRules(const Cursor& cursor)
{
    SWC_ASSERT(cursor.inst != nullptr);

    const auto& rules = ruleDispatch_.rulesByOpcode[static_cast<size_t>(SWC_NOT_NULL(cursor.inst)->op)];
    for (const RulePtr rule : rules)
    {
        SWC_ASSERT(rule != nullptr);
        SWC_ASSERT(SWC_NOT_NULL(rule)->applyMutable != nullptr || SWC_NOT_NULL(rule)->applyConst != nullptr);
        if (SWC_NOT_NULL(rule)->apply(*this, cursor))
            return true;
    }

    return false;
}

MicroStorage::Iterator MicroPeepholePass::computeResumeIterator(const MicroStorage::View&     view,
                                                                const MicroStorage::Iterator& prevIt,
                                                                const bool                    hasPrev,
                                                                const MicroInstrRef           instRef,
                                                                const MicroStorage::Iterator& nextIt) const
{
    SWC_ASSERT(storage_ != nullptr);
    if (storage_->ptr(instRef) != nullptr)
    {
        auto currentIt = MicroStorage::Iterator{storage_, instRef};
        ++currentIt;
        return currentIt;
    }

    if (hasPrev && storage_->ptr(prevIt.current) != nullptr)
    {
        auto resumeIt = prevIt;
        ++resumeIt;
        return resumeIt;
    }

    if (nextIt != view.end() && storage_->ptr(nextIt.current) != nullptr)
        return nextIt;

    return view.begin();
}

Result MicroPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    initRunState(context);

    const MicroStorage::View view  = storage_->view();
    const auto               endIt = view.end();
    for (auto it = view.begin(); it != endIt;)
    {
        MicroStorage::Iterator prevIt  = endIt;
        const bool             hasPrev = it != view.begin();
        if (hasPrev)
        {
            prevIt = it;
            --prevIt;
        }

        const MicroInstrRef      instRef = it.current;
        MicroInstr&              inst    = *it;
        const MicroInstrOperand* ops     = inst.ops(*operands_);
        auto                     nextIt  = it;
        ++nextIt;

        Cursor cursor;
        cursor.instRef = instRef;
        cursor.inst    = &inst;
        cursor.ops     = ops;
        cursor.nextIt  = nextIt;
        cursor.endIt   = endIt;

        if (applyOpcodeRules(cursor))
        {
            context.passChanged = true;
            it                  = computeResumeIterator(view, prevIt, hasPrev, instRef, nextIt);
            continue;
        }

        it = nextIt;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
