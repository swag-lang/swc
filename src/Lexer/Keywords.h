#pragma once

enum class SubTokenIdentifierId : uint16_t
{
    Identifier = 0,
};

constexpr uint64_t fnv1A64(const char* s, size_t n)
{
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; ++i)
    {
        h ^= static_cast<unsigned char>(s[i]);
        h *= 1099511628211ull;
    }

    return h ? h : 1ull;
}

struct KwPair
{
    const char*          key;
    uint16_t             len;
    SubTokenIdentifierId id;
};

template<size_t N>
struct KwTable
{
    static_assert((N & (N - 1)) == 0, "N must be power of two");
    struct Slot
    {
        uint64_t             hash = 0;
        const char*          key  = nullptr;
        uint16_t             len  = 0;
        SubTokenIdentifierId id   = SubTokenIdentifierId::Identifier;
    };
    std::array<Slot, N> slots{};

    consteval void insert(const KwPair& p)
    {
        const uint64_t h   = fnv1A64(p.key, p.len);
        size_t         idx = static_cast<size_t>(h) & (N - 1);
        while (slots[idx].hash)
        {
            if (slots[idx].hash == h && slots[idx].len == p.len &&
                std::memcmp(slots[idx].key, p.key, p.len) == 0)
            {
                slots[idx].id = p.id;
                return;
            }
            idx = (idx + 1) & (N - 1);
        }
        slots[idx] = Slot{h, p.key, p.len, p.id};
    }

    template<size_t M>
    explicit consteval KwTable(const std::array<KwPair, M>& arr) :
        slots{}
    {
        static_assert(M < N, "Table too full; increase N");
        for (const auto& e : arr)
            insert(e);
    }

    SubTokenIdentifierId find(std::string_view s) const noexcept
    {
        if (s.empty())
            return SubTokenIdentifierId::Identifier;
        uint64_t h   = fnv1A64(s.data(), s.size());
        size_t   idx = static_cast<size_t>(h) & (N - 1);
        while (true)
        {
            const Slot& sl = slots[idx];
            if (sl.hash == 0)
                return SubTokenIdentifierId::Identifier; // miss
            if (sl.hash == h && sl.len == s.size() &&
                std::memcmp(sl.key, s.data(), s.size()) == 0)
                return sl.id;
            idx = (idx + 1) & (N - 1);
        }
    }
};

constexpr std::array<KwPair, 14> K_KEYWORDS = {{
    {"if", 2, SubTokenIdentifierId::Identifier /* ex: KeywordId::If */},
    {"else", 4, SubTokenIdentifierId::Identifier /* Else */},
    {"for", 3, SubTokenIdentifierId::Identifier /* For */},
    {"while", 5, SubTokenIdentifierId::Identifier /* While */},
    {"return", 6, SubTokenIdentifierId::Identifier /* Return */},
    {"func", 4, SubTokenIdentifierId::Identifier /* Func */},
    {"var", 3, SubTokenIdentifierId::Identifier /* Var */},
    {"let", 3, SubTokenIdentifierId::Identifier /* Let */},
    {"true", 4, SubTokenIdentifierId::Identifier /* True */},
    {"false", 5, SubTokenIdentifierId::Identifier /* False */},
    {"null", 4, SubTokenIdentifierId::Identifier /* Null */},
    {"struct", 6, SubTokenIdentifierId::Identifier /* Struct */},
    {"enum", 4, SubTokenIdentifierId::Identifier /* Enum */},
    {"import", 6, SubTokenIdentifierId::Identifier /* Import */},
}};

constexpr KwTable<1024> G_KEYWORD_TABLE{K_KEYWORDS};
