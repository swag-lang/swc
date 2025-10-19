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

struct Token
{
    TokenId  id    = TokenId::Invalid;
    uint32_t start = 0;
    uint32_t len   = 0;
};
