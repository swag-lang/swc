#pragma once
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

// A membership set of pointers, held in one flat table.
//
// The compiler asks "have I already seen this symbol" tens of millions of times over a module, and
// a node-based set answers each question with a heap allocation and a pointer chase. This one
// stores the pointers themselves in a power-of-two table with linear probing: an insert is a
// multiply, a mask and a compare, and a whole set costs one allocation.
template<typename T>
class PointerSet
{
public:
    // True when the pointer was not already present.
    bool insert(T* value)
    {
        SWC_ASSERT(value != nullptr);
        if (slots_.empty())
            rehash(INITIAL_CAPACITY);

        size_t index = slotIndex(value, slots_.size() - 1);
        while (slots_[index])
        {
            if (slots_[index] == value)
                return false;
            index = (index + 1) & (slots_.size() - 1);
        }

        slots_[index] = value;
        ++count_;

        // Linear probing degrades sharply near a full table; keep it below three quarters.
        if (count_ * 4 > slots_.size() * 3)
            rehash(slots_.size() * 2);
        return true;
    }

    bool contains(const T* value) const noexcept
    {
        if (slots_.empty())
            return false;

        size_t index = slotIndex(value, slots_.size() - 1);
        while (slots_[index])
        {
            if (slots_[index] == value)
                return true;
            index = (index + 1) & (slots_.size() - 1);
        }

        return false;
    }

    void clear() noexcept
    {
        std::ranges::fill(slots_, nullptr);
        count_ = 0;
    }
    size_t size() const noexcept { return count_; }
    bool   empty() const noexcept { return count_ == 0; }

    void reserve(size_t count)
    {
        size_t capacity = INITIAL_CAPACITY;
        while (count * 4 > capacity * 3)
            capacity *= 2;
        if (capacity > slots_.size())
            rehash(capacity);
    }

private:
    static constexpr size_t INITIAL_CAPACITY = 16;

    // Pointers from one allocator share their low bits; the multiply spreads them over the table.
    static size_t slotIndex(const T* value, size_t mask) noexcept
    {
        const auto bits = reinterpret_cast<uintptr_t>(value);
        return static_cast<size_t>((bits >> 4) * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    void rehash(size_t capacity)
    {
        std::vector<T*> previous(capacity, nullptr);
        previous.swap(slots_);

        const size_t mask = slots_.size() - 1;
        for (T* value : previous)
        {
            if (!value)
                continue;
            size_t index = slotIndex(value, mask);
            while (slots_[index])
                index = (index + 1) & mask;
            slots_[index] = value;
        }
    }

    std::vector<T*> slots_;
    size_t          count_ = 0;
};

// The same table for strong references. A walk that only asks "have I been through this node"
// pays a node-based set one allocation per node visited; this one allocates nothing until the
// first insert and one array afterwards. The invalid reference marks a free slot, so it is never
// a member.
template<typename R>
class RefSet
{
public:
    // True when the reference was not already present.
    bool insert(R ref)
    {
        SWC_ASSERT(ref.isValid());
        if (slots_.empty())
            rehash(INITIAL_CAPACITY);

        const uint32_t value = ref.get();
        size_t         index = slotIndex(value, slots_.size() - 1);
        while (slots_[index] != K_FREE)
        {
            if (slots_[index] == value)
                return false;
            index = (index + 1) & (slots_.size() - 1);
        }

        slots_[index] = value;
        ++count_;

        // Linear probing degrades sharply near a full table; keep it below three quarters.
        if (count_ * 4 > slots_.size() * 3)
            rehash(slots_.size() * 2);
        return true;
    }

    bool contains(R ref) const noexcept
    {
        if (slots_.empty() || !ref.isValid())
            return false;

        const uint32_t value = ref.get();
        size_t         index = slotIndex(value, slots_.size() - 1);
        while (slots_[index] != K_FREE)
        {
            if (slots_[index] == value)
                return true;
            index = (index + 1) & (slots_.size() - 1);
        }

        return false;
    }

    size_t size() const noexcept { return count_; }
    bool   empty() const noexcept { return count_ == 0; }

private:
    static constexpr size_t   INITIAL_CAPACITY = 16;
    static constexpr uint32_t K_FREE           = std::numeric_limits<uint32_t>::max();

    static size_t slotIndex(uint32_t value, size_t mask) noexcept
    {
        return static_cast<size_t>(value * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    void rehash(size_t capacity)
    {
        std::vector<uint32_t> previous(capacity, K_FREE);
        previous.swap(slots_);

        const size_t mask = slots_.size() - 1;
        for (const uint32_t value : previous)
        {
            if (value == K_FREE)
                continue;
            size_t index = slotIndex(value, mask);
            while (slots_[index] != K_FREE)
                index = (index + 1) & mask;
            slots_[index] = value;
        }
    }

    std::vector<uint32_t> slots_;
    size_t                count_ = 0;
};

// The nodes on the current path of a recursive walk that must not re-enter itself. Each node
// leaves the path before its frame returns, so the path is never deeper than the recursion and a
// scan of it costs no more than the frames already on the stack. A node-based set pays two heap
// allocations to exist and one more per step.
template<typename T, size_t N = 16>
class WalkPath
{
public:
    // True when the value was not already on the path.
    bool insert(const T& value)
    {
        if (contains(value))
            return false;
        values_.push_back(value);
        return true;
    }

    bool contains(const T& value) const { return std::ranges::find(values_, value) != values_.end(); }

    void erase(const T& value)
    {
        // The value that entered last is the one leaving, unless a walk gave up halfway.
        for (size_t i = values_.size(); i-- > 0;)
        {
            if (values_[i] == value)
            {
                values_.erase_unordered(values_.begin() + i);
                return;
            }
        }
    }

private:
    SmallVector<T, N> values_;
};

// A membership set of 64-bit keys that a worker keeps between walks. A walk of the constant graph
// asks "have I been through this allocation" a few dozen times per function and a module makes
// thousands of such walks, so the set is reused rather than built: clearing it moves a stamp
// instead of touching the table, and a walk no longer starts by allocating one.
class StampedKeySet
{
public:
    // True when the key was not already present. Zero is not a key: it marks a free slot.
    bool insert(const uint64_t key)
    {
        SWC_ASSERT(key != 0);
        if (slots_.empty())
            grow(INITIAL_CAPACITY);

        size_t index = slotIndex(key);
        while (slots_[index].key)
        {
            if (slots_[index].stamp != stamp_)
                break;
            if (slots_[index].key == key)
                return false;
            index = (index + 1) & (slots_.size() - 1);
        }

        slots_[index] = {.key = key, .stamp = stamp_};
        ++count_;

        // Linear probing degrades sharply near a full table; keep it below three quarters.
        if (count_ * 4 > slots_.size() * 3)
            grow(slots_.size() * 2);
        return true;
    }

    void clear()
    {
        ++stamp_;
        count_ = 0;
    }

private:
    struct Slot
    {
        uint64_t key   = 0;
        uint64_t stamp = 0;
    };

    static constexpr size_t INITIAL_CAPACITY = 64;

    size_t slotIndex(const uint64_t key) const { return static_cast<size_t>(key * 0x9E3779B97F4A7C15ULL >> 32) & (slots_.size() - 1); }

    void grow(const size_t capacity)
    {
        // A stale slot belongs to an earlier walk, so only this walk's keys move.
        std::vector<Slot> live;
        live.reserve(count_);
        for (const Slot& slot : slots_)
        {
            if (slot.key && slot.stamp == stamp_)
                live.push_back(slot);
        }

        slots_.assign(capacity, Slot{});
        for (const Slot& slot : live)
        {
            size_t index = slotIndex(slot.key);
            while (slots_[index].key)
                index = (index + 1) & (slots_.size() - 1);
            slots_[index] = slot;
        }
    }

    std::vector<Slot> slots_;
    uint64_t          stamp_ = 1;
    size_t            count_ = 0;
};

SWC_END_NAMESPACE();
