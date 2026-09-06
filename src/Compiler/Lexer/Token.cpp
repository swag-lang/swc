#include "pch.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Lexer/Lexer.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

std::string_view Token::string(const SourceView& srcView) const
{
    const auto* start = srcView.stringView().data();

    // In the case of an identifier, 'byteStart' is the index in the file identifier table.
    // And the real 'byteStart' is stored in that table
    if (id == TokenId::Identifier)
    {
        const auto& ids    = srcView.identifiers();
        const auto  offset = ids[byteStart].byteStart;
        return {start + offset, static_cast<size_t>(byteLength)};
    }

    return {start + byteStart, static_cast<size_t>(byteLength)};
}

uint32_t Token::crc(const SourceView& srcView) const
{
    SWC_ASSERT(id == TokenId::Identifier);
    return srcView.identifiers()[byteStart].crc;
}

SourceCodeRange Token::codeRange(const TaskContext& ctx, const SourceView& srcView) const
{
    SourceCodeRange codeRange;
    uint32_t        offset;
    if (id == TokenId::Identifier)
        offset = srcView.identifiers()[byteStart].byteStart;
    else
        offset = byteStart;
    codeRange.fromOffset(ctx, srcView, offset, byteLength);
    return codeRange;
}

std::string_view Token::toName(TokenId id)
{
    return TOKEN_ID_INFOS[static_cast<size_t>(id)].displayName;
}

std::string_view Token::toFamily(TokenId id)
{
    if (id == TokenId::Identifier)
        return "identifier";
    if (id == TokenId::EndOfFile)
        return "end of file";

    if (isSymbol(id))
        return "symbol";
    if (isKeyword(id))
        return "keyword";
    if (isType(id))
        return "type";
    if (isCompiler(id))
        return "compiler instruction";
    if (isIntrinsic(id))
        return "intrinsic";
    if (isModifier(id))
        return "modifier";
    if (isLiteral(id))
        return "literal";

    return "token";
}

std::string_view Token::intrinsicName(const TokenId id)
{
    if (!isIntrinsic(id) || isCompiler(id))
        return {};

    std::string_view name   = toName(id);
    constexpr auto   prefix = std::string_view{"Swag."};
    if (!name.starts_with(prefix))
        return {};
    name.remove_prefix(prefix.size());
    return name;
}

TokenId Token::intrinsicFromName(const std::string_view name)
{
    // The parser asks twice per intrinsic call and the formatter once per candidate piece, so
    // walking every token id with a string compare each time was 9 percent of a formatting
    // pass. The table is built once, from the same names.
    static const std::unordered_map<std::string_view, TokenId> intrinsics = [] {
        std::unordered_map<std::string_view, TokenId> table;
        for (uint32_t i = 0; i < static_cast<uint32_t>(TokenId::Count); ++i)
        {
            const auto             id        = static_cast<TokenId>(i);
            const std::string_view intrinsic = intrinsicName(id);
            if (!intrinsic.empty())
                table.emplace(intrinsic, id);
        }
        return table;
    }();

    const auto it = intrinsics.find(name);
    return it == intrinsics.end() ? TokenId::Invalid : it->second;
}

TokenId Token::toRelated(TokenId id)
{
    switch (id)
    {
        case TokenId::SymLeftParen:
            return TokenId::SymRightParen;
        case TokenId::SymRightParen:
            return TokenId::SymLeftParen;

        case TokenId::SymLeftBracket:
            return TokenId::SymRightBracket;
        case TokenId::SymRightBracket:
            return TokenId::SymLeftBracket;

        case TokenId::SymLeftCurly:
            return TokenId::SymRightCurly;
        case TokenId::SymRightCurly:
            return TokenId::SymLeftCurly;

        case TokenId::SymAttrStart:
            return TokenId::SymRightBracket;

        case TokenId::SymPipe:
            return TokenId::SymPipe;

        default:
            return TokenId::Invalid;
    }
}

TokenId Token::canonicalBinary(TokenId op)
{
    return isOpCompoundAssign(op) ? assignToBinary(op) : op;
}

TokenId Token::assignToBinary(TokenId op)
{
    switch (op)
    {
        case TokenId::SymPlusEqual:
            return TokenId::SymPlus;
        case TokenId::SymMinusEqual:
            return TokenId::SymMinus;
        case TokenId::SymAsteriskEqual:
            return TokenId::SymAsterisk;
        case TokenId::SymSlashEqual:
            return TokenId::SymSlash;
        case TokenId::SymAmpersandEqual:
            return TokenId::SymAmpersand;
        case TokenId::SymPipeEqual:
            return TokenId::SymPipe;
        case TokenId::SymCircumflexEqual:
            return TokenId::SymCircumflex;
        case TokenId::SymPercentEqual:
            return TokenId::SymPercent;
        case TokenId::SymLowerLowerEqual:
            return TokenId::SymLowerLower;
        case TokenId::SymGreaterGreaterEqual:
            return TokenId::SymGreaterGreater;
        case TokenId::SymEqual:
            return TokenId::SymEqual;
        default:
            break;
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
