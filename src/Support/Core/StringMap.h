// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE();

// StringMap<T> (POD/Trivial T version)
// - Keys are string_view (caller controls lifetime).
// - You must pass a precomputed 32-bit hash for every operation.
// - Robin Hood hashing + control-byte fingerprint for speed and predictability.
// - Auto-resizing at 87.5% load (power-of-two capacities).
// - Requires: T is trivially copyable and trivially destructible (POD-friendly).
template<class T>
class StringMap
{
    static_assert(std::is_trivially_copyable_v<T>, "StringMap<T> POD version requires trivially copyable T");
    static_assert(std::is_trivially_destructible_v<T>, "StringMap<T> POD version requires trivially destructible T");

public:
    using value_type = T;

    StringMap()
    {
        rehash_(INIT_CAP);
    }

    explicit StringMap(size_t reserve_elems)
    {
        const size_t cap = next_pow2_(static_cast<size_t>(static_cast<double>(reserve_elems) / MAX_LOAD) + 1);
        rehash_(cap < 2 ? 2 : cap);
    }

    // Insert-or-assign with precomputed hash. Returns {ptr, inserted?}.
    std::pair<T*, bool> insert_or_assign(std::string_view key, uint32_t hash, const T& value)
    {
        return upsert_h_(key, hash, [&](T& dst) { dst = value; }, [&](T& dst) { dst = value; });
    }

    std::pair<T*, bool> insert_or_assign(std::string_view key, uint32_t hash, T&& value)
    {
        return upsert_h_(key, hash, [&](T& dst) { dst = std::move(value); }, [&](T& dst) { dst = std::move(value); });
    }

    // Try-emplace with precomputed hash. (Construct only if missing.)
    template<class... Args>
    std::pair<T*, bool> try_emplace(std::string_view key, uint32_t hash, Args&&... args)
    {
        return upsert_h_(key, hash, [&](T& dst) { dst = T(std::forward<Args>(args)...); }, [&](T&) {});
    }

    // Get existing or create default-constructed (zero-initialized) if missing.
    T& get_or_insert(std::string_view key, uint32_t hash)
    {
        return *try_emplace(key, hash, T{}).first;
    }

    // Convenience: insert the given value if missing; otherwise return existing unchanged.
    T& get_or_insert(std::string_view key, uint32_t hash, const T& init)
    {
        return *try_emplace(key, hash, init).first;
    }

    // Find with precomputed hash.
    T* find(std::string_view key, uint32_t hash)
    {
        return find_impl_(key, hash);
    }

    const T* find(std::string_view key, uint32_t hash) const
    {
        return const_cast<StringMap*>(this)->find_impl_(key, hash);
    }

    bool contains(std::string_view key, uint32_t hash) const
    {
        return find(key, hash) != nullptr;
    }

    void reserve(size_t n_elems)
    {
        const size_t need_cap = static_cast<size_t>(static_cast<double>(n_elems) / MAX_LOAD) + 1;
        if (need_cap > capacity())
            rehash_(next_pow2_(need_cap));
    }

    void clear()
    {
        std::ranges::fill(ctrl_, EMPTY);
        size_ = 0;
    }

    size_t size() const noexcept { return size_; }
    size_t capacity() const noexcept { return slots_.size(); }
    bool   empty() const noexcept { return size_ == 0; }

private:
    // Control bytes mirror Abseil/Swiss-table style filtering:
    //  - EMPTY (0x80): never used
    //  - TOMB  (0xFE): tombstone
    //  - otherwise: 7-bit fingerprint (never 0) derived from hash's top byte | 1
    static constexpr uint8_t EMPTY    = 0x80;
    static constexpr uint8_t TOMB     = 0xFE;
    static constexpr double  MAX_LOAD = 0.875; // 7/8
    static constexpr size_t  INIT_CAP = 16;

    struct Slot
    {
        uint16_t         dist = 0; // probe distance (Robin Hood)
        uint16_t         _pad = 0;
        uint32_t         hash = 0; // 32-bit hash
        std::string_view key{};
        T                value{}; // POD value; uninitialized bits OK for EMPTY/TOMB
    };

    std::vector<uint8_t> ctrl_;  // control bytes
    std::vector<Slot>    slots_; // slots
    size_t               mask_ = 0;
    size_t               size_ = 0;

    static constexpr bool is_occupied_(uint8_t c) noexcept
    {
        return c != EMPTY && c != TOMB;
    }

    static uint8_t fingerprint_(uint32_t h) noexcept
    {
        uint8_t fp = static_cast<uint8_t>((h >> 24) | 1u); // ensure non-zero, top 8 bits of 32-bit hash
        if (fp == EMPTY || fp == TOMB)
            fp = 1;
        return fp;
    }

    static size_t next_pow2_(size_t x)
    {
        if (x < 2)
            return 2;
        --x;
        for (size_t i = 1; i < sizeof(size_t) * 8; i <<= 1)
            x |= (x >> i);
        return x + 1;
    }

    void rehash_(size_t new_cap_pow2)
    {
        new_cap_pow2 = next_pow2_(new_cap_pow2);
        std::vector       new_ctrl(new_cap_pow2, EMPTY);
        std::vector<Slot> new_slots(new_cap_pow2);
        const size_t      new_mask = new_cap_pow2 - 1;

        // Move entries
        for (size_t i = 0; i < slots_.size(); ++i)
        {
            if (!is_occupied_(ctrl_[i]))
                continue;

            Slot moving;
            moving.hash  = slots_[i].hash;
            moving.key   = slots_[i].key;
            moving.value = std::move(slots_[i].value);
            moving.dist  = 0;

            uint8_t  fp   = fingerprint_(moving.hash);
            size_t   idx  = static_cast<size_t>(moving.hash) & new_mask;
            uint16_t dist = 0;

            while (true)
            {
                if (!is_occupied_(new_ctrl[idx]))
                {
                    new_ctrl[idx]  = fp;
                    moving.dist    = dist;
                    new_slots[idx] = std::move(moving);
                    break;
                }
                if (new_slots[idx].dist < dist)
                {
                    std::swap(new_ctrl[idx], fp);
                    moving.dist = dist;
                    std::swap(new_slots[idx], moving);
                    dist = moving.dist;
                }
                ++dist;
                idx = (idx + 1) & new_mask;
            }
        }

        ctrl_.swap(new_ctrl);
        slots_.swap(new_slots);
        mask_ = new_mask;
    }

    template<class FInsert, class FFound>
    std::pair<T*, bool> upsert_h_(std::string_view key, uint32_t hash, FInsert on_insert, FFound on_found)
    {
        if (static_cast<double>(size_ + 1) > MAX_LOAD * static_cast<double>(capacity()))
            rehash_(capacity() ? capacity() * 2 : INIT_CAP);

        const uint8_t fp         = fingerprint_(hash);
        size_t        idx        = hash & mask_;
        uint16_t      dist       = 0;
        size_t        first_tomb = INVALID_POS;

        while (true)
        {
            const uint8_t c = ctrl_[idx];

            if (c == EMPTY)
            {
                size_t target = (first_tomb != INVALID_POS) ? first_tomb : idx;
                ctrl_[target] = fp;
                Slot& s       = slots_[target];
                s.hash        = hash;
                s.key         = key;
                s.dist        = dist;
                on_insert(s.value);
                ++size_;
                return {&s.value, true};
            }

            if (c == TOMB && first_tomb == INVALID_POS)
                first_tomb = idx;

            if (is_occupied_(c))
            {
                Slot& s = slots_[idx];

                // Equality check (FOUND)
                if (c == fp && s.hash == hash && s.key == key)
                {
                    on_found(s.value);
                    return {&s.value, false};
                }

                if (s.dist < dist)
                {
                    size_t target = (first_tomb != INVALID_POS) ? first_tomb : idx;

                    // Create a moving entry from input
                    Slot moving;
                    moving.hash = hash;
                    moving.key  = key;
                    moving.dist = dist;
                    on_insert(moving.value);

                    // If using a tombstone target, place it there first.
                    if (target != idx)
                    {
                        ctrl_[target]  = fp;
                        slots_[target] = std::move(moving);

                        // Continue by inserting displaced resident
                        Slot    carry    = std::move(slots_[idx]);
                        uint8_t carry_fp = c;
                        ctrl_[idx]       = TOMB;

                        const size_t base  = carry.hash & mask_;
                        size_t       ins   = (target + 1) & mask_;
                        uint16_t     idist = static_cast<uint16_t>(((target >= base) ? (target - base) : (target + capacity() - base)) + 1);

                        while (true)
                        {
                            const uint8_t cc = ctrl_[ins];
                            if (cc == EMPTY || cc == TOMB)
                            {
                                ctrl_[ins]  = carry_fp;
                                carry.dist  = idist;
                                slots_[ins] = std::move(carry);
                                if (cc == EMPTY)
                                    ++size_;
                                return {&slots_[target].value, true};
                            }

                            if (slots_[ins].dist < idist)
                            {
                                carry.dist = idist;
                                std::swap(ctrl_[ins], carry_fp);
                                std::swap(slots_[ins], carry);
                                idist = carry.dist;
                            }
                            ++idist;
                            ins = (ins + 1) & mask_;
                        }
                    }

                    // Swap with resident at idx
                    uint8_t new_fp = fp;
                    std::swap(ctrl_[idx], new_fp);

                    Slot carry       = std::move(slots_[idx]);
                    slots_[idx].hash = hash;
                    slots_[idx].key  = key;
                    slots_[idx].dist = dist;
                    on_insert(slots_[idx].value);

                    size_t   ins   = (idx + 1) & mask_;
                    uint16_t idist = static_cast<uint16_t>(carry.dist + 1);

                    while (true)
                    {
                        const uint8_t cc = ctrl_[ins];
                        if (cc == EMPTY || cc == TOMB)
                        {
                            ctrl_[ins]  = new_fp;
                            carry.dist  = idist;
                            slots_[ins] = std::move(carry);
                            if (cc == EMPTY)
                                ++size_;
                            return {&slots_[idx].value, true};
                        }

                        if (slots_[ins].dist < idist)
                        {
                            carry.dist = idist;
                            std::swap(ctrl_[ins], new_fp);
                            std::swap(slots_[ins], carry);
                            idist = carry.dist;
                        }

                        ++idist;
                        ins = (ins + 1) & mask_;
                    }
                }
            }

            ++dist;
            idx = (idx + 1) & mask_;
        }
    }

    bool find_index_(std::string_view key, uint32_t hash, size_t& out_idx)
    {
        if (slots_.empty())
            return false;

        const uint8_t fp   = fingerprint_(hash);
        size_t        idx  = hash & mask_;
        uint16_t      dist = 0;

        while (true)
        {
            const uint8_t c = ctrl_[idx];
            if (c == EMPTY)
                return false;
            if (is_occupied_(c))
            {
                Slot& s = slots_[idx];

                if (c == fp && s.hash == hash && s.key == key)
                {
                    out_idx = idx;
                    return true;
                }

                if (s.dist < dist)
                    return false;
            }

            ++dist;
            idx = (idx + 1) & mask_;
        }
    }

    T* find_impl_(std::string_view key, uint32_t hash)
    {
        size_t idx;
        if (!find_index_(key, hash, idx))
            return nullptr;
        return &slots_[idx].value;
    }

    static constexpr size_t INVALID_POS = static_cast<size_t>(-1);
};

SWC_END_NAMESPACE();
