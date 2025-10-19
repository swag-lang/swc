#pragma once

enum class TokenId : uint32_t
{
    Invalid,
    Blank,
    Eol,
    LineComment,
    MultiLineComment,
    StringLiteral,
};

enum class SubTokenStringId : uint32_t
{
    LineString,
    RawString,
    MultiLineString,
};

struct Token
{
    TokenId  id    = TokenId::Invalid;
    uint32_t start = 0;
    uint32_t len   = 0;
    union
    {
        SubTokenStringId subTokenStringId;  // Valid if id is StringLiteral 
    };
};
