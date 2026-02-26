#pragma once
#include "Backend/Micro/MicroInstr.h"

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
    size_t                                allocatedBytes() const noexcept;
    void                                  clear() noexcept;
    MicroInstr*                           ptr(MicroInstrRef ref) noexcept;
    const MicroInstr*                     ptr(MicroInstrRef ref) const noexcept;
    std::pair<MicroInstrRef, MicroInstr*> emplaceUninit();
    bool                                  erase(MicroInstrRef ref);
    MicroInstrRef                         findPreviousInstructionRef(MicroInstrRef beforeRef) const noexcept;
    MicroInstrRef                         insertBefore(MicroInstrRef beforeRef, const MicroInstr& value);
    MicroInstrRef                         insertBefore(MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroInstrOpcode op, std::span<const MicroInstrOperand> opsData);
    View                                  view() noexcept;
    ConstView                             view() const noexcept;

private:
    struct Node
    {
        MicroInstr    instr;
        MicroInstrRef prev  = MicroInstrRef::invalid();
        MicroInstrRef next  = MicroInstrRef::invalid();
        bool          alive = false;
    };

    MicroInstrRef allocNode();
    void          linkAtEnd(MicroInstrRef ref);

    std::vector<Node>          nodes_;
    std::vector<MicroInstrRef> freeList_;
    MicroInstrRef              head_  = MicroInstrRef::invalid();
    MicroInstrRef              tail_  = MicroInstrRef::invalid();
    uint32_t                   count_ = 0;
};

SWC_END_NAMESPACE();
