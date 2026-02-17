#include "pch.h"
#include "Backend/CodeGen/Micro/MicroStorage.h"

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

MicroStorage::Iterator::reference MicroStorage::Iterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    return storage->nodes_[current].instr;
}

MicroStorage::Iterator::pointer MicroStorage::Iterator::operator->() const
{
    return &(**this);
}

MicroStorage::Iterator& MicroStorage::Iterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    current = storage->nodes_[current].next;
    return *this;
}

MicroStorage::Iterator MicroStorage::Iterator::operator++(int)
{
    const Iterator copy = *this;
    ++(*this);
    return copy;
}

MicroStorage::Iterator& MicroStorage::Iterator::operator--()
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

MicroStorage::Iterator MicroStorage::Iterator::operator--(int)
{
    const Iterator copy = *this;
    --(*this);
    return copy;
}

bool MicroStorage::Iterator::operator==(const Iterator& other) const
{
    return storage == other.storage && current == other.current;
}

MicroStorage::ConstIterator::reference MicroStorage::ConstIterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    return storage->nodes_[current].instr;
}

MicroStorage::ConstIterator::pointer MicroStorage::ConstIterator::operator->() const
{
    return &(**this);
}

MicroStorage::ConstIterator& MicroStorage::ConstIterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current != INVALID_REF);
    current = storage->nodes_[current].next;
    return *this;
}

MicroStorage::ConstIterator MicroStorage::ConstIterator::operator++(int)
{
    const ConstIterator copy = *this;
    ++(*this);
    return copy;
}

MicroStorage::ConstIterator& MicroStorage::ConstIterator::operator--()
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

MicroStorage::ConstIterator MicroStorage::ConstIterator::operator--(int)
{
    const ConstIterator copy = *this;
    --(*this);
    return copy;
}

bool MicroStorage::ConstIterator::operator==(const ConstIterator& other) const
{
    return storage == other.storage && current == other.current;
}

MicroStorage::View::View(MicroStorage* storage) :
    storage_(storage)
{
}

MicroStorage::Iterator MicroStorage::View::begin() const
{
    return {storage_, storage_->head_};
}

MicroStorage::Iterator MicroStorage::View::end() const
{
    return {storage_, INVALID_REF};
}

MicroStorage::ConstView::ConstView(const MicroStorage* storage) :
    storage_(storage)
{
}

MicroStorage::ConstIterator MicroStorage::ConstView::begin() const
{
    return {storage_, storage_->head_};
}

MicroStorage::ConstIterator MicroStorage::ConstView::end() const
{
    return {storage_, INVALID_REF};
}

uint32_t MicroStorage::count() const noexcept
{
    return count_;
}

void MicroStorage::clear() noexcept
{
    nodes_.clear();
    freeList_.clear();
    head_  = INVALID_REF;
    tail_  = INVALID_REF;
    count_ = 0;
}

MicroInstr* MicroStorage::ptr(Ref ref) noexcept
{
    if (ref == INVALID_REF || ref >= nodes_.size())
        return nullptr;

    Node& node = nodes_[ref];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

const MicroInstr* MicroStorage::ptr(Ref ref) const noexcept
{
    if (ref == INVALID_REF || ref >= nodes_.size())
        return nullptr;

    const Node& node = nodes_[ref];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

std::pair<Ref, MicroInstr*> MicroStorage::emplaceUninit()
{
    const Ref ref = allocNode();
    linkAtEnd(ref);
    return {ref, &nodes_[ref].instr};
}

Ref MicroStorage::insertBefore(Ref beforeRef, const MicroInstr& value)
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

Ref MicroStorage::insertBefore(MicroOperandStorage& operands, Ref beforeRef, MicroInstrOpcode op, EncodeFlags emitFlags, std::span<const MicroInstrOperand> opsData)
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

MicroStorage::View MicroStorage::view() noexcept
{
    return View(this);
}

MicroStorage::ConstView MicroStorage::view() const noexcept
{
    return ConstView(this);
}

Ref MicroStorage::allocNode()
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

void MicroStorage::linkAtEnd(Ref ref)
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
