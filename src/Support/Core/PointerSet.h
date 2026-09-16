#pragma once

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

    void   clear() noexcept { std::ranges::fill(slots_, nullptr); count_ = 0; }
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

SWC_END_NAMESPACE();
