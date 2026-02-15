#pragma once
#include "Backend/MachineCode/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

class MicroOperandStorage
{
public:
    uint32_t count() const noexcept { return static_cast<uint32_t>(operands_.size()); }

    void clear() noexcept
    {
        operands_.clear();
    }

    std::pair<Ref, MicroInstrOperand*> emplaceUninitArray(uint32_t count)
    {
        if (!count)
            return {INVALID_REF, nullptr};

        const Ref first = static_cast<Ref>(operands_.size());
        operands_.resize(operands_.size() + count);
        return {first, operands_.data() + first};
    }

    MicroInstrOperand* ptr(Ref ref) noexcept
    {
        SWC_ASSERT(ref < operands_.size());
        return operands_.data() + ref;
    }

    const MicroInstrOperand* ptr(Ref ref) const noexcept
    {
        SWC_ASSERT(ref < operands_.size());
        return operands_.data() + ref;
    }

private:
    std::vector<MicroInstrOperand> operands_;
};

class MicroInstrStorage
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

        MicroInstrStorage* storage = nullptr;
        Ref                current = INVALID_REF;

        reference operator*() const
        {
            SWC_ASSERT(storage);
            SWC_ASSERT(current != INVALID_REF);
            return storage->nodes_[current].instr;
        }

        pointer operator->() const
        {
            return &(**this);
        }

        Iterator& operator++()
        {
            SWC_ASSERT(storage);
            SWC_ASSERT(current != INVALID_REF);
            current = storage->nodes_[current].next;
            return *this;
        }

        Iterator operator++(int)
        {
            Iterator copy = *this;
            ++(*this);
            return copy;
        }

        Iterator& operator--()
        {
            SWC_ASSERT(storage);

            if (current == INVALID_REF)
            {
                current = storage->tail_;
                return *this;
            }

            current = storage->nodes_[current].prev;
            return *this;
        }

        Iterator operator--(int)
        {
            Iterator copy = *this;
            --(*this);
            return copy;
        }

        bool operator==(const Iterator& other) const
        {
            return storage == other.storage && current == other.current;
        }
    };

    class View
        : public std::ranges::view_base
    {
    public:
        explicit View(MicroInstrStorage* storage) :
            storage_(storage)
        {
        }

        Iterator begin() const
        {
            return {storage_, storage_->head_};
        }

        Iterator end() const
        {
            return {storage_, INVALID_REF};
        }

    private:
        MicroInstrStorage* storage_ = nullptr;
    };

    uint32_t count() const noexcept { return count_; }

    void clear() noexcept
    {
        nodes_.clear();
        freeList_.clear();
        head_  = INVALID_REF;
        tail_  = INVALID_REF;
        count_ = 0;
    }

    std::pair<Ref, MicroInstr*> emplaceUninit()
    {
        const Ref ref = allocNode();
        linkAtEnd(ref);
        return {ref, &nodes_[ref].instr};
    }

    Ref insertBefore(Ref beforeRef, const MicroInstr& value)
    {
        SWC_ASSERT(beforeRef != INVALID_REF);
        SWC_ASSERT(beforeRef < nodes_.size());
        SWC_ASSERT(nodes_[beforeRef].alive);

        const Ref ref       = allocNode();
        Node&     node      = nodes_[ref];
        node.instr          = value;
        const Ref prev      = nodes_[beforeRef].prev;
        node.prev           = prev;
        node.next           = beforeRef;
        nodes_[beforeRef].prev = ref;

        if (prev != INVALID_REF)
            nodes_[prev].next = ref;
        else
            head_ = ref;

        return ref;
    }

    View view() noexcept { return View(this); }

private:
    struct Node
    {
        MicroInstr instr;
        Ref        prev  = INVALID_REF;
        Ref        next  = INVALID_REF;
        bool       alive = false;
    };

    Ref allocNode()
    {
        Ref ref = INVALID_REF;
        if (!freeList_.empty())
        {
            ref = freeList_.back();
            freeList_.pop_back();
        }
        else
        {
            ref = static_cast<Ref>(nodes_.size());
            nodes_.emplace_back();
        }

        Node& node = nodes_[ref];
        node       = Node{};
        node.alive = true;
        ++count_;
        return ref;
    }

    void linkAtEnd(Ref ref)
    {
        Node& node = nodes_[ref];
        node.prev  = tail_;
        node.next  = INVALID_REF;

        if (tail_ != INVALID_REF)
            nodes_[tail_].next = ref;
        else
            head_ = ref;

        tail_ = ref;
    }

    std::vector<Node> nodes_;
    std::vector<Ref>  freeList_;
    Ref               head_  = INVALID_REF;
    Ref               tail_  = INVALID_REF;
    uint32_t          count_ = 0;
};

SWC_END_NAMESPACE();
