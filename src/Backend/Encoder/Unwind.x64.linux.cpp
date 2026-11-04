#include "pch.h"
#include "Backend/Encoder/Unwind.x64.linux.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

int64_t X64UnwindLinux::adjustDistance(const int64_t distance, const int64_t amount, const bool subtract)
{
    if (distance == K_UNKNOWN)
        return K_UNKNOWN;
    if (subtract)
    {
        if ((amount > 0 && distance < INT64_MIN + amount) || (amount < 0 && distance > INT64_MAX + amount))
            return K_UNKNOWN;
        return distance - amount;
    }
    if ((amount > 0 && distance > INT64_MAX - amount) || (amount < 0 && distance < INT64_MIN - amount))
        return K_UNKNOWN;
    return distance + amount;
}

uint32_t X64UnwindLinux::registerSlot(const MicroReg reg)
{
    SWC_FORCE_ASSERT((reg.isInt() || reg.isFloat()) && reg.index() < 16);
    return reg.index() + (reg.isFloat() ? 16 : 0);
}

uint32_t X64UnwindLinux::dwarfRegister(const uint32_t slot)
{
    return X64DwarfFrame::registerNumber(slot < 16 ? MicroReg::intReg(slot) : MicroReg::floatReg(slot - 16));
}

X64UnwindLinux::State X64UnwindLinux::initialState() const
{
    State state;
    state.frameDistance.fill(K_UNKNOWN);
    state.frameDistance[K_SP] = 8;
    state.original = persistent_;
    return state;
}

void X64UnwindLinux::reset()
{
    frame_.reset();
    cursor_ = 0;
    current_ = emitted_ = initialState();
}

bool X64UnwindLinux::merge(State& into, const State& incoming)
{
    // Different recovery rules at one instruction address cannot be represented by an FDE.
    SWC_FORCE_ASSERT(into.saved == incoming.saved);
    bool changed = false;
    if (into.frameDistance[into.cfaReg] != incoming.frameDistance[into.cfaReg])
    {
        uint32_t common = incoming.cfaReg;
        if (into.frameDistance[common] != incoming.frameDistance[common])
            common = K_SP;
        SWC_FORCE_ASSERT(into.frameDistance[common] != K_UNKNOWN && into.frameDistance[common] == incoming.frameDistance[common]);
        changed = into.cfaReg != common;
        into.cfaReg = common;
    }
    for (uint32_t reg = 0; reg < into.frameDistance.size(); ++reg)
    {
        if (into.frameDistance[reg] != incoming.frameDistance[reg] && into.frameDistance[reg] != K_UNKNOWN)
        {
            into.frameDistance[reg] = K_UNKNOWN;
            changed = true;
        }
    }
    const uint32_t original = into.original & incoming.original;
    changed |= original != into.original;
    into.original = original;
    return changed;
}

void X64UnwindLinux::prepare(MicroBuilder& builder, const CallConvKind callConv, const Encoder* encoder)
{
    const CallConv& conv = CallConv::get(callConv);
    frameReg_ = conv.framePointer.index();
    persistent_ = 0;
    for (const MicroReg reg : conv.intPersistentRegs)
        persistent_ |= 1u << registerSlot(reg);
    for (const MicroReg reg : conv.floatPersistentRegs)
        persistent_ |= 1u << registerSlot(reg);
    operands_ = &builder.operands();
    encoder_ = encoder;

    const auto& graph = builder.controlFlowGraph();
    SWC_FORCE_ASSERT(!graph.hasUnsupportedControlFlowForCfgLiveness() && graph.supportsDeadCodeLiveness());
    instructions_.clear();
    blocks_.clear();
    blockOf_.resize(graph.instructionCount());
    const auto refs = graph.instructionRefs();
    for (uint32_t index = 0; index < refs.size(); ++index)
    {
        instructions_.push_back(builder.instructions().ptr(refs[index]));
        const auto& predecessors = graph.predecessors(index);
        const bool startsBlock = !index || predecessors.size() != 1 || predecessors[0] != index - 1 || graph.successors(index - 1).size() != 1;
        if (startsBlock)
        {
            if (!blocks_.empty())
                blocks_.back().end = index;
            blocks_.push_back({.first = index});
        }
        blockOf_[index] = static_cast<uint32_t>(blocks_.size() - 1);
    }
    if (blocks_.empty())
        return;
    blocks_.back().end = static_cast<uint32_t>(refs.size());
    blocks_[0].entry = initialState();
    blocks_[0].reached = blocks_[0].queued = true;
    std::vector<uint32_t> pending{0};
    while (!pending.empty())
    {
        Block& block = blocks_[pending.back()];
        pending.pop_back();
        block.queued = false;
        State state = block.entry;
        for (uint32_t index = block.first; index < block.end; ++index)
            transfer(state, *instructions_[index], instructions_[index]->ops(*operands_));
        for (const uint32_t successor : graph.successors(block.end - 1))
        {
            const uint32_t nextIndex = blockOf_[successor];
            Block& next = blocks_[nextIndex];
            const bool changed = !next.reached || merge(next.entry, state);
            if (!next.reached)
            {
                next.entry = state;
                next.reached = true;
            }
            if (changed && !next.queued)
            {
                next.queued = true;
                pending.push_back(nextIndex);
            }
        }
    }
    reset();
}

void X64UnwindLinux::transfer(State& state, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    const State before = state;
    inst.collectUseDef(useDef_, *operands_, encoder_);
    for (const MicroReg reg : useDef_.defs)
    {
        if (!reg.isInt() && !reg.isFloat())
            continue;
        state.original &= ~(1u << registerSlot(reg));
        if (reg.isInt())
            state.frameDistance[reg.index()] = K_UNKNOWN;
    }

    if (inst.op == MicroInstrOpcode::Push || inst.op == MicroInstrOpcode::Pop)
    {
        const uint32_t slot = registerSlot(ops[0].reg);
        const bool push = inst.op == MicroInstrOpcode::Push;
        const int64_t distance = before.frameDistance[K_SP];
        state.frameDistance[K_SP] = adjustDistance(distance, 8, !push);
        if (push && (before.original & (1u << slot)) && !before.saved[slot])
        {
            SWC_FORCE_ASSERT(distance != K_UNKNOWN && distance >= 0 && distance + 8 <= INT32_MAX);
            state.saved[slot] = -static_cast<int32_t>(distance + 8);
        }
        else if (!push && before.saved[slot] && distance != K_UNKNOWN && before.saved[slot] == -distance)
        {
            state.saved[slot] = 0;
            state.original |= 1u << slot;
        }
    }
    else if ((inst.op == MicroInstrOpcode::LoadRegReg || inst.op == MicroInstrOpcode::LoadAddrRegMem) && ops[0].reg.isInt() && ops[1].reg.isInt() && ops[2].opBits == MicroOpBits::B64)
    {
        const int64_t distance = before.frameDistance[ops[1].reg.index()];
        const int64_t offset = inst.op == MicroInstrOpcode::LoadAddrRegMem ? static_cast<int64_t>(ops[3].valueU64) : 0;
        state.frameDistance[ops[0].reg.index()] = adjustDistance(distance, offset, true);
        if (!offset && ops[0].reg == ops[1].reg)
            state.original |= before.original & (1u << registerSlot(ops[0].reg));
    }
    else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt() && ops[1].opBits == MicroOpBits::B64 && (ops[2].microOp == MicroOp::Add || ops[2].microOp == MicroOp::Subtract))
    {
        const uint32_t reg = ops[0].reg.index();
        const int64_t distance = before.frameDistance[reg];
        const int64_t offset = static_cast<int64_t>(ops[3].valueU64);
        state.frameDistance[reg] = adjustDistance(distance, offset, ops[2].microOp == MicroOp::Add);
    }
    else if ((inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::LoadRegMem) && (ops[2].opBits == MicroOpBits::B64 || ops[2].opBits == MicroOpBits::B128))
    {
        const bool save = inst.op == MicroInstrOpcode::LoadMemReg;
        const MicroReg base = ops[save ? 0 : 1].reg;
        const MicroReg reg = ops[save ? 1 : 0].reg;
        const uint32_t slot = registerSlot(reg);
        const int64_t distance = base.isInt() ? before.frameDistance[base.index()] : K_UNKNOWN;
        if (distance != K_UNKNOWN && (reg.isInt() || ops[2].opBits == MicroOpBits::B128))
        {
            const int64_t offset = adjustDistance(static_cast<int64_t>(ops[3].valueU64), distance, true);
            if (save && (before.original & (1u << slot)) && !before.saved[slot])
            {
                SWC_FORCE_ASSERT(offset < 0 && offset >= INT32_MIN && offset % 8 == 0);
                state.saved[slot] = static_cast<int32_t>(offset);
            }
            else if (!save && before.saved[slot] && offset == before.saved[slot])
            {
                state.saved[slot] = 0;
                state.original |= 1u << slot;
            }
        }
    }

    // Prefer the ABI frame register once established. Dynamic stack allocation and
    // probing may then change RSP without changing the canonical frame address.
    if (state.frameDistance[frameReg_] != K_UNKNOWN)
        state.cfaReg = frameReg_;
    else if (state.frameDistance[state.cfaReg] == K_UNKNOWN)
        state.cfaReg = K_SP;
    const int64_t cfaOffset = state.frameDistance[state.cfaReg];
    SWC_FORCE_ASSERT(cfaOffset >= 0 && cfaOffset <= UINT32_MAX);
}

void X64UnwindLinux::emitState(const State& state, const uint32_t codeOffset)
{
    if (state.cfaReg == emitted_.cfaReg && state.frameDistance[state.cfaReg] == emitted_.frameDistance[emitted_.cfaReg] && state.saved == emitted_.saved)
        return;
    frame_.advance(codeOffset);
    if (state.cfaReg != emitted_.cfaReg || state.frameDistance[state.cfaReg] != emitted_.frameDistance[emitted_.cfaReg])
        frame_.defineCfa(dwarfRegister(state.cfaReg), static_cast<uint32_t>(state.frameDistance[state.cfaReg]));
    for (uint32_t slot = 0; slot < state.saved.size(); ++slot)
    {
        if (state.saved[slot] == emitted_.saved[slot])
            continue;
        if (state.saved[slot])
            frame_.saveRegister(dwarfRegister(slot), state.saved[slot]);
        else
            frame_.restoreRegister(dwarfRegister(slot));
    }
    emitted_ = state;
}

void X64UnwindLinux::onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeStartOffset, const uint32_t codeEndOffset)
{
    // Embedded jump tables have no executable callback. The CFG already excludes their bytes.
    while (cursor_ < instructions_.size() && instructions_[cursor_]->op == MicroInstrOpcode::JumpTableData)
        ++cursor_;
    SWC_FORCE_ASSERT(cursor_ < instructions_.size() && instructions_[cursor_] == &inst);
    const Block& block = blocks_[blockOf_[cursor_]];
    if (block.reached)
    {
        if (cursor_ == block.first)
            current_ = block.entry;
        emitState(current_, codeStartOffset);
        transfer(current_, inst, ops);
        emitState(current_, codeEndOffset);
    }
    ++cursor_;
}

void X64UnwindLinux::buildInfo(ByteArray& outUnwindInfo, const uint32_t codeSize) const
{
    SWC_FORCE_ASSERT(!instructions_.empty());
    frame_.build(outUnwindInfo, codeSize);
}

SWC_END_NAMESPACE();
