#include "pch.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isRuleApplicable(const PeepholePass::Rule& rule, const PeepholePass::Cursor& cursor)
    {
        switch (rule.target)
        {
            case PeepholePass::RuleTarget::AnyInstruction:
                return true;
            case PeepholePass::RuleTarget::LoadRegReg:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::LoadRegReg;
            case PeepholePass::RuleTarget::LoadRegImm:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::LoadRegImm;
            case PeepholePass::RuleTarget::OpBinaryRegImm:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::OpBinaryRegImm;
            case PeepholePass::RuleTarget::LoadAddrRegMem:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::LoadAddrRegMem;
            case PeepholePass::RuleTarget::LoadAddrAmcRegMem:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::LoadAddrAmcRegMem;
            case PeepholePass::RuleTarget::LoadMemImm:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::LoadMemImm;
            default:
                return false;
        }
    }

    PeepholePass::RuleList buildPeepholeRules()
    {
        PeepholePass::RuleList rules;
        rules.reserve(18);

        PeepholePass::appendAddressingRules(rules);
        PeepholePass::appendImmediateRules(rules);
        PeepholePass::appendCopyRules(rules);
        PeepholePass::appendCleanupRules(rules);

        return rules;
    }

    const PeepholePass::RuleList& peepholeRules()
    {
        static const PeepholePass::RuleList rules = buildPeepholeRules();
        return rules;
    }

    bool applyRule(const MicroPassContext& context, const PeepholePass::Rule& rule, const PeepholePass::Cursor& cursor)
    {
        if (!isRuleApplicable(rule, cursor))
            return false;

        return SWC_CHECK_NOT_NULL(rule.apply)(context, cursor);
    }
}

bool MicroPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    bool changed = false;

    const MicroStorage::View view = context.instructions->view();
    for (auto it = view.begin(); it != view.end();)
    {
        const Ref                instRef = it.current;
        MicroInstr&              inst    = *it;
        const MicroInstrOperand* ops     = inst.ops(*context.operands);
        auto                     nextIt  = it;
        ++nextIt;

        PeepholePass::Cursor cursor;
        cursor.instRef = instRef;
        cursor.inst    = &inst;
        cursor.ops     = ops;
        cursor.nextIt  = nextIt;
        cursor.endIt   = view.end();

        bool appliedRule = false;
        for (const PeepholePass::Rule& rule : peepholeRules())
        {
            if (!applyRule(context, rule, cursor))
                continue;

            changed     = true;
            appliedRule = true;
            break;
        }

        if (appliedRule)
        {
            if (nextIt == view.end() || context.instructions->ptr(nextIt.current) != nullptr)
                it = nextIt;
            else
                it = view.begin();
            continue;
        }

        it = nextIt;
    }

    return changed;
}

SWC_END_NAMESPACE();
