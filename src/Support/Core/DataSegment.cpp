#include "pch.h"
#include "Support/Core/DataSegment.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

void DataSegment::LargeBlockStorageDeleter::operator()(std::byte* ptr) const noexcept
{
    if (proximitySize)
        Os::freeProximityMemory(ptr, proximitySize);
    else
        delete[] ptr;
}

namespace
{
    bool containsLargeBlockRange(const DataSegment::LargeBlock& block, const Ref ref, const uint32_t size) noexcept
    {
        return ref >= block.offset && ref + size <= block.offset + block.size;
    }

    const std::byte* findLargeBlockPtr(const std::vector<DataSegment::LargeBlock>& blocks, const Ref ref, const uint32_t size) noexcept
    {
        // Page-backed addresses precede these append-only, offset-ordered blocks.
        if (ref < blocks.front().offset)
            return nullptr;

        const auto  it    = std::ranges::upper_bound(blocks, ref, {}, &DataSegment::LargeBlock::offset);
        const auto& block = *std::prev(it);
        return containsLargeBlockRange(block, ref, size) ? block.storage.get() + (ref - block.offset) : nullptr;
    }

    struct RelocationOffsetProjection
    {
        const std::vector<DataSegmentRelocation>* relocations = nullptr;

        uint32_t operator()(const uint32_t index) const
        {
            return (*relocations)[index].offset;
        }
    };

    struct RelocationIndexLess
    {
        const std::vector<DataSegmentRelocation>* relocations = nullptr;

        bool operator()(const uint32_t lhs, const uint32_t rhs) const
        {
            const uint32_t lhsOffset = (*relocations)[lhs].offset;
            const uint32_t rhsOffset = (*relocations)[rhs].offset;
            if (lhsOffset != rhsOffset)
                return lhsOffset < rhsOffset;

            return lhs < rhs;
        }
    };
}

std::pair<std::span<const std::byte>, Ref> DataSegment::addSpan(std::span<const std::byte> value)
{
    return addSpan(value, alignof(std::byte));
}

std::pair<std::span<const std::byte>, Ref> DataSegment::addSpan(std::span<const std::byte> value, uint32_t align)
{
    const std::unique_lock lock(mutex_);
    const auto [offset, ptr] = allocateStorageLocked(static_cast<uint32_t>(value.size()), align, false);
    if (value.data() && !value.empty())
        std::memcpy(ptr, value.data(), value.size());

    recordAllocation(offset, static_cast<uint32_t>(value.size()), align);
    return {{ptr, value.size()}, offset};
}

std::pair<std::string_view, Ref> DataSegment::addString(const std::string_view value)
{
    const uint32_t         hash = Math::hash(value);
    const std::unique_lock lock(mutex_);
    if (const InternedString* found = stringMap_.find(value, hash))
        return {std::string_view{found->data, found->size}, found->offset};

    SWC_ASSERT(value.size() < std::numeric_limits<uint32_t>::max());
    const uint32_t size      = static_cast<uint32_t>(value.size()) + 1;
    const auto [offset, ptr] = allocateStorageLocked(size, alignof(std::byte), false);
    if (!value.empty())
        std::memcpy(ptr, value.data(), value.size());
    ptr[value.size()] = std::byte{0};

    recordAllocation(offset, size, alignof(std::byte));
    const std::string_view view{reinterpret_cast<const char*>(ptr), value.size()};

    // The key stays independently owned: segment bytes can be restored by test snapshots.
    char* key = nullptr;
    if (!value.empty())
    {
        key = static_cast<char*>(stringKeys_.allocate(value.size(), alignof(char)));
        std::memcpy(key, value.data(), value.size());
    }

    stringMap_.insert_or_assign(std::string_view{key, value.size()}, hash, InternedString{.data = view.data(), .size = static_cast<uint32_t>(view.size()), .offset = offset});

    return {view, offset};
}

uint32_t DataSegment::addString(uint32_t baseOffset, uint32_t fieldOffset, const std::string_view value)
{
    const std::pair<std::string_view, Ref> res = addString(value);
    addRelocation(baseOffset + fieldOffset, res.second);

    const char** ptrField = ptr<const char*>(baseOffset + fieldOffset);
    *ptrField             = res.first.data();

    return static_cast<uint32_t>(res.first.size());
}

void DataSegment::addRelocation(uint32_t offset, uint32_t targetOffset)
{
    const std::unique_lock lock(relocationsMutex_);
    const uint32_t         relocationIndex = static_cast<uint32_t>(relocations_.size());
    relocations_.push_back({.offset = offset, .kind = DataSegmentRelocationKind::DataSegmentOffset, .targetOffset = targetOffset, .targetShardIndex = INVALID_REF, .targetSymbol = nullptr});
    recordRelocationIndexLocked(relocationIndex);
}

void DataSegment::addRelocation(uint32_t offset, const DataSegmentRef targetRef)
{
    const std::unique_lock lock(relocationsMutex_);
    const uint32_t         relocationIndex = static_cast<uint32_t>(relocations_.size());
    relocations_.push_back({.offset = offset, .kind = DataSegmentRelocationKind::DataSegmentOffset, .targetOffset = targetRef.offset, .targetShardIndex = targetRef.shardIndex, .targetSymbol = nullptr});
    recordRelocationIndexLocked(relocationIndex);
}

void DataSegment::addFunctionRelocation(uint32_t offset, const SymbolFunction* targetSymbol, bool allowUnresolvedFunction)
{
    const std::unique_lock lock(relocationsMutex_);
    const uint32_t         relocationIndex = static_cast<uint32_t>(relocations_.size());
    relocations_.push_back({.offset = offset, .kind = DataSegmentRelocationKind::FunctionSymbol, .allowUnresolvedFunction = allowUnresolvedFunction, .targetOffset = INVALID_REF, .targetShardIndex = INVALID_REF, .targetSymbol = targetSymbol});
    recordRelocationIndexLocked(relocationIndex);
}

Ref DataSegment::findRef(const void* ptr) const noexcept
{
    // Fast path: with no large blocks, findRef only consults the lock-free PagedStore.
    if (!hasLargeBlocks_.load(std::memory_order_acquire))
        return store_.findRef(ptr);

    const std::shared_lock lock(mutex_);
    const Ref              ref = store_.findRef(ptr);
    if (ref != INVALID_REF)
        return ref;

    return findLargeBlockRefLocked(ptr);
}

bool DataSegment::findAllocation(DataSegmentAllocation& outAllocation, const uint32_t offset) const noexcept
{
    outAllocation = {};

    const std::shared_lock lock(allocationsMutex_);
    if (allocations_.empty())
        return false;

    const auto it = std::ranges::upper_bound(allocations_, offset, {}, &DataSegmentAllocation::offset);
    if (it == allocations_.begin())
        return false;

    const auto allocIt = std::prev(it);
    if (offset < allocIt->offset || offset - allocIt->offset >= allocIt->size)
        return false;

    outAllocation = *allocIt;
    return true;
}

bool DataSegment::isInternedString(const DataSegmentAllocation& allocation) const
{
    if (!allocation.size || allocation.align != alignof(std::byte))
        return false;

    // Read the bytes before taking the lock: the large-block path of ptr() takes it too.
    const char* bytes = ptr<char>(allocation.offset);
    if (!bytes || bytes[allocation.size - 1] != 0)
        return false;

    const std::string_view value{bytes, allocation.size - 1};
    const uint32_t         hash = Math::hash(value);
    const std::shared_lock lock(mutex_);
    const InternedString*  found = stringMap_.find(value, hash);
    return found && found->offset == allocation.offset;
}

uint32_t DataSegment::size() const noexcept
{
    const std::shared_lock lock(mutex_);
    if (largeBlocks_.empty())
        return store_.size();

    return currentExtentLocked();
}

uint32_t DataSegment::extentSize() const noexcept
{
    const std::shared_lock lock(mutex_);
    return currentExtentLocked();
}

void DataSegment::copyTo(std::span<std::byte> dst) const
{
    const std::shared_lock lock(mutex_);
    if (!largeBlocks_.empty())
    {
        if (dst.empty())
            return;

        std::memset(dst.data(), 0, dst.size_bytes());

        const uint32_t storeExtent = store_.extentSize();
        if (storeExtent)
            store_.copyToPreserveOffsets(std::span{dst.data(), storeExtent});

        for (const LargeBlock& block : largeBlocks_)
        {
            SWC_ASSERT(block.offset + block.size <= dst.size_bytes());
            std::memcpy(dst.data() + block.offset, block.storage.get(), block.size);
        }

        return;
    }

    store_.copyTo(dst);
}

void DataSegment::copyToPreserveOffsets(std::span<std::byte> dst) const
{
    const std::shared_lock lock(mutex_);
    const uint32_t         storeExtent = store_.extentSize();
    SWC_ASSERT(storeExtent <= dst.size_bytes());
    if (storeExtent)
        store_.copyToPreserveOffsets(std::span{dst.data(), storeExtent});

    const auto tail = dst.subspan(storeExtent);
    if (!tail.empty())
        std::memset(tail.data(), 0, tail.size_bytes());

    for (const LargeBlock& block : largeBlocks_)
    {
        SWC_ASSERT(block.offset + block.size <= dst.size_bytes());
        std::memcpy(dst.data() + block.offset, block.storage.get(), block.size);
    }
}

void DataSegment::restoreFromPreserveOffsets(std::span<const std::byte> src) const
{
    const std::unique_lock lock(mutex_);
    const uint32_t         storeExtent = store_.extentSize();
    if (storeExtent)
        store_.restoreFromPreserveOffsets(std::span{src.data(), storeExtent});
    for (const LargeBlock& block : largeBlocks_)
    {
        SWC_ASSERT(block.offset + block.size <= src.size_bytes());
        std::memcpy(block.storage.get(), src.data() + block.offset, block.size);
    }
}

void DataSegment::fill(const std::byte value) const
{
    const std::unique_lock lock(mutex_);
    store_.fill(value);
    for (const LargeBlock& block : largeBlocks_)
        std::memset(block.storage.get(), std::to_integer<int>(value), block.size);
}

std::vector<DataSegmentRelocation> DataSegment::copyRelocations() const
{
    const std::shared_lock lock(relocationsMutex_);
    return relocations_;
}

std::vector<const SymbolFunction*> DataSegment::copyFunctionRelocationTargets() const
{
    const std::shared_lock             lock(relocationsMutex_);
    std::vector<const SymbolFunction*> targets;
    for (const DataSegmentRelocation& relocation : relocations_)
        if (relocation.kind == DataSegmentRelocationKind::FunctionSymbol)
            targets.push_back(relocation.targetSymbol);
    return targets;
}

std::vector<DataSegmentRef> DataSegment::copyDataSegmentRelocationTargets() const
{
    const std::shared_lock      lock(relocationsMutex_);
    std::vector<DataSegmentRef> targets;
    for (const DataSegmentRelocation& relocation : relocations_)
    {
        if (relocation.kind != DataSegmentRelocationKind::DataSegmentOffset || relocation.targetShardIndex == INVALID_REF)
            continue;

        targets.push_back({.shardIndex = relocation.targetShardIndex, .offset = relocation.targetOffset});
    }
    return targets;
}

void DataSegment::copyRelocations(std::vector<DataSegmentRelocation>& outRelocations, const uint32_t offset, const uint32_t size) const
{
    copyRelocationsImpl(outRelocations, offset, size);
}

void DataSegment::copyRelocations(SmallVector<DataSegmentRelocation, 4>& outRelocations, const uint32_t offset, const uint32_t size) const
{
    copyRelocationsImpl(outRelocations, offset, size);
}

bool DataSegment::findRelocation(DataSegmentRelocation& outRelocation, const uint32_t offset, const DataSegmentRelocationKind kind) const
{
    outRelocation = {};

    const std::shared_lock lock(relocationsMutex_);
    return findRelocationLocked(outRelocation, offset, kind);
}

bool DataSegment::hasRelocations(const uint32_t offset, const uint32_t size) const
{
    if (!size)
        return false;

    const std::shared_lock lock(relocationsMutex_);
    return hasRelocationsLocked(offset, size);
}

template<typename T>
void DataSegment::copyRelocationsImpl(T& outRelocations, const uint32_t offset, const uint32_t size) const
{
    outRelocations.clear();
    if (!size)
        return;

    // Readers only ever take a shared lock: the query walks the sorted prefix plus the unsorted tail, so
    // no exclusive index rebuild is needed. This keeps concurrent readers off the writer's critical path.
    const std::shared_lock lock(relocationsMutex_);

    const RelocationOffsetProjection projection{.relocations = &relocations_};

    auto       indexed     = std::ranges::lower_bound(relocationsByOffset_, offset, {}, projection);
    auto       tail        = std::ranges::lower_bound(relocationsTailByOffset_, offset, {}, projection);
    const auto appendRange = [&](const std::vector<uint32_t>& index, auto it) {
        for (; it != index.end() && relocations_[*it].offset - offset < size; ++it)
            outRelocations.push_back(relocations_[*it]);
    };
    const bool tailRangeEmpty       = tail == relocationsTailByOffset_.end() || relocations_[*tail].offset - offset >= size;
    const bool rangesAlreadyOrdered = indexed == relocationsByOffset_.end() || tailRangeEmpty ||
                                      relocations_[relocationsByOffset_.back()].offset <= relocations_[*tail].offset;
    if (rangesAlreadyOrdered)
    {
        appendRange(relocationsByOffset_, indexed);
        appendRange(relocationsTailByOffset_, tail);
        return;
    }

    // Merge into the output to avoid materializing both ranges before a second merge pass.
    // The indexed prefix predates the tail, so choosing it on ties preserves insertion order.
    while (indexed != relocationsByOffset_.end() && tail != relocationsTailByOffset_.end())
    {
        const DataSegmentRelocation& indexedRelocation = relocations_[*indexed];
        const DataSegmentRelocation& tailRelocation    = relocations_[*tail];
        if (indexedRelocation.offset - offset >= size)
            break;
        if (tailRelocation.offset - offset >= size)
        {
            outRelocations.push_back(indexedRelocation);
            ++indexed;
            continue;
        }

        if (indexedRelocation.offset <= tailRelocation.offset)
        {
            outRelocations.push_back(indexedRelocation);
            ++indexed;
        }
        else
        {
            outRelocations.push_back(tailRelocation);
            ++tail;
        }
    }
    for (; indexed != relocationsByOffset_.end() && relocations_[*indexed].offset - offset < size; ++indexed)
        outRelocations.push_back(relocations_[*indexed]);
    for (; tail != relocationsTailByOffset_.end() && relocations_[*tail].offset - offset < size; ++tail)
        outRelocations.push_back(relocations_[*tail]);
}

bool DataSegment::findRelocationLocked(DataSegmentRelocation& outRelocation, const uint32_t offset, const DataSegmentRelocationKind kind) const
{
    const RelocationOffsetProjection projection{.relocations = &relocations_};

    const auto findIn = [&](const std::vector<uint32_t>& index) {
        for (auto it = std::ranges::lower_bound(index, offset, {}, projection); it != index.end(); ++it)
        {
            const DataSegmentRelocation& relocation = relocations_[*it];
            if (relocation.offset != offset)
                break;
            if (relocation.kind == kind)
            {
                outRelocation = relocation;
                return true;
            }
        }

        return false;
    };

    return findIn(relocationsByOffset_) || findIn(relocationsTailByOffset_);
}

bool DataSegment::hasRelocationsLocked(const uint32_t offset, const uint32_t size) const
{
    const RelocationOffsetProjection projection{.relocations = &relocations_};

    const auto hasIn = [&](const std::vector<uint32_t>& index) {
        const auto it = std::ranges::lower_bound(index, offset, {}, projection);
        return it != index.end() && relocations_[*it].offset - offset < size;
    };

    return hasIn(relocationsByOffset_) || hasIn(relocationsTailByOffset_);
}

std::mutex& DataSegment::allocationMutex(const uint32_t allocationOffset) const
{
    const std::scoped_lock lock(allocationMutexesMutex_);
    auto&                  mutex = allocationMutexes_[allocationOffset];
    if (!mutex)
        mutex = std::make_unique<std::mutex>();
    return *mutex;
}

std::pair<uint32_t, std::byte*> DataSegment::reserveBytes(uint32_t size, uint32_t align, bool zeroInit)
{
    if (!size)
        return {INVALID_REF, nullptr};

    const std::unique_lock lock(mutex_);
    const auto             res = allocateStorageLocked(size, align, zeroInit);
    recordAllocation(res.first, size, align);
    return res;
}

uint32_t DataSegment::reserveBlock(uint32_t size, uint32_t align, bool zeroInit)
{
    return reserveBytes(size, align, zeroInit).first;
}

uint32_t DataSegment::currentExtentLocked() const noexcept
{
    if (!largeBlocks_.empty())
    {
        const LargeBlock& last = largeBlocks_.back();
        return last.offset + last.size;
    }

    return store_.extentSize();
}

std::pair<uint32_t, std::byte*> DataSegment::allocateStorageLocked(uint32_t size, uint32_t align, bool zeroInit)
{
    if (!size)
        return {INVALID_REF, nullptr};
    if (!align)
        align = 1;

    if (!largeBlocks_.empty() || size > store_.pageSize())
    {
        if (!largeBlocks_.empty())
        {
            LargeBlock&    last     = largeBlocks_.back();
            const uint32_t offset   = Math::alignUpU32(last.offset + last.size, align);
            const uint32_t relative = offset - last.offset;
            const auto     begin    = reinterpret_cast<uintptr_t>(last.storage.get());
            if (relative <= last.capacity && size <= last.capacity - relative && (begin + relative) % align == 0)
            {
                // Keep alignment gaps zero for offset-preserving copies and snapshots.
                std::memset(last.storage.get() + last.size, 0, relative - last.size);
                std::byte* ptr = last.storage.get() + relative;
                if (zeroInit)
                    std::memset(ptr, 0, size);
                last.size                                       = relative + size;
                largeBlockRanges_.find(begin)->second.offsetEnd = begin + last.size;
                return {offset, ptr};
            }
        }

        // Large allocations end the paged prefix, but small values that follow still share
        // storage. One OS allocation per value would round each tiny constant to a 4 KiB page.
        LargeBlock block;
        block.offset   = Math::alignUpU32(currentExtentLocked(), std::max(align, static_cast<uint32_t>(alignof(std::max_align_t))));
        block.size     = size;
        block.capacity = std::max(size, store_.pageSize());
        if (proximityStorage_)
        {
            if (auto* arena = static_cast<std::byte*>(Os::allocProximityMemory(block.capacity)))
                block.storage = LargeBlockStorage(arena, {.proximitySize = block.capacity});
        }
        if (!block.storage)
            block.storage = LargeBlockStorage(new std::byte[block.capacity], {});
        if (zeroInit)
            std::memset(block.storage.get(), 0, size);

        const uint32_t offset    = block.offset;
        std::byte*     ptr       = block.storage.get();
        const auto     begin     = reinterpret_cast<uintptr_t>(ptr);
        largeBlockRanges_[begin] = {
            .offsetEnd   = begin + size,
            .blockOffset = offset,
        };
        largeBlocks_.push_back(std::move(block));
        // Publish that large blocks now exist so lock-free readers fall back to the locked path
        // (which consults largeBlocks_). Release pairs with the acquire load in ptr()/findRef().
        hasLargeBlocks_.store(true, std::memory_order_release);
        return {offset, ptr};
    }

    const auto [span, ref] = store_.reserveSpan(size, align);
    if (zeroInit)
        std::memset(span.data(), 0, size);
    return {ref, span.data()};
}

const std::byte* DataSegment::findPtrLocked(const Ref ref, const uint32_t size) const noexcept
{
    SWC_ASSERT(ref != INVALID_REF);

    if (!largeBlocks_.empty())
    {
        if (const std::byte* ptr = findLargeBlockPtr(largeBlocks_, ref, size))
            return ptr;
    }

    SWC_ASSERT(ref + size <= store_.extentSize());
    return store_.ptr<std::byte>(ref);
}

Ref DataSegment::findLargeBlockRefLocked(const void* ptr) const noexcept
{
    if (!ptr || largeBlockRanges_.empty())
        return INVALID_REF;

    const auto address = reinterpret_cast<uintptr_t>(ptr);
    const auto nextIt  = largeBlockRanges_.upper_bound(address);
    if (nextIt == largeBlockRanges_.begin())
        return INVALID_REF;

    const auto it = std::prev(nextIt);
    if (address >= it->second.offsetEnd)
        return INVALID_REF;

    return it->second.blockOffset + static_cast<uint32_t>(address - it->first);
}

void DataSegment::rebuildRelocationsByOffsetLocked() const
{
    if (relocationsTailByOffset_.empty())
        return;

    // Both halves are sorted, so folding the tail back in is one linear merge.
    const RelocationIndexLess sortRelocations{.relocations = &relocations_};
    std::vector<uint32_t>     merged;
    merged.reserve(relocationsByOffset_.size() + relocationsTailByOffset_.size());
    std::ranges::merge(relocationsByOffset_, relocationsTailByOffset_, std::back_inserter(merged), sortRelocations);

    relocationsByOffset_ = std::move(merged);
    relocationsTailByOffset_.clear();
    relocationsIndexedCount_ = static_cast<uint32_t>(relocations_.size());
}

void DataSegment::recordRelocationIndexLocked(uint32_t index)
{
    SWC_ASSERT(index + 1 == relocations_.size());
    relocationVersion_.fetch_add(1, std::memory_order_release);

    const RelocationIndexLess sortRelocations{.relocations = &relocations_};

    // Common case: relocations arrive in non-decreasing offset order (bump allocation), so the new one
    // simply extends the sorted index in O(1).
    if (relocationsTailByOffset_.empty() && (relocationsByOffset_.empty() || !sortRelocations(index, relocationsByOffset_.back())))
    {
        relocationsByOffset_.push_back(index);
        relocationsIndexedCount_ = index + 1;
        return;
    }

    // Otherwise it joins the tail, which is kept sorted so a reader binary-searches it instead of
    // scanning it. A module reads this index millions of times and writes it thousands of times, so
    // the insertion pays for itself immediately. The tail still folds back into the index once it
    // grows past a threshold that scales with the indexed size, keeping the merge cost amortized.
    relocationsTailByOffset_.insert(std::ranges::upper_bound(relocationsTailByOffset_, index, sortRelocations), index);

    const uint32_t threshold = std::max<uint32_t>(64, relocationsIndexedCount_ / 8);
    if (relocationsTailByOffset_.size() > threshold)
        rebuildRelocationsByOffsetLocked();
}

void DataSegment::recordAllocation(const uint32_t offset, const uint32_t size, uint32_t align)
{
    if (!size)
        return;

    const std::unique_lock lock(allocationsMutex_);

    if (!align)
        align = 1;

    if (!allocations_.empty())
    {
        const DataSegmentAllocation& last = allocations_.back();
        SWC_ASSERT(last.offset + last.size <= offset);
    }

    allocations_.push_back({.offset = offset, .size = size, .align = align});
}

SWC_END_NAMESPACE();
