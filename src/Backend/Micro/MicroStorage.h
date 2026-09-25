#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Support/Core/RefTypes.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class MicroOperandStorage
{
public:
    uint32_t                                       count() const noexcept;
    size_t                                         allocatedBytes() const noexcept;
    void                                           clear() noexcept;
    std::pair<MicroOperandRef, MicroInstrOperand*> emplaceUninitArray(uint32_t count);
    MicroInstrOperand*                             ptr(MicroOperandRef ref) noexcept;
    const MicroInstrOperand*                       ptr(MicroOperandRef ref) const noexcept;

private:
    std::vector<MicroInstrOperand> operands_;
};

inline MicroInstrOperand* MicroOperandStorage::ptr(const MicroOperandRef ref) noexcept
{
    SWC_ASSERT(ref.get() < operands_.size());
    return operands_.data() + ref.get();
}

inline const MicroInstrOperand* MicroOperandStorage::ptr(const MicroOperandRef ref) const noexcept
{
    SWC_ASSERT(ref.get() < operands_.size());
    return operands_.data() + ref.get();
}

inline MicroInstrOperand* MicroInstr::ops(MicroOperandStorage& operands) const
{
    if (!numOperands)
        return nullptr;
    return operands.ptr(opsRef);
}

inline const MicroInstrOperand* MicroInstr::ops(const MicroOperandStorage& operands) const
{
    if (!numOperands)
        return nullptr;
    return operands.ptr(opsRef);
}

inline void MicroInstr::collectRegOperands(MicroOperandStorage& operands, MicroInstrRegOperandRefs& out, const Encoder*) const
{
    MicroInstrOperand* instructionOps = ops(operands);
    if (!instructionOps)
        return;

    const auto modes = info(op).resolvedRegModes(instructionOps);
    for (size_t i = 0; i < modes.size(); ++i)
    {
        const MicroInstrRegMode mode = modes[i];
        if (mode != MicroInstrRegMode::Use && mode != MicroInstrRegMode::Def && mode != MicroInstrRegMode::UseDef)
            continue;
        MicroReg* reg = &instructionOps[i].reg;
        if (!reg->isValid() || reg->isNoBase())
            continue;
        out.push_back({reg, mode == MicroInstrRegMode::Use || mode == MicroInstrRegMode::UseDef,
                       mode == MicroInstrRegMode::Def || mode == MicroInstrRegMode::UseDef});
    }
}

class MicroStorage
{
public:
    struct Iterator
    {
        using iterator_concept  = std::bidirectional_iterator_tag;
        using iterator_category = std::bidirectional_iterator_tag;
        using value_type        = MicroInstr;
        using difference_type   = std::ptrdiff_t;
        using pointer           = MicroInstr*;
        using reference         = MicroInstr&;

        MicroStorage* storage = nullptr;
        MicroInstrRef current = MicroInstrRef::invalid();

        reference operator*() const;
        pointer   operator->() const;
        Iterator& operator++();
        Iterator  operator++(int);
        Iterator& operator--();
        Iterator  operator--(int);
        bool      operator==(const Iterator& other) const;
    };

    struct ConstIterator
    {
        using iterator_concept  = std::bidirectional_iterator_tag;
        using iterator_category = std::bidirectional_iterator_tag;
        using value_type        = const MicroInstr;
        using difference_type   = std::ptrdiff_t;
        using pointer           = const MicroInstr*;
        using reference         = const MicroInstr&;

        const MicroStorage* storage = nullptr;
        MicroInstrRef       current = MicroInstrRef::invalid();

        reference      operator*() const;
        pointer        operator->() const;
        ConstIterator& operator++();
        ConstIterator  operator++(int);
        ConstIterator& operator--();
        ConstIterator  operator--(int);
        bool           operator==(const ConstIterator& other) const;
    };

    class View
        : public std::ranges::view_base
    {
    public:
        explicit View(MicroStorage* storage);
        Iterator begin() const;
        Iterator end() const;

    private:
        MicroStorage* storage_ = nullptr;
    };

    class ConstView
        : public std::ranges::view_base
    {
    public:
        explicit ConstView(const MicroStorage* storage);
        ConstIterator begin() const;
        ConstIterator end() const;

    private:
        const MicroStorage* storage_ = nullptr;
    };

    uint32_t                              count() const noexcept;
    uint32_t                              slotCount() const noexcept { return static_cast<uint32_t>(nodes_.size()); }
    uint64_t                              revision() const noexcept;
    size_t                                allocatedBytes() const noexcept;
    void                                  clear() noexcept;
    MicroInstr*                           ptr(MicroInstrRef ref) noexcept;
    const MicroInstr*                     ptr(MicroInstrRef ref) const noexcept;
    std::pair<MicroInstrRef, MicroInstr*> emplaceUninit();
    bool                                  erase(MicroInstrRef ref);
    // An erased slot is only handed out again once everything keyed by its
    // reference has been dropped. Relocations are keyed that way, and a pass
    // that erases a relocated load and inserts an instruction before its own
    // cleanup runs would otherwise see the new instruction inherit the old
    // relocation. MicroBuilder::pruneDeadRelocations is what calls this.
    void          releaseErasedRefs();
    MicroInstrRef lastInstructionRef() const noexcept { return tail_; }
    MicroInstrRef findNextInstructionRef(MicroInstrRef afterRef) const noexcept;
    MicroInstrRef findPreviousInstructionRef(MicroInstrRef beforeRef) const noexcept;
    MicroInstrRef insertBefore(MicroInstrRef beforeRef, const MicroInstr& value);
    MicroInstrRef insertDerivedBefore(MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroInstrOpcode op, std::span<const MicroInstrOperand> opsData);
    MicroInstrRef insertSyntheticBefore(MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroInstrOpcode op, std::span<const MicroInstrOperand> opsData);
    View          view() noexcept;
    ConstView     view() const noexcept;

private:
    struct Node
    {
        MicroInstr    instr;
        MicroInstrRef prev  = MicroInstrRef::invalid();
        MicroInstrRef next  = MicroInstrRef::invalid();
        bool          alive = false;
    };

    void          completeInsertedDebugSourceInfo(MicroInstrRef beforeRef, MicroInstr& inOutInstruction) const;
    MicroInstrRef allocNode();
    MicroInstrRef insertBefore(MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroInstrOpcode op, std::span<const MicroInstrOperand> opsData, const DebugSourceInfo& debugSourceInfo);
    void          linkAtEnd(MicroInstrRef ref);

    std::vector<Node>          nodes_;
    std::vector<MicroInstrRef> freeList_;
    std::vector<MicroInstrRef> quarantinedRefs_;
    MicroInstrRef              head_     = MicroInstrRef::invalid();
    MicroInstrRef              tail_     = MicroInstrRef::invalid();
    uint32_t                   count_    = 0;
    uint64_t                   revision_ = 1;
};

inline MicroStorage::Iterator::reference MicroStorage::Iterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    return storage->nodes_[current.get()].instr;
}

inline MicroStorage::Iterator::pointer MicroStorage::Iterator::operator->() const
{
    return &(**this);
}

inline MicroStorage::Iterator& MicroStorage::Iterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    current = storage->nodes_[current.get()].next;
    return *this;
}

inline MicroStorage::Iterator& MicroStorage::Iterator::operator--()
{
    SWC_ASSERT(storage);
    if (current.isInvalid())
        current = storage->tail_;
    else
        current = storage->nodes_[current.get()].prev;
    return *this;
}

inline bool MicroStorage::Iterator::operator==(const Iterator& other) const
{
    return storage == other.storage && current == other.current;
}

inline MicroStorage::ConstIterator::reference MicroStorage::ConstIterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    return storage->nodes_[current.get()].instr;
}

inline MicroStorage::ConstIterator::pointer MicroStorage::ConstIterator::operator->() const
{
    return &(**this);
}

inline MicroStorage::ConstIterator& MicroStorage::ConstIterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    current = storage->nodes_[current.get()].next;
    return *this;
}

inline MicroStorage::ConstIterator& MicroStorage::ConstIterator::operator--()
{
    SWC_ASSERT(storage);
    if (current.isInvalid())
        current = storage->tail_;
    else
        current = storage->nodes_[current.get()].prev;
    return *this;
}

inline bool MicroStorage::ConstIterator::operator==(const ConstIterator& other) const
{
    return storage == other.storage && current == other.current;
}

inline MicroStorage::View::View(MicroStorage* storage) :
    storage_(storage)
{
}

inline MicroStorage::Iterator MicroStorage::View::begin() const
{
    return {storage_, storage_->head_};
}

inline MicroStorage::Iterator MicroStorage::View::end() const
{
    return {storage_, MicroInstrRef::invalid()};
}

inline MicroStorage::ConstView::ConstView(const MicroStorage* storage) :
    storage_(storage)
{
}

inline MicroStorage::ConstIterator MicroStorage::ConstView::begin() const
{
    return {storage_, storage_->head_};
}

inline MicroStorage::ConstIterator MicroStorage::ConstView::end() const
{
    return {storage_, MicroInstrRef::invalid()};
}

inline MicroStorage::View MicroStorage::view() noexcept
{
    return View(this);
}

inline MicroStorage::ConstView MicroStorage::view() const noexcept
{
    return ConstView(this);
}

inline MicroInstr* MicroStorage::ptr(const MicroInstrRef ref) noexcept
{
    if (ref.isInvalid() || ref.get() >= nodes_.size())
        return nullptr;

    Node& node = nodes_[ref.get()];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

inline const MicroInstr* MicroStorage::ptr(const MicroInstrRef ref) const noexcept
{
    if (ref.isInvalid() || ref.get() >= nodes_.size())
        return nullptr;

    const Node& node = nodes_[ref.get()];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

SWC_END_NAMESPACE();
