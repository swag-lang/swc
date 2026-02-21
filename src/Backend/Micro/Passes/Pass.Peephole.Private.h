#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    struct Cursor
    {
        Ref                      instRef;
        MicroInstr*              inst;
        const MicroInstrOperand* ops;
        MicroStorage::Iterator   nextIt;
        MicroStorage::Iterator   endIt;
    };

    enum class RuleTarget : uint8_t
    {
        AnyInstruction,
        LoadRegReg,
        LoadRegImm,
        OpBinaryRegImm,
        LoadAddrRegMem,
        LoadAddrAmcRegMem,
        LoadMemImm,
    };

    using RuleApplyFn = bool (*)(const MicroPassContext& context, const Cursor& cursor);

    struct Rule
    {
        RuleTarget       target;
        RuleApplyFn      apply;
    };

    using RuleList = std::vector<Rule>;

    bool isCopyDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg);
    bool isTempDeadForAddressFold(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg);
    bool areFlagsDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt);

    void appendAddressingRules(RuleList& outRules);
    void appendImmediateRules(RuleList& outRules);
    void appendCopyRules(RuleList& outRules);
    void appendCleanupRules(RuleList& outRules);
}

SWC_END_NAMESPACE();
