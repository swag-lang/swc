#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

class MicroOperandStorage
{
public:
    uint32_t                           count() const noexcept;
    size_t                             allocatedBytes() const noexcept;
    void                               clear() noexcept;
    std::pair<Ref, MicroInstrOperand*> emplaceUninitArray(uint32_t count);
    MicroInstrOperand*                 ptr(Ref ref) noexcept;
    const MicroInstrOperand*           ptr(Ref ref) const noexcept;

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
        Ref           current = INVALID_REF;

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
        Ref                 current = INVALID_REF;

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

    uint32_t                    count() const noexcept;
    size_t                      allocatedBytes() const noexcept;
    void                        clear() noexcept;
    MicroInstr*                 ptr(Ref ref) noexcept;
    const MicroInstr*           ptr(Ref ref) const noexcept;
    std::pair<Ref, MicroInstr*> emplaceUninit();
    bool                        erase(Ref ref);
    Ref                         insertBefore(Ref beforeRef, const MicroInstr& value);
    Ref                         insertBefore(MicroOperandStorage& operands, Ref beforeRef, MicroInstrOpcode op, std::span<const MicroInstrOperand> opsData);
    View                        view() noexcept;
    ConstView                   view() const noexcept;

private:
    struct Node
    {
        MicroInstr instr;
        Ref        prev  = INVALID_REF;
        Ref        next  = INVALID_REF;
        bool       alive = false;
    };

    Ref  allocNode();
    void linkAtEnd(Ref ref);

    std::vector<Node> nodes_;
    std::vector<Ref>  freeList_;
    Ref               head_  = INVALID_REF;
    Ref               tail_  = INVALID_REF;
    uint32_t          count_ = 0;
};

SWC_END_NAMESPACE();
