#pragma once
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

// A membership set of pointers, held in one flat table.
//
// The compiler asks "have I already seen this symbol" tens of millions of times over a module, and
// a node-based set answers each question with a heap allocation and a pointer chase. This one
// stores the pointers themselves in a power-of-two table with linear probing: an insert is a
// multiply, a mask and a compare. The first table is inline, so a set that stays small - most of
// them - allocates nothing.
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

    // A set that holds nothing has nothing to free. A large table that its last fill used only a
    // little of is given back, so a set a worker keeps costs what the current walk inserts rather
    // than the largest walk it has seen.
    void clear() noexcept
    {
        if (!count_)
            return;
        if (slots_.size() > RELEASE_CAPACITY && count_ * 8 < slots_.size())
            slots_ = SmallVector<T*, INITIAL_CAPACITY>{};
        else
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
    static constexpr size_t RELEASE_CAPACITY = 1024;

    // Pointers from one allocator share their low bits; the multiply spreads them over the table.
    static size_t slotIndex(const T* value, size_t mask) noexcept
    {
        const auto bits = reinterpret_cast<uintptr_t>(value);
        return static_cast<size_t>((bits >> 4) * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    void rehash(size_t capacity)
    {
        const SmallVector<T*, INITIAL_CAPACITY> previous = std::move(slots_);
        slots_.clear();
        slots_.resize(capacity, nullptr);

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

    SmallVector<T*, INITIAL_CAPACITY> slots_;
    size_t                            count_ = 0;
};

// The same table for strong references. A walk that only asks "have I been through this node"
// pays a node-based set one allocation per node visited; this one keeps its first table inline
// and allocates only past it. The invalid reference marks a free slot, so it is never a member.
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
        const SmallVector<uint32_t, INITIAL_CAPACITY> previous = std::move(slots_);
        slots_.clear();
        slots_.resize(capacity, K_FREE);

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

    SmallVector<uint32_t, INITIAL_CAPACITY> slots_;
    size_t                                  count_ = 0;
};

// A map from strong references to pointers, held in one flat table. Code generation records a
// payload for nearly every node it lowers, and a node-based map paid one allocation per node. A
// null value reads as absent, so erasing a key clears its value and probing never meets a
// tombstone.
template<typename R, typename V = void>
class RefPointerMap
{
public:
    V* find(R ref) const noexcept
    {
        if (slots_.empty() || ref.isInvalid())
            return nullptr;

        const uint32_t key   = ref.get();
        size_t         index = slotIndex(key, slots_.size() - 1);
        while (slots_[index].key != K_FREE)
        {
            if (slots_[index].key == key)
                return slots_[index].value;
            index = (index + 1) & (slots_.size() - 1);
        }

        return nullptr;
    }

    void set(R ref, V* value)
    {
        SWC_ASSERT(ref.isValid());
        if (slots_.empty())
            rehash(INITIAL_CAPACITY);

        const uint32_t key   = ref.get();
        size_t         index = slotIndex(key, slots_.size() - 1);
        while (slots_[index].key != K_FREE)
        {
            if (slots_[index].key == key)
            {
                if (!slots_[index].value && value)
                    ++live_;
                else if (slots_[index].value && !value)
                    --live_;
                slots_[index].value = value;
                return;
            }
            index = (index + 1) & (slots_.size() - 1);
        }

        slots_[index] = {.key = key, .value = value};
        ++count_;
        if (value)
            ++live_;

        // Linear probing degrades sharply near a full table; keep it below three quarters.
        if (count_ * 4 > slots_.size() * 3)
            rehash(slots_.size() * 2);
    }

    void erase(R ref)
    {
        if (find(ref))
            set(ref, nullptr);
    }

    // The references that map to a value; an erased one no longer counts.
    size_t size() const noexcept { return live_; }

private:
    struct Slot
    {
        uint32_t key   = K_FREE;
        V*       value = nullptr;
    };

    static constexpr size_t   INITIAL_CAPACITY = 64;
    static constexpr uint32_t K_FREE           = std::numeric_limits<uint32_t>::max();

    static size_t slotIndex(uint32_t key, size_t mask) noexcept
    {
        return static_cast<size_t>(key * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    void rehash(size_t capacity)
    {
        std::vector<Slot> previous(capacity);
        previous.swap(slots_);

        const size_t mask = slots_.size() - 1;
        for (const Slot& slot : previous)
        {
            if (slot.key == K_FREE)
                continue;
            size_t index = slotIndex(slot.key, mask);
            while (slots_[index].key != K_FREE)
                index = (index + 1) & mask;
            slots_[index] = slot;
        }
    }

    std::vector<Slot> slots_;
    size_t            count_ = 0;
    size_t            live_  = 0;
};

// A map from pointers to pointers, held in one flat table. The null key marks a free slot, so it is
// never a key; a null value reads as absent.
template<typename K, typename V>
class PointerMap
{
public:
    V* find(const K* key) const noexcept
    {
        if (slots_.empty() || !key)
            return nullptr;

        size_t index = slotIndex(key, slots_.size() - 1);
        while (slots_[index].key)
        {
            if (slots_[index].key == key)
                return slots_[index].value;
            index = (index + 1) & (slots_.size() - 1);
        }

        return nullptr;
    }

    void set(const K* key, V* value)
    {
        SWC_ASSERT(key != nullptr);
        if (slots_.empty())
            rehash(INITIAL_CAPACITY);

        size_t index = slotIndex(key, slots_.size() - 1);
        while (slots_[index].key)
        {
            if (slots_[index].key == key)
            {
                slots_[index].value = value;
                return;
            }
            index = (index + 1) & (slots_.size() - 1);
        }

        slots_[index] = {.key = key, .value = value};
        ++count_;

        // Linear probing degrades sharply near a full table; keep it below three quarters.
        if (count_ * 4 > slots_.size() * 3)
            rehash(slots_.size() * 2);
    }

    // Inserts the key with the value unless the key is already there, like 'emplace'. The null
    // key is never a key, so it is not inserted.
    void emplace(const K* key, V* value)
    {
        if (key && !find(key))
            set(key, value);
    }

    void clear() noexcept
    {
        slots_.clear();
        count_ = 0;
    }

    void reserve(size_t count)
    {
        size_t capacity = INITIAL_CAPACITY;
        while (count * 4 > capacity * 3)
            capacity *= 2;
        if (capacity > slots_.size())
            rehash(capacity);
    }

private:
    struct Slot
    {
        const K* key   = nullptr;
        V*       value = nullptr;
    };

    static constexpr size_t INITIAL_CAPACITY = 32;

    // Pointers from one allocator share their low bits; the multiply spreads them over the table.
    static size_t slotIndex(const K* key, size_t mask) noexcept
    {
        const auto bits = reinterpret_cast<uintptr_t>(key);
        return static_cast<size_t>((bits >> 4) * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    void rehash(size_t capacity)
    {
        std::vector<Slot> previous(capacity);
        previous.swap(slots_);

        const size_t mask = slots_.size() - 1;
        for (const Slot& slot : previous)
        {
            if (!slot.key)
                continue;
            size_t index = slotIndex(slot.key, mask);
            while (slots_[index].key)
                index = (index + 1) & mask;
            slots_[index] = slot;
        }
    }

    std::vector<Slot> slots_;
    size_t            count_ = 0;
};

// A map from 32-bit (or 64-bit) keys to small trivially copyable values, held in one flat table.
// The all-ones key marks a free slot, so that one key lives beside the table. A found value is read
// before the next insertion, which can move it. Clearing keeps the table, so a map that is refilled
// reuses it, unless the table is large and its last fill used little of it: that table is given
// back, so a map a worker keeps costs what the current function inserts rather than the largest
// function it has seen.
template<typename V, typename K = uint32_t, bool TrackOccupiedSlots = false>
class FlatKeyMap
{
    struct NoOccupiedSlots
    {
    };

    using OccupiedSlots = std::conditional_t<TrackOccupiedSlots, std::vector<size_t>, NoOccupiedSlots>;

    static_assert(std::is_trivially_copyable_v<V>, "FlatKeyMap holds trivially copyable values");

public:
    const V* find(K key) const noexcept
    {
        if (key == K_FREE)
            return hasFreeKey_ ? &freeKeyValue_ : nullptr;
        if (slots_.empty())
            return nullptr;

        size_t index = slotIndex(key, slots_.size() - 1);
        while (slots_[index].key != K_FREE)
        {
            if (slots_[index].key == key)
                return &slots_[index].value;
            index = (index + 1) & (slots_.size() - 1);
        }

        return nullptr;
    }

    V* find(K key) noexcept { return const_cast<V*>(std::as_const(*this).find(key)); }

    // Inserts the key with the value, or keeps the value already there, like 'emplace'.
    void emplace(K key, const V& value)
    {
        bool inserted = false;
        V&   slot     = slotFor(key, inserted);
        if (inserted)
            slot = value;
    }

    // The value of the key, value-initialized when the key is new, like 'operator[]'.
    V& getOrInsert(K key)
    {
        bool inserted = false;
        return slotFor(key, inserted);
    }

    size_t size() const noexcept { return count_ + (hasFreeKey_ ? 1 : 0); }
    bool   empty() const noexcept { return size() == 0; }

    void clear() noexcept
    {
        if (count_)
        {
            if (slots_.size() > RELEASE_CAPACITY && count_ * 8 < slots_.size())
            {
                slots_ = {};
                if constexpr (TrackOccupiedSlots)
                    std::vector<size_t>().swap(occupiedSlots_);
            }
            else if constexpr (TrackOccupiedSlots)
            {
                for (const size_t index : occupiedSlots_)
                    slots_[index].key = K_FREE;
            }
            else
            {
                for (Slot& slot : slots_)
                    slot.key = K_FREE;
            }
            count_ = 0;
        }
        if constexpr (TrackOccupiedSlots)
            occupiedSlots_.clear();
        hasFreeKey_ = false;
    }

    void reserve(size_t count)
    {
        size_t capacity = INITIAL_CAPACITY;
        while (count * 4 > capacity * 3)
            capacity *= 2;
        if (capacity > slots_.size())
            rehash(capacity);
    }

private:
    struct Slot
    {
        K key = K_FREE;
        V value{};
    };

    static constexpr size_t INITIAL_CAPACITY = 64;
    static constexpr size_t RELEASE_CAPACITY = 1024;
    static constexpr K      K_FREE           = std::numeric_limits<K>::max();

    static size_t slotIndex(K key, size_t mask) noexcept
    {
        return static_cast<size_t>(key * 0x9E3779B97F4A7C15ULL >> 32) & mask;
    }

    // The table grows before an insertion rather than after it, so the returned value stays
    // where it is until the next one.
    V& slotFor(K key, bool& outInserted)
    {
        if (key == K_FREE)
        {
            outInserted = !hasFreeKey_;
            if (outInserted)
            {
                hasFreeKey_   = true;
                freeKeyValue_ = V{};
            }
            return freeKeyValue_;
        }

        if (slots_.empty())
            rehash(INITIAL_CAPACITY);
        else if ((count_ + 1) * 4 > slots_.size() * 3)
            rehash(slots_.size() * 2);

        size_t index = slotIndex(key, slots_.size() - 1);
        while (slots_[index].key != K_FREE)
        {
            if (slots_[index].key == key)
            {
                outInserted = false;
                return slots_[index].value;
            }
            index = (index + 1) & (slots_.size() - 1);
        }

        if constexpr (TrackOccupiedSlots)
            occupiedSlots_.push_back(index);
        slots_[index] = {.key = key, .value = V{}};
        ++count_;
        outInserted = true;
        return slots_[index].value;
    }

    void rehash(size_t capacity)
    {
        if constexpr (TrackOccupiedSlots)
            occupiedSlots_.reserve(count_);
        std::vector<Slot> previous(capacity);
        previous.swap(slots_);
        if constexpr (TrackOccupiedSlots)
            occupiedSlots_.clear();

        const size_t mask = slots_.size() - 1;
        for (const Slot& slot : previous)
        {
            if (slot.key == K_FREE)
                continue;
            size_t index = slotIndex(slot.key, mask);
            while (slots_[index].key != K_FREE)
                index = (index + 1) & mask;
            slots_[index] = slot;
            if constexpr (TrackOccupiedSlots)
                occupiedSlots_.push_back(index);
        }
    }

    std::vector<Slot>                  slots_;
    [[no_unique_address]] OccupiedSlots occupiedSlots_;
    size_t                              count_ = 0;
    V                                   freeKeyValue_{};
    bool                                hasFreeKey_ = false;
};

// A variant for a worker map cleared between fills. It resets the occupied slots rather than
// scanning its retained capacity; each insertion records one slot index to make that possible.
template<typename V, typename K = uint32_t>
using TrackedClearFlatKeyMap = FlatKeyMap<V, K, true>;

// A set of 32-bit (or 64-bit) keys held in one flat table, for the instruction sets a pass collects
// once per function and then only asks about. An empty set owns nothing; a filled one is one
// allocation.
template<typename K = uint32_t>
class FlatKeySetOf
{
public:
    // True when the key was not already present.
    bool insert(K key)
    {
        bool& present = map_.getOrInsert(key);
        if (present)
            return false;
        present = true;
        return true;
    }

    bool   contains(K key) const noexcept { return map_.find(key) != nullptr; }
    bool   empty() const noexcept { return map_.size() == 0; }
    size_t size() const noexcept { return map_.size(); }
    void   clear() noexcept { map_.clear(); }
    void   reserve(size_t count) { map_.reserve(count); }

private:
    FlatKeyMap<bool, K> map_;
};

using FlatKeySet   = FlatKeySetOf<uint32_t>;
using FlatKey64Set = FlatKeySetOf<uint64_t>;

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
