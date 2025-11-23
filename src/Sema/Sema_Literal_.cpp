#include "pch.h"
#include "Lexer/LangSpec.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBoolLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok = job.token(srcViewRef(), tokRef());
    if (tok.is(TokenId::KwdTrue))
        setConstant(job.constMgr().boolTrue());
    else if (tok.is(TokenId::KwdFalse))
        setConstant(job.constMgr().boolFalse());
    else
        SWC_UNREACHABLE();

    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstStringLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok     = job.token(srcViewRef(), tokRef());
    const auto& srcView = job.compiler().srcView(srcViewRef());
    auto        str     = tok.string(srcView);

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
        const auto val = ConstantValue::makeString(job.ctx(), str);
        setConstant(job.constMgr().addConstant(val));
        return AstVisitStepResult::SkipChildren;
    }

    Utf8 result;
    result.reserve(str.size());

    auto parseHexEscape = [&](size_t& index, size_t maxDigits, uint32_t& valueOut) {
        uint32_t    value    = 0;
        size_t      digits   = 0;
        const auto& langSpec = job.compiler().global().langSpec();
        do
        {
            SWC_ASSERT(index + 1 < str.size());
            const unsigned char h = str[++index];
            SWC_ASSERT(langSpec.isHexNumber(h));

            value <<= 4;

            if (langSpec.isHexNumber(h))
            {
                const unsigned char c = (h >= 'A' && h <= 'F') ? (h + 32) : h;
                value += (c <= '9') ? (c - '0') : (10u + (c - 'a'));
            }

            ++digits;
        } while (digits < maxDigits && index + 1 < str.size() && langSpec.isHexNumber(str[index + 1]));
        valueOut = value;
    };

    // Decode escape sequences
    for (size_t i = 0; i < str.size(); ++i)
    {
        const char ch = str[i];

        if (ch != '\\')
        {
            result += ch;
            continue;
        }

        SWC_ASSERT(i + 1 < str.size());

        const char esc = str[++i];
        switch (esc)
        {
            case '0':
                result += '\0';
                break;
            case 'a':
                result += '\a';
                break;
            case 'b':
                result += '\b';
                break;
            case '\\':
                result += '\\';
                break;
            case 't':
                result += '\t';
                break;
            case 'n':
                result += '\n';
                break;
            case 'f':
                result += '\f';
                break;
            case 'r':
                result += '\r';
                break;
            case 'v':
                result += '\v';
                break;
            case '\'':
                result += '\'';
                break;
            case '\"':
                result += '\"';
                break;

            case 'x':
            {
                uint32_t cp = 0;
                parseHexEscape(i, 2, cp);
                result += cp;
                break;
            }

            case 'u':
            {
                uint32_t cp = 0;
                parseHexEscape(i, 4, cp);
                result += cp;
                break;
            }

            case 'U':
            {
                uint32_t cp = 0;
                parseHexEscape(i, 8, cp);
                result += cp;
                break;
            }

            default:
                SWC_UNREACHABLE();
        }
    }

    const auto val = ConstantValue::makeString(job.ctx(), result);
    setConstant(job.constMgr().addConstant(val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstBinaryLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok = job.token(srcViewRef(), tokRef());
    auto        str = tok.string(job.compiler().srcView(srcViewRef()));

    SWC_ASSERT(str.size() > 2);
    SWC_ASSERT(str[0] == '0' && (str[1] == 'b' || str[1] == 'B'));

    // Remove '0b' or '0B' prefix
    str = str.substr(2);

    // Remove separators
    const auto&     langSpec = job.compiler().global().langSpec();
    ConstantInt<64> value;
    for (const char c : str)
    {
        if (langSpec.isNumberSep(c))
            continue;
        value <<= 1;
        value |= (c == '1') ? 1 : 0;
    }

    // Convert the binary string to an integer constant
    // const auto val = ConstantValue::makeInt(job.ctx(), strNoSep, 2); // Base 2 (binary)
    // setConstant(job.constMgr().addConstant(val));
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstHexadecimalLiteral::semaPreNode(SemaJob& job)
{
    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstIntegerLiteral::semaPreNode(SemaJob& job)
{
    return AstVisitStepResult::SkipChildren;
}

SWC_END_NAMESPACE()
