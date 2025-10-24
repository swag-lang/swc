#pragma once
SWC_BEGIN_NAMESPACE();

enum class SubTokenIdentifierId : uint16_t;
enum class KeywordFlagsEnum : uint32_t;
using KeywordFlags = Flags<KeywordFlagsEnum>;

struct KeywordInfo
{
    std::string_view     key;
    SubTokenIdentifierId id;
    KeywordFlags         flags;
};

template<size_t N>
struct KeywordTable
{
    static constexpr uint64_t fnv1A64(std::string_view s)
    {
        uint64_t h = 1469598103934665603ull;
        for (const char i : s)
        {
            h ^= static_cast<unsigned char>(i);
            h *= 1099511628211ull;
        }

        return h ? h : 1ull;
    }

    static_assert((N & (N - 1)) == 0, "N must be power of two");
    struct Slot
    {
        uint64_t             hash = 0;
        std::string_view     key;
        SubTokenIdentifierId id;
        KeywordFlags         flags;
    };

    std::array<Slot, N> slots{};

    consteval void insert(const KeywordInfo& p)
    {
        const uint64_t h   = fnv1A64(p.key);
        size_t         idx = static_cast<size_t>(h) & (N - 1);
        while (slots[idx].hash)
        {
            if (slots[idx].hash == h && slots[idx].key == p.key)
            {
                slots[idx].id = p.id;
                return;
            }
            idx = (idx + 1) & (N - 1);
        }
        slots[idx] = Slot{h, p.key, p.id, p.flags};
    }

    template<size_t M>
    explicit consteval KeywordTable(const std::array<KeywordInfo, M>& arr)
    {
        static_assert(M < N, "Table too full; increase N");
        for (const auto& e : arr)
            insert(e);
    }

    SubTokenIdentifierId find(std::string_view s) const noexcept
    {
        uint64_t h   = fnv1A64(s);
        size_t   idx = h & (N - 1);
        while (true)
        {
            const Slot& sl = slots[idx];
            if (sl.hash == 0)
                return static_cast<SubTokenIdentifierId>(0);
            if (sl.hash == h && sl.key == s)
                return sl.id;
            idx = (idx + 1) & (N - 1);
        }
    }
};

SWC_END_NAMESPACE();
