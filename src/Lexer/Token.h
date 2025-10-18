#pragma once

enum class TokenId : uint32_t
{
};

struct Token
{
    TokenId  id;
    uint32_t start;
    uint32_t end;
};
