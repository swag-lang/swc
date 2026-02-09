#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

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

Result AstBoolLiteral::semaPreNode(Sema& sema) const
{
    const auto& tok = sema.token(codeRef());
    if (tok.is(TokenId::KwdTrue))
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstTrue());
    else if (tok.is(TokenId::KwdFalse))
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstFalse());
    else
        SWC_UNREACHABLE();

    return Result::SkipChildren;
}

Result AstNullLiteral::semaPreNode(Sema& sema)
{
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstNull());
    return Result::SkipChildren;
}

Result AstUndefinedExpr::semaPreNode(Sema& sema)
{
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstUndefined());
    return Result::SkipChildren;
}

Result AstCharacterLiteral::semaPreNode(Sema& sema) const
{
    auto&             ctx     = sema.ctx();
    const Token&      tok     = sema.token(codeRef());
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
    return Result::SkipChildren;
}

Result AstStringLiteral::semaPreNode(Sema& sema) const
{
    auto&             ctx     = sema.ctx();
    const Token&      tok     = sema.token(codeRef());
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
        return Result::SkipChildren;
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
    return Result::SkipChildren;
}

Result AstBinaryLiteral::semaPreNode(Sema& sema) const
{
    auto&       ctx = sema.ctx();
    const auto& tok = sema.token(codeRef());
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
            return SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());

        value.bitwiseOr((c == '1') ? 1 : 0);
    }

    // Convert the binary string to an integer constant
    value.setUnsigned(true);
    const auto val = ConstantValue::makeIntUnsized(ctx, value, TypeInfo::Sign::Unsigned);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return Result::SkipChildren;
}

Result AstHexaLiteral::semaPreNode(Sema& sema) const
{
    auto&       ctx = sema.ctx();
    const auto& tok = sema.token(codeRef());
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
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
            return Result::Error;
        }

        const unsigned char h     = (c >= 'A' && c <= 'F') ? (c + 32) : c;
        const size_t        digit = (c <= '9') ? (c - '0') : (10u + (h - 'a'));
        value.bitwiseOr(digit & 0xF);
    }

    // Convert the hexadecimal string to an integer constant
    value.setUnsigned(true);
    const auto val = ConstantValue::makeIntUnsized(ctx, value, TypeInfo::Sign::Unsigned);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return Result::SkipChildren;
}

Result AstIntegerLiteral::semaPreNode(Sema& sema) const
{
    auto&       ctx = sema.ctx();
    const auto& tok = sema.token(codeRef());
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
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
            return Result::Error;
        }

        // add a digit
        value.add(digit, over);
        if (over)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
            return Result::Error;
        }
    }

    const auto val = ConstantValue::makeIntUnsized(ctx, ApsInt{value, false}, TypeInfo::Sign::Unknown);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return Result::SkipChildren;
}

Result AstFloatLiteral::semaPreNode(Sema& sema) const
{
    auto&       ctx = sema.ctx();
    const auto& tok = sema.token(codeRef());
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
                    SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
                    return Result::Error;
                }

                intValue.add(digit, over);
                if (over)
                {
                    SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
                    return Result::Error;
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
                    SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
                    return Result::Error;
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
            SemaError::raise(sema, DiagnosticId::sema_err_number_too_big, codeRef());
            return Result::Error;
        }

        totalExp10 -= static_cast<int64_t>(fracDigits);
    }

    ApFloat value;
    value.set(intValue, totalExp10);

    const ConstantValue val = ConstantValue::makeFloatUnsized(ctx, value);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return Result::SkipChildren;
}

Result AstStructLiteral::semaPostNode(Sema& sema)
{
    SmallVector<AstNodeRef> children;
    collectChildren(children, sema.ast());

    SmallVector<TypeRef>       memberTypes;
    SmallVector<IdentifierRef> memberNames;
    SmallVector<SourceCodeRef> memberCodeRefs;
    memberTypes.reserve(children.size());
    memberNames.reserve(children.size());
    memberCodeRefs.reserve(children.size());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    values.reserve(children.size());

    for (const AstNodeRef& child : children)
    {
        const AstNode& childNode = sema.node(child);
        if (childNode.is(AstNodeId::NamedArgument))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else
            memberNames.push_back(IdentifierRef::invalid());

        SemaNodeView nodeView(sema, child);
        SWC_ASSERT(nodeView.typeRef.isValid());
        memberTypes.push_back(nodeView.typeRef);
        memberCodeRefs.push_back(childNode.codeRef());
        allConstant = allConstant && nodeView.cstRef.isValid();
        values.push_back(nodeView.cstRef);
    }

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateStruct(sema.ctx(), memberNames, values, memberCodeRefs);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAggregateStruct(memberNames, memberTypes, memberCodeRefs));
        sema.setType(sema.curNodeRef(), typeRef);
    }

    sema.setIsValue(sema.curNodeRef());
    return Result::Continue;
}

Result AstStructInitializerList::semaPostNode(Sema& sema) const
{
    SmallVector<AstNodeRef> children;
    AstNode::collectChildren(children, sema.ast(), spanArgsRef);

    SmallVector<TypeRef>       memberTypes;
    SmallVector<IdentifierRef> memberNames;
    SmallVector<SourceCodeRef> memberCodeRefs;
    memberTypes.reserve(children.size());
    memberNames.reserve(children.size());
    memberCodeRefs.reserve(children.size());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    values.reserve(children.size());

    for (const AstNodeRef& child : children)
    {
        const AstNode& childNode = sema.node(child);
        if (childNode.is(AstNodeId::NamedArgument))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else
            memberNames.push_back(IdentifierRef::invalid());

        SemaNodeView nodeView(sema, child);
        SWC_ASSERT(nodeView.typeRef.isValid());
        memberTypes.push_back(nodeView.typeRef);
        memberCodeRefs.push_back(childNode.codeRef());
        allConstant = allConstant && nodeView.cstRef.isValid();
        values.push_back(nodeView.cstRef);
    }

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateStruct(sema.ctx(), memberNames, values, memberCodeRefs);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAggregateStruct(memberNames, memberTypes, memberCodeRefs));
        sema.setType(sema.curNodeRef(), typeRef);
    }

    sema.setIsValue(sema.curNodeRef());

    const SemaNodeView nodeWhatView(sema, nodeWhatRef);
    SemaNodeView       initView(sema, sema.curNodeRef());
    RESULT_VERIFY(Cast::cast(sema, initView, nodeWhatView.typeRef, CastKind::Initialization));

    return Result::Continue;
}

Result AstArrayLiteral::semaPostNode(Sema& sema)
{
    // 'AstArrayLiteral' directly contains the element expressions in `spanChildrenRef`.
    SmallVector<AstNodeRef> elements;
    collectChildren(elements, sema.ast());
    if (elements.empty())
        return SemaError::raise(sema, DiagnosticId::sema_err_empty_array_literal, sema.curNodeRef());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    SmallVector<TypeRef>     elemTypes;
    values.reserve(elements.size());
    elemTypes.reserve(elements.size());

    for (const auto& child : elements)
    {
        SemaNodeView nodeView(sema, child);
        SWC_ASSERT(nodeView.typeRef.isValid());
        values.push_back(nodeView.cstRef);
        elemTypes.push_back(nodeView.typeRef);
        allConstant = allConstant && nodeView.cstRef.isValid();
    }

    SmallVector<SourceCodeRef> elementCodeRefs;
    elementCodeRefs.reserve(elements.size());
    for (const auto& element : elements)
        elementCodeRefs.push_back(sema.node(element).codeRef());

    const TypeRef aggregateTypeRef = sema.typeMgr().addType(TypeInfo::makeAggregateArray(elemTypes, elementCodeRefs));

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateArray(sema.ctx(), values, elementCodeRefs);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        sema.setType(sema.curNodeRef(), aggregateTypeRef);
    }

    sema.setIsValue(*this);
    return Result::Continue;
}

SWC_END_NAMESPACE();
