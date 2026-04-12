#include "pch.h"
#include "Backend/Micro/MicroVerify.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Support/Memory/MemoryProfile.h"

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
    context_                      = &context;
    storage_                      = context.instructions;
    operands_                     = context.operands;
    equivalentStackBasesComputed_ = false;
    equivalentStackBasesValue_    = false;
    structuralHashKnown_          = false;
    structuralHashValue_          = 0;
}

bool MicroPeepholePass::hasEquivalentStackBases() const
{
    if (!equivalentStackBasesComputed_)
    {
        equivalentStackBasesValue_    = computeEquivalentStackBases(*context_);
        equivalentStackBasesComputed_ = true;
    }

    return equivalentStackBasesValue_;
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
        case RuleTarget::LoadMemReg:
            return opcode == MicroInstrOpcode::LoadMemReg;
        case RuleTarget::StackWriteCandidate:
            return opcode == MicroInstrOpcode::LoadMemReg ||
                   opcode == MicroInstrOpcode::LoadMemImm ||
                   opcode == MicroInstrOpcode::OpUnaryMem ||
                   opcode == MicroInstrOpcode::OpBinaryMemReg ||
                   opcode == MicroInstrOpcode::OpBinaryMemImm;
        case RuleTarget::CmpRegImm:
            return opcode == MicroInstrOpcode::CmpRegImm;
        case RuleTarget::CmpAny:
            return opcode == MicroInstrOpcode::CmpRegImm ||
                   opcode == MicroInstrOpcode::CmpRegReg ||
                   opcode == MicroInstrOpcode::CmpMemImm ||
                   opcode == MicroInstrOpcode::CmpMemReg;
        case RuleTarget::SetCondReg:
            return opcode == MicroInstrOpcode::SetCondReg;
        case RuleTarget::ClearReg:
            return opcode == MicroInstrOpcode::ClearReg;
        case RuleTarget::Push:
            return opcode == MicroInstrOpcode::Push;
        default:
            return false;
    }
}

void MicroPeepholePass::buildRules(RuleList& outRules)
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
                bucket.push_back(rule);
        }
    }

    return dispatch;
}

MicroPeepholePass::RuleDispatch MicroPeepholePass::makeDefaultRuleDispatch()
{
    RuleList rules;
    rules.reserve(48);
    buildRules(rules);
    return buildRuleDispatch(rules);
}

const MicroPeepholePass::RuleDispatch& MicroPeepholePass::getRuleDispatch()
{
    static const RuleDispatch DISPATCH = makeDefaultRuleDispatch();
    return DISPATCH;
}

Result MicroPeepholePass::failRuleInvariant(const Rule& rule, const Cursor& cursor, std::string_view message) const
{
    const char* ruleName = rule.name ? rule.name : "<unnamed-rule>";
    SWC_ASSERT(context_ != nullptr);
    return MicroVerify::reportError(*context_,
                                    std::format("peephole rule {} on opcode {} (ref={})",
                                                ruleName,
                                                cursor.inst ? static_cast<uint32_t>(cursor.inst->op) : std::numeric_limits<uint32_t>::max(),
                                                cursor.instRef.get()),
                                    message);
}

Result MicroPeepholePass::applyOpcodeRules(bool& outChanged, const Cursor& cursor)
{
    SWC_ASSERT(cursor.inst != nullptr);
    outChanged = false;

    const auto& rules = getRuleDispatch().rulesByOpcode[static_cast<size_t>((cursor.inst)->op)];
    for (const Rule& rule : rules)
    {
        SWC_ASSERT(rule.applyMutable != nullptr || rule.applyConst != nullptr);

#if SWC_DEV_MODE
        const bool shouldVerify = MicroVerify::isEnabled(context());
        uint64_t   structuralHashBefore = 0;
        if (shouldVerify)
        {
            if (!structuralHashKnown_)
            {
                structuralHashValue_ = MicroVerify::computeStructuralHash(context());
                structuralHashKnown_ = true;
            }

            structuralHashBefore = structuralHashValue_;
        }
#endif

        const bool ruleChanged = rule.apply(*this, cursor);

#if SWC_DEV_MODE
        if (shouldVerify)
        {
            const uint64_t structuralHashAfter = MicroVerify::computeStructuralHash(context());
            if (!ruleChanged && structuralHashAfter != structuralHashBefore)
                return failRuleInvariant(rule, cursor, "mutated micro state while returning false");
            if (ruleChanged && structuralHashAfter == structuralHashBefore)
                return failRuleInvariant(rule, cursor, "reported success without an observable micro-state change");

            structuralHashValue_ = structuralHashAfter;
            structuralHashKnown_ = true;
        }
#endif

        if (ruleChanged)
        {
            outChanged = true;
            return Result::Continue;
        }
    }

    return Result::Continue;
}

MicroStorage::Iterator MicroPeepholePass::computeResumeIterator(const MicroStorage::View&     view,
                                                                const MicroStorage::Iterator& prevIt,
                                                                const bool                    hasPrev,
                                                                const MicroInstrRef           instRef,
                                                                const MicroStorage::Iterator& nextIt) const
{
    SWC_ASSERT(storage_ != nullptr);
    if (hasPrev && storage_->ptr(prevIt.current) != nullptr)
        return prevIt;

    if (storage_->ptr(instRef) != nullptr)
        return MicroStorage::Iterator{storage_, instRef};

    if (nextIt != view.end() && storage_->ptr(nextIt.current) != nullptr)
        return nextIt;

    return view.begin();
}

bool MicroPeepholePass::isStackSlotDefinitelyRead(const uint64_t offset, const uint32_t size) const
{
    for (const auto& [readOffset, readSize] : stackReadRanges_)
    {
        if (MicroPassHelpers::rangesOverlap(offset, size, readOffset, readSize))
            return true;
    }

    return false;
}

bool MicroPeepholePass::hasCallAfterInstruction(const MicroInstrRef instRef) const
{
    if (!hasAnyCall_)
        return false;

    const uint32_t idx = instRef.get();
    if (idx >= instrSeqNum_.size())
        return false;

    return instrSeqNum_[idx] < lastCallSeqNum_;
}

Result MicroPeepholePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/Peephole");
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    initRunState(context);
    precomputeStackSlotInfo();

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
        cursor.curIt   = it;
        cursor.nextIt  = nextIt;
        cursor.endIt   = endIt;

        bool changed = false;
        SWC_RESULT(applyOpcodeRules(changed, cursor));
        if (changed)
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
