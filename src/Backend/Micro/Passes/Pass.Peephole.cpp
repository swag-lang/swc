#include "pch.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using RulePtr = const PeepholePass::Rule*;

    constexpr size_t K_MICRO_OPCODE_COUNT = static_cast<size_t>(MicroInstrOpcode::OpTernaryRegRegReg) + 1;

    bool isRuleApplicableToOpcode(const PeepholePass::Rule& rule, MicroInstrOpcode opcode)
    {
        switch (rule.target)
        {
            case PeepholePass::RuleTarget::AnyInstruction:
                return true;
            case PeepholePass::RuleTarget::LoadRegReg:
                return opcode == MicroInstrOpcode::LoadRegReg;
            case PeepholePass::RuleTarget::LoadRegImm:
                return opcode == MicroInstrOpcode::LoadRegImm;
            case PeepholePass::RuleTarget::LoadRegMem:
                return opcode == MicroInstrOpcode::LoadRegMem;
            case PeepholePass::RuleTarget::OpBinaryRegImm:
                return opcode == MicroInstrOpcode::OpBinaryRegImm;
            case PeepholePass::RuleTarget::LoadAddrRegMem:
                return opcode == MicroInstrOpcode::LoadAddrRegMem;
            case PeepholePass::RuleTarget::LoadAddrAmcRegMem:
                return opcode == MicroInstrOpcode::LoadAddrAmcRegMem;
            case PeepholePass::RuleTarget::LoadMemImm:
                return opcode == MicroInstrOpcode::LoadMemImm;
            default:
                return false;
        }
    }

    struct PeepholeRuleDispatch
    {
        std::array<std::vector<RulePtr>, K_MICRO_OPCODE_COUNT> rulesByOpcode;
    };

    PeepholePass::RuleList buildPeepholeRules()
    {
        PeepholePass::RuleList rules;
        rules.reserve(48);

        PeepholePass::appendAddressingRules(rules);
        PeepholePass::appendImmediateRules(rules);
        PeepholePass::appendCopyRules(rules);
        PeepholePass::appendCleanupRules(rules);

        return rules;
    }

    const PeepholePass::RuleList& peepholeRules()
    {
        static const PeepholePass::RuleList RULES = buildPeepholeRules();
        return RULES;
    }

    PeepholeRuleDispatch buildPeepholeRuleDispatch()
    {
        PeepholeRuleDispatch          dispatch;
        const PeepholePass::RuleList& rules = peepholeRules();
        for (size_t opcodeIndex = 0; opcodeIndex < K_MICRO_OPCODE_COUNT; ++opcodeIndex)
        {
            const auto opcode = static_cast<MicroInstrOpcode>(opcodeIndex);
            auto&      bucket = dispatch.rulesByOpcode[opcodeIndex];
            for (const PeepholePass::Rule& rule : rules)
            {
                if (isRuleApplicableToOpcode(rule, opcode))
                    bucket.push_back(&rule);
            }
        }

        return dispatch;
    }

    const std::vector<RulePtr>& peepholeRulesForOpcode(MicroInstrOpcode opcode)
    {
        static const PeepholeRuleDispatch DISPATCH = buildPeepholeRuleDispatch();
        return DISPATCH.rulesByOpcode[static_cast<size_t>(opcode)];
    }

    bool applyOpcodeRules(const MicroPassContext& context, const PeepholePass::Cursor& cursor)
    {
        SWC_ASSERT(cursor.inst != nullptr);
        const auto& rules = peepholeRulesForOpcode(SWC_NOT_NULL(cursor.inst)->op);
        for (const RulePtr rule : rules)
        {
            SWC_ASSERT(rule != nullptr);
            SWC_ASSERT(SWC_NOT_NULL(rule)->apply != nullptr);
            if (SWC_NOT_NULL(rule)->apply(context, cursor))
                return true;
        }

        return false;
    }

    MicroStorage::Iterator computeResumeIterator(const MicroPassContext& context, const MicroStorage::View& view, const MicroStorage::Iterator& prevIt, bool hasPrev, MicroInstrRef instRef, const MicroStorage::Iterator& nextIt)
    {
        SWC_ASSERT(context.instructions != nullptr);
        auto& storage = *SWC_NOT_NULL(context.instructions);

        if (storage.ptr(instRef) != nullptr)
        {
            auto currentIt = MicroStorage::Iterator{&storage, instRef};
            ++currentIt;
            return currentIt;
        }

        if (hasPrev && storage.ptr(prevIt.current) != nullptr)
        {
            auto resumeIt = prevIt;
            ++resumeIt;
            return resumeIt;
        }

        if (nextIt != view.end() && storage.ptr(nextIt.current) != nullptr)
            return nextIt;

        return view.begin();
    }
}

Result MicroPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    bool changed = false;

    const MicroStorage::View view  = context.instructions->view();
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
        const MicroInstrOperand* ops     = inst.ops(*SWC_NOT_NULL(context.operands));
        auto                     nextIt  = it;
        ++nextIt;

        PeepholePass::Cursor cursor;
        cursor.instRef = instRef;
        cursor.inst    = &inst;
        cursor.ops     = ops;
        cursor.nextIt  = nextIt;
        cursor.endIt   = endIt;

        if (applyOpcodeRules(context, cursor))
        {
            changed = true;
            it      = computeResumeIterator(context, view, prevIt, hasPrev, instRef, nextIt);
            continue;
        }

        it = nextIt;
    }

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
