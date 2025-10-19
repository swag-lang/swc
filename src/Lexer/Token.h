#pragma once

class SourceFile;

enum class TokenId : uint32_t
{
    Invalid,
    Blank,
    Eol,
    Comment,
    StringLiteral,
    NumberLiteral,
};

enum class SubTokenStringId : uint32_t
{
    Line,
    Raw,
    MultiLine,
};

enum class SubTokenNumberId : uint32_t
{
    Hexadecimal,
    Binary,
    Integer,
    Float,
};

enum class SubTokenCommentId : uint32_t
{
    Line,
    MultiLine,
};

struct Token
{
    TokenId  id    = TokenId::Invalid;
    uint32_t start = 0;
    uint32_t len   = 0;
    union
    {
        SubTokenStringId  subTokenStringId;  // Valid if id is StringLiteral
        SubTokenNumberId  subTokenNumberId;  // Valid if id is NumberLiteral
        SubTokenCommentId subTokenCommentId; // Valid if id is Comment
    };

    std::string_view toString(const SourceFile* file) const;
};
