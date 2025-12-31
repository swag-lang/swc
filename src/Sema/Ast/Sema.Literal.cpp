#include "pch.h"
#include "Core/Utf8Helper.h"
#include "Lexer/LangSpec.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void parseHexEscape(const Utf8& str, size_t& index, size_t maxDigits, char32_t& valueOut, const LangSpec& langSpec)
    {
        char32_t value  = 0;
        size_t   digits = 0;

        do
        {
            SWC_ASSERT(index + 1 < str.size());
            const unsigned char h = static_cast<unsigned char>(str[++index]);
            SWC_ASSERT(langSpec.isHexNumber(h));

            value <<= 4;

            if (langSpec.isHexNumber(h))
            {
                const unsigned char c = (h >= 'A' && h <= 'F') ? (h + 32) : h;
                value += (c <= '9') ? (c - '0') : (10u + (c - 'a'));
            }

            ++digits;
        } while (digits < maxDigits && index + 1 < str.size() && langSpec.isHexNumber(static_cast<unsigned char>(str[index + 1])));

        valueOut = value;
    }

    char32_t decodeEscapeSequence(const Utf8& str, size_t& index, const LangSpec& langSpec)
    {
        SWC_ASSERT(index < str.size());
        SWC_ASSERT(str[index] == '\\');
        SWC_ASSERT(index + 1 < str.size());

        const char esc = str[++index];

        switch (esc)
        {
            case '0': return '\0';
            case 'a': return '\a';
            case 'b': return '\b';
            case '\\': return '\\';
            case 't': return '\t';
            case 'n': return '\n';
            case 'f': return '\f';
            case 'r': return '\r';
            case 'v': return '\v';
            case '\'': return '\'';
            case '\"': return '\"';

            case 'x':
            {
                char32_t cp = 0;
                parseHexEscape(str, index, 2, cp, langSpec);
                return cp;
            }

            case 'u':
            {
                char32_t cp = 0;
                parseHexEscape(str, index, 4, cp, langSpec);
                return cp;
            }

            case 'U':
            {
                char32_t cp = 0;
                parseHexEscape(str, index, 8, cp, langSpec);
                return cp;
            }

            default:
                SWC_UNREACHABLE();
        }
    }
}

AstVisitStepResult AstBoolLiteral::semaPreNode(Sema& sema) const
{
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (tok.is(TokenId::KwdTrue))
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstTrue());
    else if (tok.is(TokenId::KwdFalse))
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstFalse());
    else
        SWC_UNREACHABLE();

    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstCharacterLiteral::semaPreNode(Sema& sema) const
{
    const auto&       ctx     = sema.ctx();
    const Token&      tok     = sema.token(srcViewRef(), tokRef());
    const SourceView& srcView = sema.compiler().srcView(srcViewRef());
    std::string_view  str     = tok.string(srcView);

    // Remove delimiters
    str = str.substr(1, str.size() - 2);

    char32_t value = 0;

    if (!tok.hasFlag(TokenFlagsE::Escaped))
    {
        auto [buf, wc, eat] = Utf8Helper::decodeOneChar(reinterpret_cast<const char8_t*>(str.data()), reinterpret_cast<const char8_t*>(str.data() + str.size()));
        value               = wc;
    }
    else
    {
        // Character literal contains a single escape sequence.
        const auto& langSpec = sema.compiler().global().langSpec();

        SWC_ASSERT(!str.empty());
        SWC_ASSERT(str[0] == '\\');

        size_t i = 0;
        value    = decodeEscapeSequence(str, i, langSpec);

        // We expect exactly one escape sequence and nothing else.
        SWC_ASSERT(i + 1 == str.size());
    }

    const auto val = ConstantValue::makeChar(ctx, value);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstStringLiteral::semaPreNode(Sema& sema) const
{
    const auto&       ctx     = sema.ctx();
    const Token&      tok     = sema.token(srcViewRef(), tokRef());
    const SourceView& srcView = sema.compiler().srcView(srcViewRef());
    std::string_view  str     = tok.string(srcView);

    // Remove delimiters
    switch (tok.id)
    {
        case TokenId::StringLine:
            str = str.substr(1, str.size() - 2);
            break;
        case TokenId::StringMultiLine:
            str = str.substr(3, str.size() - 6);
            break;
        case TokenId::StringRaw:
            str = str.substr(2, str.size() - 4);
            break;
        default:
            SWC_UNREACHABLE();
    }

    // Fast path if no escape sequence inside the string
    if (!tok.hasFlag(TokenFlagsE::Escaped))
    {
        const auto val = ConstantValue::makeString(ctx, str);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
        return AstVisitStepResult::SkipChildren;
    }

    Utf8 result;
    result.reserve(str.size());

    const auto& langSpec = sema.compiler().global().langSpec();

    // Decode escape sequences
    for (size_t i = 0; i < str.size(); ++i)
    {
        const char ch = str[i];

        if (ch != '\\')
        {
            result += ch;
            continue;
        }

        const char32_t cp = decodeEscapeSequence(str, i, langSpec);
        result += cp;
    }

    const auto val = ConstantValue::makeString(ctx, result);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstBinaryLiteral::semaPreNode(Sema& sema) const
{
    const auto& ctx = sema.ctx();
    const auto& tok = sema.token(srcViewRef(), tokRef());
    auto        str = tok.string(sema.compiler().srcView(srcViewRef()));

    SWC_ASSERT(str.size() > 2);
    SWC_ASSERT(str[0] == '0' && (str[1] == 'b' || str[1] == 'B'));

    // Remove '0b' or '0B' prefix
    str = str.substr(2);

    const auto& langSpec = sema.compiler().global().langSpec();
    ApsInt      value;
    for (const char c : str)
    {
        if (langSpec.isNumberSep(c))
            continue;

        bool over = false;
        value.logicalShiftLeft(1, over);
        if (over)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
            return AstVisitStepResult::Stop;
        }

        value.bitwiseOr((c == '1') ? 1 : 0);
    }

    // Convert the binary string to an integer constant
    value.setUnsigned(true);
    const auto val = ConstantValue::makeIntUnsized(ctx, value, TypeInfo::Sign::Unsigned);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstHexaLiteral::semaPreNode(Sema& sema) const
{
    const auto& ctx = sema.ctx();
    const auto& tok = sema.token(srcViewRef(), tokRef());
    auto        str = tok.string(sema.compiler().srcView(srcViewRef()));

    SWC_ASSERT(str.size() > 2);
    SWC_ASSERT(str[0] == '0' && (str[1] == 'x' || str[1] == 'X'));

    // Remove '0x' or '0X' prefix
    str = str.substr(2);

    const auto& langSpec = sema.compiler().global().langSpec();
    ApsInt      value;
    for (const char c : str)
    {
        if (langSpec.isNumberSep(c))
            continue;

        bool over = false;
        value.logicalShiftLeft(4, over); // multiply by 16
        if (over)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
            return AstVisitStepResult::Stop;
        }

        const unsigned char h     = (c >= 'A' && c <= 'F') ? (c + 32) : c;
        const size_t        digit = (c <= '9') ? (c - '0') : (10u + (h - 'a'));
        value.bitwiseOr(digit & 0xF);
    }

    // Convert the hexadecimal string to an integer constant
    value.setUnsigned(true);
    const auto val = ConstantValue::makeIntUnsized(ctx, value, TypeInfo::Sign::Unsigned);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstIntegerLiteral::semaPreNode(Sema& sema) const
{
    const auto& ctx = sema.ctx();
    const auto& tok = sema.token(srcViewRef(), tokRef());
    const auto  str = tok.string(sema.compiler().srcView(srcViewRef()));

    SWC_ASSERT(!str.empty());

    const auto& langSpec = sema.compiler().global().langSpec();

    ApInt value;
    for (const char c : str)
    {
        if (langSpec.isNumberSep(c))
            continue;

        if (c < '0' || c > '9')
        {
            // Lexer should prevent this
            SWC_ASSERT(false && "Invalid digit in decimal literal");
            continue;
        }

        const size_t digit = static_cast<size_t>(c - '0');

        // multiply the current value by 10
        bool over = false;
        value.mul(10, over);
        if (over)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
            return AstVisitStepResult::Stop;
        }

        // add a digit
        value.add(digit, over);
        if (over)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
            return AstVisitStepResult::Stop;
        }
    }

    const auto val = ConstantValue::makeIntUnsized(ctx, ApsInt{value, false}, TypeInfo::Sign::Unknown);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstFloatLiteral::semaPreNode(Sema& sema) const
{
    const auto& ctx = sema.ctx();
    const auto& tok = sema.token(srcViewRef(), tokRef());
    const auto  str = tok.string(sema.compiler().srcView(srcViewRef()));

    SWC_ASSERT(!str.empty());

    const auto& langSpec = sema.compiler().global().langSpec();

    ApInt intValue;

    bool seenDot      = false;
    bool seenExp      = false;
    bool expNegative  = false;
    bool expSignSeen  = false;
    bool expDigitSeen = false;

    size_t  fracDigits = 0; // number of digits AFTER '.'
    int64_t expValue   = 0; // exponent part AFTER 'e'

    for (const char c : str)
    {
        // skip numeric separators (NO cleaned copy)
        if (langSpec.isNumberSep(c))
            continue;

        if (langSpec.isDigit(c))
        {
            const uint32_t digit = static_cast<uint32_t>(c - '0');

            if (!seenExp)
            {
                bool over = false;
                intValue.mul(10, over);
                if (over)
                {
                    SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
                    return AstVisitStepResult::Stop;
                }

                intValue.add(digit, over);
                if (over)
                {
                    SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
                    return AstVisitStepResult::Stop;
                }

                if (seenDot)
                    ++fracDigits;
            }
            else
            {
                expDigitSeen = true;

                // Avoid overflow of expValue
                if (expValue <= (INT64_MAX - digit) / 10)
                {
                    expValue = expValue * 10 + digit;
                }
                else
                {
                    SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
                    return AstVisitStepResult::Stop;
                }
            }
            continue;
        }

        if (c == '.' && !seenExp)
        {
            if (seenDot)
            {
                SWC_ASSERT(false && "Multiple '.' in float literal");
                continue;
            }

            seenDot = true;
            continue;
        }

        if ((c == 'e' || c == 'E') && !seenExp)
        {
            seenExp = true;
            continue;
        }

        if ((c == '+' || c == '-') && seenExp && !expSignSeen && !expDigitSeen)
        {
            expSignSeen = true;
            expNegative = (c == '-');
            continue;
        }

        SWC_UNREACHABLE();
    }

    // Exponent offset from decimal digits
    int64_t totalExp10 = 0;

    if (seenExp)
    {
        SWC_ASSERT(expDigitSeen);
        totalExp10 = expNegative ? -expValue : expValue;
    }

    // Apply fractional shift: e.g., 1.234e2  => 1234 * 10^(2 - 3) = 1234 * 10^-1
    if (fracDigits > 0)
    {
        if (totalExp10 < (std::numeric_limits<int64_t>::min)() + static_cast<int64_t>(fracDigits))
        {
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, srcViewRef(), tokRef());
            return AstVisitStepResult::Stop;
        }

        totalExp10 -= static_cast<int64_t>(fracDigits);
    }

    ApFloat value;
    value.set(intValue, totalExp10);

    const ConstantValue val = ConstantValue::makeFloatUnsized(ctx, value);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return AstVisitStepResult::SkipChildren;
}

SWC_END_NAMESPACE()
