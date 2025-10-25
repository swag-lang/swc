#pragma once
#include "Keyword.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

enum class TokenId : uint8_t
{
    Invalid,
    Blank,
    EndOfLine,
    EndOfFile,

    CommentLine,
    CommentMultiLine,

    StringLine,
    StringRaw,
    StringMultiLine,

    NumberHexadecimal,
    NumberBinary,
    NumberInteger,
    NumberFloat,

    Character,
    Identifier,
    Keyword,
    Intrinsic,
    Compiler,

    OpQuote,
    OpBackSlash,
    OpLeftParen,
    OpRightParen,
    OpLeftSquare,
    OpRightSquare,
    OpLeftCurly,
    OpRightCurly,
    OpSemiColon,
    OpComma,
    OpAt,
    OpQuestion,
    OpTilde,
    OpEqual,
    OpEqualEqual,
    OpEqualGreater,
    OpColon,
    OpExclamation,
    OpExclamationEqual,
    OpMinus,
    OpMinusEqual,
    OpMinusGreater,
    OpMinusMinus,
    OpPlus,
    OpPlusEqual,
    OpPlusPlus,
    OpAsterisk,
    OpAsteriskEqual,
    OpSlash,
    OpSlashEqual,
    OpAmpersand,
    OpAmpersandEqual,
    OpAmpersandAmpersand,
    OpVertical,
    OpVerticalEqual,
    OpVerticalVertical,
    OpCircumflex,
    OpCircumflexEqual,
    OpPercent,
    OpPercentEqual,
    OpDot,
    OpDotDot,
    OpDotDotDot,
    OpLower,
    OpLowerEqual,
    OpLowerEqualGreater,
    OpLowerLower,
    OpLowerLowerEqual,
    OpGreater,
    OpGreaterEqual,
    OpGreaterGreater,
    OpGreaterGreaterEqual
};

struct Token
{
    uint32_t start = 0;
    uint32_t len   = 0;

    TokenId id      = TokenId::Invalid;

    union
    {
        SubTokenIdentifierId subTokenIdentifierId; // Valid if id is Identifier
    };

    std::string_view toString(const SourceFile* file) const;
};

SWC_END_NAMESPACE();
