#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Token.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool foldedNamespaceIsReserved(std::string_view name)
    {
        Utf8 folded = name;
        folded.make_lower();
        return folded == "swag";
    }
}

SWC_TEST_BEGIN(LangSpec_CharacterClassesCoverEveryByteAndOutOfRangeValues)
{
    const LangSpec&            spec    = ctx.global().langSpec();
    constexpr std::string_view escapes = "0abtnfrv\\'\"xuU";
    for (uint32_t c = 0; c < 512; ++c)
    {
        const bool alpha  = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        const bool digit  = c >= '0' && c <= '9';
        const bool letter = alpha || c == '_';
        const bool blank  = c == ' ' || c == '\t' || c == '\f' || c == '\v';
        const bool eol    = c == '\r' || c == '\n';
        const bool hex    = digit || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        const bool escape = c < 256 && escapes.find(static_cast<char>(c)) != std::string_view::npos;
        if (spec.isAscii(c) != (c < 128) ||
            spec.isBlank(c) != blank ||
            spec.isWhiteSpace(c) != (blank || eol) ||
            spec.isEol(c) != eol ||
            spec.isDigit(c) != digit ||
            spec.isLetter(c) != letter ||
            spec.isHexNumber(c) != hex ||
            spec.isBinNumber(c) != (c == '0' || c == '1') ||
            spec.isNumberSep(c) != (c == '_') ||
            spec.isIdentifierStart(c) != (letter || c == '#') ||
            spec.isIdentifierPart(c) != (letter || digit) ||
            spec.isEscape(c) != escape ||
            spec.isOption(c) != (alpha || c == '-'))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(LangSpec_ReservedNamespaceMatchesOwningFoldOracle)
{
    for (uint32_t position = 0; position < 4; ++position)
    {
        for (uint32_t byte = 0; byte < 256; ++byte)
        {
            std::array<char, 4> name{'s', 'w', 'a', 'g'};
            name[position] = static_cast<char>(byte);
            const std::string_view view(name.data(), name.size());
            if (LangSpec::isReservedNamespace(view) != foldedNamespaceIsReserved(view))
                return Result::Error;
        }
    }
    for (uint32_t mask = 0; mask < 16; ++mask)
    {
        std::array<char, 4> name{'s', 'w', 'a', 'g'};
        for (uint32_t position = 0; position < name.size(); ++position)
            if (mask & (1u << position))
                name[position] = static_cast<char>(name[position] - 'a' + 'A');
        if (!LangSpec::isReservedNamespace(std::string_view(name.data(), name.size())))
            return Result::Error;
    }
    for (const auto name : {std::string_view{}, std::string_view{"swa"}, std::string_view{"swagx"}, std::string_view{"xswag"}})
        if (LangSpec::isReservedNamespace(name))
            return Result::Error;
    const Utf8 longName(1024, 'S');
    if (LangSpec::isReservedNamespace(longName))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Token_IntrinsicNamesRoundTripThroughTheDefinitionTable)
{
    for (uint32_t index = 0; index < static_cast<uint32_t>(TokenId::Count); ++index)
    {
        const auto id   = static_cast<TokenId>(index);
        const auto name = Token::intrinsicName(id);
        if (Token::isIntrinsic(id) && !Token::isCompiler(id) && Token::toName(id).starts_with("Swag."))
        {
            if (name.empty() || Token::intrinsicFromName(name) != id)
                return Result::Error;
        }
        else if (!name.empty())
            return Result::Error;
    }
    for (const auto name : {std::string_view{}, std::string_view{"Swag.memcpy"}, std::string_view{"missingIntrinsic"}})
        if (Token::intrinsicFromName(name) != TokenId::Invalid)
            return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
