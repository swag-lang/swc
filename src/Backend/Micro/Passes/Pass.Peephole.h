#pragma once
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;

class MicroPeepholePass final : public MicroPass
{
public:
    struct Cursor
    {
        MicroInstrRef            instRef;
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
        LoadRegMem,
        OpBinaryRegImm,
        LoadAddrRegMem,
        LoadAddrAmcRegMem,
        LoadMemImm,
    };

    using RuleApplyFn = bool (*)(MicroPeepholePass& pass, const Cursor& cursor);

    struct Rule
    {
        RuleTarget  target;
        RuleApplyFn apply;
    };

    using RuleList = std::vector<Rule>;

    std::string_view name() const override { return "peephole"; }
    Result           run(MicroPassContext& context) override;

    const MicroPassContext& context() const
    {
        SWC_ASSERT(context_ != nullptr);
        return *context_;
    }

    bool isCopyDeadAfterInstruction(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg) const;
    bool isTempDeadForAddressFold(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg) const;
    bool isRegUnusedAfterInstruction(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg) const;
    bool areFlagsDeadAfterInstruction(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt) const;

private:
    using RulePtr = const Rule*;

    struct RuleDispatch
    {
        static constexpr size_t                                K_MICRO_OPCODE_COUNT = static_cast<size_t>(MicroInstrOpcode::OpTernaryRegRegReg) + 1;
        std::array<std::vector<RulePtr>, K_MICRO_OPCODE_COUNT> rulesByOpcode;
    };

    void                   initRunState(MicroPassContext& context);
    static bool            isRuleApplicableToOpcode(const Rule& rule, MicroInstrOpcode opcode);
    void                   buildRules(RuleList& outRules) const;
    static RuleDispatch    buildRuleDispatch(const RuleList& rules);
    bool                   applyOpcodeRules(const Cursor& cursor);
    MicroStorage::Iterator computeResumeIterator(const MicroStorage::View& view, const MicroStorage::Iterator& prevIt, bool hasPrev, MicroInstrRef instRef, const MicroStorage::Iterator& nextIt) const;
    void                   appendAddressingRules(RuleList& outRules) const;
    void                   appendImmediateRules(RuleList& outRules) const;
    void                   appendCopyRules(RuleList& outRules) const;
    void                   appendCleanupRules(RuleList& outRules) const;

    MicroPassContext*    context_  = nullptr;
    MicroStorage*        storage_  = nullptr;
    MicroOperandStorage* operands_ = nullptr;
    RuleList             rules_;
    RuleDispatch         ruleDispatch_;
};

SWC_END_NAMESPACE();
