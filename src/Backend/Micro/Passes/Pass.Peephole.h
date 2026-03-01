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

    using RuleApplyMutableFn = bool (*)(MicroPeepholePass& pass, const Cursor& cursor);
    using RuleApplyConstFn   = bool (*)(const MicroPeepholePass& pass, const Cursor& cursor);

    struct Rule
    {
        RuleTarget         target       = RuleTarget::AnyInstruction;
        RuleApplyMutableFn applyMutable = nullptr;
        RuleApplyConstFn   applyConst   = nullptr;

        Rule() = default;

        Rule(const RuleTarget targetValue, const RuleApplyMutableFn applyValue) :
            target(targetValue),
            applyMutable(applyValue)
        {
        }

        Rule(const RuleTarget targetValue, const RuleApplyConstFn applyValue) :
            target(targetValue),
            applyConst(applyValue)
        {
        }

        bool apply(MicroPeepholePass& pass, const Cursor& cursor) const;
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
    struct RuleDispatch
    {
        static constexpr size_t                             K_MICRO_OPCODE_COUNT = static_cast<size_t>(MicroInstrOpcode::OpTernaryRegRegReg) + 1;
        std::array<std::vector<Rule>, K_MICRO_OPCODE_COUNT> rulesByOpcode;
    };

    void                       initRunState(MicroPassContext& context);
    static bool                isRuleApplicableToOpcode(const Rule& rule, MicroInstrOpcode opcode);
    static void                buildRules(RuleList& outRules);
    static RuleDispatch        buildRuleDispatch(const RuleList& rules);
    static const RuleDispatch& getRuleDispatch();
    bool                       applyOpcodeRules(const Cursor& cursor);
    MicroStorage::Iterator     computeResumeIterator(const MicroStorage::View& view, const MicroStorage::Iterator& prevIt, bool hasPrev, MicroInstrRef instRef, const MicroStorage::Iterator& nextIt) const;
    static void                appendAddressingRules(RuleList& outRules);
    static void                appendImmediateRules(RuleList& outRules);
    static void                appendCopyRules(RuleList& outRules);
    static void                appendCleanupRules(RuleList& outRules);

    MicroPassContext*    context_  = nullptr;
    MicroStorage*        storage_  = nullptr;
    MicroOperandStorage* operands_ = nullptr;
};

SWC_END_NAMESPACE();
