#pragma once

constexpr uint64_t fnv1a64(const char* s, size_t n)
{
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; ++i)
    {
        h ^= static_cast<unsigned char>(s[i]);
        h *= 1099511628211ull;
    }
    return h ? h : 1ull; // 0 réservé comme "vide"
}

enum class KeywordId : uint16_t
{
    Identifier = 0,
    // ... vos 300 ids (If, Else, While, Return, ...)
};

struct KWPair
{
    const char* key;
    uint16_t    len;
    KeywordId   id;
};

template<size_t N>
struct KWTable
{
    static_assert((N & (N - 1)) == 0, "N must be power of two");
    struct Slot
    {
        uint64_t    hash = 0; // 0 => vide
        const char* key  = nullptr;
        uint16_t    len  = 0;
        KeywordId   id   = KeywordId::Identifier;
    };
    std::array<Slot, N> slots{};

    consteval void insert(const KWPair& p)
    {
        const uint64_t h   = fnv1a64(p.key, p.len);
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
    consteval KWTable(const std::array<KWPair, M>& arr) :
        slots{}
    {
        static_assert(M < N, "Table too full; increase N");
        for (const auto& e : arr)
            insert(e);
    }

    KeywordId find(std::string_view s) const noexcept
    {
        if (s.size() == 0)
            return KeywordId::Identifier;
        uint64_t h   = fnv1a64(s.data(), s.size());
        size_t   idx = static_cast<size_t>(h) & (N - 1);
        while (true)
        {
            const Slot& sl = slots[idx];
            if (sl.hash == 0)
                return KeywordId::Identifier; // miss
            if (sl.hash == h && sl.len == s.size() &&
                std::memcmp(sl.key, s.data(), s.size()) == 0)
                return sl.id;
            idx = (idx + 1) & (N - 1);
        }
    }
};

constexpr std::array<KWPair, 14> K_KEYWORDS = {{
    {"if", 2, KeywordId::Identifier /* ex: KeywordId::If */},
    {"else", 4, KeywordId::Identifier /* Else */},
    {"for", 3, KeywordId::Identifier /* For */},
    {"while", 5, KeywordId::Identifier /* While */},
    {"return", 6, KeywordId::Identifier /* Return */},
    {"func", 4, KeywordId::Identifier /* Func */},
    {"var", 3, KeywordId::Identifier /* Var */},
    {"let", 3, KeywordId::Identifier /* Let */},
    {"true", 4, KeywordId::Identifier /* True */},
    {"false", 5, KeywordId::Identifier /* False */},
    {"null", 4, KeywordId::Identifier /* Null */},
    {"struct", 6, KeywordId::Identifier /* Struct */},
    {"enum", 4, KeywordId::Identifier /* Enum */},
    {"import", 6, KeywordId::Identifier /* Import */},
}};

constexpr KWTable<1024> gKeywordTable{K_KEYWORDS};
