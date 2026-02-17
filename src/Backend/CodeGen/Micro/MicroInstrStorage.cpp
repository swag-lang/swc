#include "pch.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"

SWC_BEGIN_NAMESPACE();

uint32_t MicroOperandStorage::count() const noexcept
{
    return static_cast<uint32_t>(operands_.size());
}

void MicroOperandStorage::clear() noexcept
{
    operands_.clear();
}

std::pair<Ref, MicroInstrOperand*> MicroOperandStorage::emplaceUninitArray(uint32_t count)
{
    if (!count)
        return {INVALID_REF, nullptr};

    const Ref first = static_cast<Ref>(operands_.size());
    operands_.resize(operands_.size() + count);
    return {first, operands_.data() + first};
}

MicroInstrOperand* MicroOperandStorage::ptr(Ref ref) noexcept
{
    SWC_ASSERT(ref < operands_.size());
    return operands_.data() + ref;
}

const MicroInstrOperand* MicroOperandStorage::ptr(Ref ref) const noexcept
{
    SWC_ASSERT(ref < operands_.size());
    return operands_.data() + ref;
}

MicroInstrStorage::Iterator::reference MicroInstrStorage::Iterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    return storage->nodes_[current].instr;
}

MicroInstrStorage::Iterator::pointer MicroInstrStorage::Iterator::operator->() const
{
    return &(**this);
}

MicroInstrStorage::Iterator& MicroInstrStorage::Iterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    current = storage->nodes_[current].next;
    return *this;
}

MicroInstrStorage::Iterator MicroInstrStorage::Iterator::operator++(int)
{
    const Iterator copy = *this;
    ++(*this);
    return copy;
}

MicroInstrStorage::Iterator& MicroInstrStorage::Iterator::operator--()
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

MicroInstrStorage::Iterator MicroInstrStorage::Iterator::operator--(int)
{
    const Iterator copy = *this;
    --(*this);
    return copy;
}

bool MicroInstrStorage::Iterator::operator==(const Iterator& other) const
{
    return storage == other.storage && current == other.current;
}

MicroInstrStorage::ConstIterator::reference MicroInstrStorage::ConstIterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    return storage->nodes_[current].instr;
}

MicroInstrStorage::ConstIterator::pointer MicroInstrStorage::ConstIterator::operator->() const
{
    return &(**this);
}

MicroInstrStorage::ConstIterator& MicroInstrStorage::ConstIterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    current = storage->nodes_[current].next;
    return *this;
}

MicroInstrStorage::ConstIterator MicroInstrStorage::ConstIterator::operator++(int)
{
    const ConstIterator copy = *this;
    ++(*this);
    return copy;
}

MicroInstrStorage::ConstIterator& MicroInstrStorage::ConstIterator::operator--()
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

MicroInstrStorage::ConstIterator MicroInstrStorage::ConstIterator::operator--(int)
{
    const ConstIterator copy = *this;
    --(*this);
    return copy;
}

bool MicroInstrStorage::ConstIterator::operator==(const ConstIterator& other) const
{
    return storage == other.storage && current == other.current;
}

MicroInstrStorage::View::View(MicroInstrStorage* storage) :
    storage_(storage)
{
}

MicroInstrStorage::Iterator MicroInstrStorage::View::begin() const
{
    return {storage_, storage_->head_};
}

MicroInstrStorage::Iterator MicroInstrStorage::View::end() const
{
    return {storage_, INVALID_REF};
}

MicroInstrStorage::ConstView::ConstView(const MicroInstrStorage* storage) :
    storage_(storage)
{
}

MicroInstrStorage::ConstIterator MicroInstrStorage::ConstView::begin() const
{
    return {storage_, storage_->head_};
}

MicroInstrStorage::ConstIterator MicroInstrStorage::ConstView::end() const
{
    return {storage_, INVALID_REF};
}

uint32_t MicroInstrStorage::count() const noexcept
{
    return count_;
}

void MicroInstrStorage::clear() noexcept
{
    nodes_.clear();
    freeList_.clear();
    head_  = INVALID_REF;
    tail_  = INVALID_REF;
    count_ = 0;
}

MicroInstr* MicroInstrStorage::ptr(Ref ref) noexcept
{
    if (ref == INVALID_REF || ref >= nodes_.size())
        return nullptr;

    Node& node = nodes_[ref];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

const MicroInstr* MicroInstrStorage::ptr(Ref ref) const noexcept
{
    if (ref == INVALID_REF || ref >= nodes_.size())
        return nullptr;

    const Node& node = nodes_[ref];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

std::pair<Ref, MicroInstr*> MicroInstrStorage::emplaceUninit()
{
    const Ref ref = allocNode();
    linkAtEnd(ref);
    return {ref, &nodes_[ref].instr};
}

Ref MicroInstrStorage::insertBefore(Ref beforeRef, const MicroInstr& value)
{
    SWC_ASSERT(beforeRef != INVALID_REF);
    SWC_ASSERT(beforeRef < nodes_.size());
    SWC_ASSERT(nodes_[beforeRef].alive);

    const Ref ref          = allocNode();
    Node&     node         = nodes_[ref];
    node.instr             = value;
    const Ref prev         = nodes_[beforeRef].prev;
    node.prev              = prev;
    node.next              = beforeRef;
    nodes_[beforeRef].prev = ref;

    if (prev != INVALID_REF)
        nodes_[prev].next = ref;
    else
        head_ = ref;

    return ref;
}

Ref MicroInstrStorage::insertBefore(MicroOperandStorage& operands, Ref beforeRef, MicroInstrOpcode op, EncodeFlags emitFlags, std::span<const MicroInstrOperand> opsData)
{
    MicroInstr inst;
    inst.op          = op;
    inst.emitFlags   = emitFlags;
    inst.numOperands = static_cast<uint8_t>(opsData.size());

    if (!opsData.empty())
    {
        auto [opsRef, dstOps] = operands.emplaceUninitArray(inst.numOperands);
        inst.opsRef           = opsRef;
        for (uint32_t i = 0; i < inst.numOperands; ++i)
            dstOps[i] = opsData[i];
    }
    else
    {
        inst.opsRef = INVALID_REF;
    }

    return insertBefore(beforeRef, inst);
}

MicroInstrStorage::View MicroInstrStorage::view() noexcept
{
    return View(this);
}

MicroInstrStorage::ConstView MicroInstrStorage::view() const noexcept
{
    return ConstView(this);
}

Ref MicroInstrStorage::allocNode()
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

void MicroInstrStorage::linkAtEnd(Ref ref)
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

SWC_END_NAMESPACE();
