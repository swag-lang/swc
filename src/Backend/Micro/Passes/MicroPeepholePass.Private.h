#pragma once
#include "Backend/Micro/Passes/MicroPeepholePass.h"
#include "Backend/Micro/MicroInstr.h"

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
        LoadAddrRegMem,
        LoadMemImm,
    };

    using RuleMatchFn   = bool (*)(const MicroPassContext& context, const Cursor& cursor);
    using RuleRewriteFn = bool (*)(const MicroPassContext& context, const Cursor& cursor);

    struct Rule
    {
        std::string_view name;
        RuleTarget       target;
        RuleMatchFn      match;
        RuleRewriteFn    rewrite;
    };

    using RuleList = std::vector<Rule>;

    bool isCopyDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg);
    bool isTempDeadForAddressFold(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg);
    bool areFlagsDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt);
    bool getMemBaseOffsetOperandIndices(uint8_t& outBaseIndex, uint8_t& outOffsetIndex, const MicroInstr& inst);

    void appendAddressingRules(RuleList& outRules);
    void appendImmediateRules(RuleList& outRules);
    void appendCopyRules(RuleList& outRules);
    void appendCleanupRules(RuleList& outRules);
}

SWC_END_NAMESPACE();
