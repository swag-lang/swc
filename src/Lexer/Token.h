#pragma once

enum class TokenId : uint32_t
{
    Invalid,
    Blank,
    Eol,
    LineComment,
    MultiLineComment,
    StringLiteral,
    NumberLiteral,
};

enum class SubTokenStringId : uint32_t
{
    LineString,
    RawString,
    MultiLineString,
};

enum class SubTokenNumberId : uint32_t
{
    Hexadecimal,
    Binary,
    Integer,
    Float,
};

struct Token
{
    TokenId  id    = TokenId::Invalid;
    uint32_t start = 0;
    uint32_t len   = 0;
    union
    {
        SubTokenStringId subTokenStringId;  // Valid if id is StringLiteral
        SubTokenNumberId subTokenNumberId;  // Valid if id is NumberLiteral
    };
};
