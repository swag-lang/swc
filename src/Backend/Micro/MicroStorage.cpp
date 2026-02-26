#include "pch.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

uint32_t MicroOperandStorage::count() const noexcept
{
    return static_cast<uint32_t>(operands_.size());
}

size_t MicroOperandStorage::allocatedBytes() const noexcept
{
    return operands_.capacity() * sizeof(MicroInstrOperand);
}

void MicroOperandStorage::clear() noexcept
{
    operands_.clear();
}

std::pair<MicroOperandRef, MicroInstrOperand*> MicroOperandStorage::emplaceUninitArray(uint32_t count)
{
    if (!count)
        return {MicroOperandRef::invalid(), nullptr};

    const MicroOperandRef first(static_cast<uint32_t>(operands_.size()));
    operands_.resize(operands_.size() + count);
    return {first, operands_.data() + first.get()};
}

MicroInstrOperand* MicroOperandStorage::ptr(MicroOperandRef ref) noexcept
{
    SWC_ASSERT(ref.get() < operands_.size());
    return operands_.data() + ref.get();
}

const MicroInstrOperand* MicroOperandStorage::ptr(MicroOperandRef ref) const noexcept
{
    SWC_ASSERT(ref.get() < operands_.size());
    return operands_.data() + ref.get();
}

MicroStorage::Iterator::reference MicroStorage::Iterator::operator*() const
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    return storage->nodes_[current.get()].instr;
}

MicroStorage::Iterator::pointer MicroStorage::Iterator::operator->() const
{
    return &(**this);
}

MicroStorage::Iterator& MicroStorage::Iterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    current = storage->nodes_[current.get()].next;
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

    if (current.isInvalid())
    {
        current = storage->tail_;
        return *this;
    }

    current = storage->nodes_[current.get()].prev;
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
    SWC_ASSERT(current.isValid());
    return storage->nodes_[current.get()].instr;
}

MicroStorage::ConstIterator::pointer MicroStorage::ConstIterator::operator->() const
{
    return &(**this);
}

MicroStorage::ConstIterator& MicroStorage::ConstIterator::operator++()
{
    SWC_ASSERT(storage);
    SWC_ASSERT(current.isValid());
    current = storage->nodes_[current.get()].next;
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

    if (current.isInvalid())
    {
        current = storage->tail_;
        return *this;
    }

    current = storage->nodes_[current.get()].prev;
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
    return {storage_, MicroInstrRef::invalid()};
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
    return {storage_, MicroInstrRef::invalid()};
}

uint32_t MicroStorage::count() const noexcept
{
    return count_;
}

size_t MicroStorage::allocatedBytes() const noexcept
{
    return nodes_.capacity() * sizeof(Node);
}

void MicroStorage::clear() noexcept
{
    nodes_.clear();
    freeList_.clear();
    head_  = MicroInstrRef::invalid();
    tail_  = MicroInstrRef::invalid();
    count_ = 0;
}

MicroInstr* MicroStorage::ptr(MicroInstrRef ref) noexcept
{
    if (ref.isInvalid() || ref.get() >= nodes_.size())
        return nullptr;

    Node& node = nodes_[ref.get()];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

const MicroInstr* MicroStorage::ptr(MicroInstrRef ref) const noexcept
{
    if (ref.isInvalid() || ref.get() >= nodes_.size())
        return nullptr;

    const Node& node = nodes_[ref.get()];
    if (!node.alive)
        return nullptr;
    return &node.instr;
}

std::pair<MicroInstrRef, MicroInstr*> MicroStorage::emplaceUninit()
{
    const MicroInstrRef ref = allocNode();
    linkAtEnd(ref);
    return {ref, &nodes_[ref.get()].instr};
}

bool MicroStorage::erase(MicroInstrRef ref)
{
    if (ref.isInvalid() || ref.get() >= nodes_.size())
        return false;

    Node& node = nodes_[ref.get()];
    if (!node.alive)
        return false;

    if (node.prev.isValid())
        nodes_[node.prev.get()].next = node.next;
    else
        head_ = node.next;

    if (node.next.isValid())
        nodes_[node.next.get()].prev = node.prev;
    else
        tail_ = node.prev;

    node = Node{};
    freeList_.push_back(ref);
    SWC_ASSERT(count_ > 0);
    --count_;
    return true;
}

MicroInstrRef MicroStorage::findPreviousInstructionRef(MicroInstrRef beforeRef) const noexcept
{
    if (beforeRef.isInvalid())
        return tail_;

    if (beforeRef.get() >= nodes_.size())
        return MicroInstrRef::invalid();

    const Node& node = nodes_[beforeRef.get()];
    if (!node.alive)
        return MicroInstrRef::invalid();

    return node.prev;
}

MicroInstrRef MicroStorage::insertBefore(MicroInstrRef beforeRef, const MicroInstr& value)
{
    SWC_ASSERT(beforeRef.isValid());
    SWC_ASSERT(beforeRef.get() < nodes_.size());
    SWC_ASSERT(nodes_[beforeRef.get()].alive);

    const MicroInstrRef ref  = allocNode();
    Node&               node = nodes_[ref.get()];
    node.instr               = value;
    if (!node.instr.sourceCodeRef.isValid())
        node.instr.sourceCodeRef = nodes_[beforeRef.get()].instr.sourceCodeRef;
    const MicroInstrRef prev     = nodes_[beforeRef.get()].prev;
    node.prev                    = prev;
    node.next                    = beforeRef;
    nodes_[beforeRef.get()].prev = ref;

    if (prev.isValid())
        nodes_[prev.get()].next = ref;
    else
        head_ = ref;

    return ref;
}

MicroInstrRef MicroStorage::insertBefore(MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroInstrOpcode op, std::span<const MicroInstrOperand> opsData)
{
    MicroInstr inst;
    inst.op          = op;
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
        inst.opsRef = MicroOperandRef::invalid();
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

MicroInstrRef MicroStorage::allocNode()
{
    MicroInstrRef ref = MicroInstrRef::invalid();
    if (!freeList_.empty())
    {
        ref = freeList_.back();
        freeList_.pop_back();
    }
    else
    {
        ref = MicroInstrRef(static_cast<uint32_t>(nodes_.size()));
        nodes_.emplace_back();
    }

    Node& node = nodes_[ref.get()];
    node       = Node{};
    node.alive = true;
    ++count_;
    return ref;
}

void MicroStorage::linkAtEnd(MicroInstrRef ref)
{
    Node& node = nodes_[ref.get()];
    node.prev  = tail_;
    node.next  = MicroInstrRef::invalid();

    if (tail_.isValid())
        nodes_[tail_.get()].next = ref;
    else
        head_ = ref;

    tail_ = ref;
}

SWC_END_NAMESPACE();
