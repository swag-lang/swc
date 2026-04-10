#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result raiseNumberTooBig(Sema& sema, const SourceCodeRef& codeRef, std::string_view value)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_number_too_big, codeRef);
        diag.addArgument(Diagnostic::ARG_VALUE, value);
        diag.report(sema.ctx());
        return Result::Error;
    }

    uint32_t stringDelimiterSize(TokenId id)
    {
        switch (id)
        {
            case TokenId::StringLine:
                return 1;
            case TokenId::StringMultiLine:
                return 3;
            case TokenId::StringRaw:
                return 2;
            default:
                SWC_UNREACHABLE();
        }
    }

    uint32_t stringAlignColumn(const Token& tok, const SourceView& srcView)
    {
        SWC_ASSERT(tok.isAny({TokenId::StringMultiLine, TokenId::StringRaw}));

        const auto it = std::ranges::upper_bound(srcView.lines(), tok.byteStart);
        SWC_ASSERT(it != srcView.lines().begin());
        return tok.byteStart - *std::prev(it) + stringDelimiterSize(tok.id);
    }

    // Trim continuation-line indentation up to the opening delimiter column,
    // but never invent padding when a line starts earlier on purpose.
    Utf8 normalizeMultilineLiteral(std::string_view str, uint32_t alignColumn, const LangSpec& langSpec)
    {
        Utf8 result;
        result.reserve(str.size());

        bool atLineStart = false;
        for (size_t i = 0; i < str.size();)
        {
            if (atLineStart)
            {
                uint32_t eat = 0;
                while (eat < alignColumn && i < str.size() && langSpec.isBlank(static_cast<unsigned char>(str[i])))
                {
                    ++i;
                    ++eat;
                }

                atLineStart = false;
                if (i >= str.size())
                    break;
            }

            if (str[i] == '\r')
            {
                result += '\r';
                ++i;
                if (i < str.size() && str[i] == '\n')
                {
                    result += '\n';
                    ++i;
                }

                atLineStart = true;
                continue;
            }

            if (str[i] == '\n')
            {
                result += '\n';
                ++i;
                atLineStart = true;
                continue;
            }

            result += str[i];
            ++i;
        }

        return result;
    }

    Utf8 foldEscapedEols(std::string_view str)
    {
        Utf8 result;
        result.reserve(str.size());

        for (size_t i = 0; i < str.size(); ++i)
        {
            if (str[i] != '\\' || i + 1 >= str.size())
            {
                result += str[i];
                continue;
            }

            if (str[i + 1] == '\n')
            {
                ++i;
                continue;
            }

            if (str[i + 1] == '\r')
            {
                ++i;
                if (i + 1 < str.size() && str[i + 1] == '\n')
                    ++i;
                continue;
            }

            result += str[i];
        }

        return result;
    }

    void parseHexEscape(const Utf8& str, size_t& index, size_t maxDigits, char32_t& valueOut, const LangSpec& langSpec)
    {
        char32_t value  = 0;
        size_t   digits = 0;

        do
        {
            SWC_ASSERT(index + 1 < str.size());
            const auto h = static_cast<unsigned char>(str[++index]);
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

    TypeRef literalRuntimeStorageTypeRef(const SemaNodeView& view)
    {
        if (!view.type())
            return TypeRef::invalid();
        if (view.hasConstant())
            return TypeRef::invalid();
        if (!view.type()->isAggregateStruct() && !view.type()->isAggregateArray())
            return TypeRef::invalid();
        return view.typeRef();
    }

    Result completeLiteralRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar, typeRef));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueLiteralRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, "__literal_runtime_storage");
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        return *(symVariable);
    }

    Result attachLiteralRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SemaNodeView& literalView)
    {
        const TypeRef runtimeStorageTypeRef = literalRuntimeStorageTypeRef(literalView);
        if (runtimeStorageTypeRef.isInvalid())
            return Result::Continue;
        if (sema.isGlobalScope())
            return Result::Continue;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(sema.curNodeRef(), payload);
            }

            payload->runtimeStorageSym = boundStorage;
            return Result::Continue;
        }

        auto& storageSym = registerUniqueLiteralRuntimeStorageSymbol(sema, node);
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeLiteralRuntimeStorageSymbol(sema, storageSym, runtimeStorageTypeRef));

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeStorageSym = &storageSym;
        return Result::Continue;
    }

    template<typename ResolveChildBindingTypeFunc>
    Result pushLiteralChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, ResolveChildBindingTypeFunc&& resolveChildBindingType)
    {
        const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
        for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
        {
            TypeRef bindingTypeRef = TypeRef::invalid();
            SWC_RESULT(resolveChildBindingType(bindingTypes[bindingIndex - 1], bindingTypeRef));
            if (!bindingTypeRef.isValid())
                continue;

            auto frame = sema.frame();
            frame.pushBindingType(bindingTypeRef);
            sema.pushFramePopOnPostChild(frame, childRef);
            break;
        }

        return Result::Continue;
    }
}

Result AstBoolLiteral::semaPreNode(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
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
    const TaskContext& ctx     = sema.ctx();
    const Token&       tok     = sema.token(codeRef());
    const SourceView&  srcView = sema.compiler().srcView(srcViewRef());
    std::string_view   str     = tok.string(srcView);

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
        const LangSpec& langSpec = sema.compiler().global().langSpec();

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
    const TaskContext& ctx     = sema.ctx();
    const Token&       tok     = sema.token(codeRef());
    const SourceView&  srcView = sema.compiler().srcView(srcViewRef());
    std::string_view   str     = tok.string(srcView);

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

    const LangSpec&  langSpec = sema.compiler().global().langSpec();
    Utf8             normalized;
    std::string_view value = str;

    if (tok.isAny({TokenId::StringMultiLine, TokenId::StringRaw}) && tok.hasFlag(TokenFlagsE::EolInside))
    {
        normalized = normalizeMultilineLiteral(str, stringAlignColumn(tok, srcView), langSpec);
        normalized = foldEscapedEols(normalized);
        value      = normalized;
    }

    if (tok.id == TokenId::StringRaw)
    {
        const auto val = ConstantValue::makeString(ctx, value);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
        return Result::SkipChildren;
    }

    // Fast path if no escape sequence inside the string
    if (!tok.hasFlag(TokenFlagsE::Escaped))
    {
        const auto val = ConstantValue::makeString(ctx, value);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
        return Result::SkipChildren;
    }

    Utf8 result;
    result.reserve(value.size());

    // Decode escape sequences
    for (size_t i = 0; i < value.size(); ++i)
    {
        const char ch = value[i];

        if (ch != '\\')
        {
            result += ch;
            continue;
        }

        const char32_t cp = decodeEscapeSequence(value, i, langSpec);
        result += cp;
    }

    const auto val = ConstantValue::makeString(ctx, result);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return Result::SkipChildren;
}

Result AstBinaryLiteral::semaPreNode(Sema& sema) const
{
    const TaskContext& ctx    = sema.ctx();
    const Token&       tok    = sema.token(codeRef());
    const auto         tokStr = tok.string(sema.compiler().srcView(srcViewRef()));
    auto               str    = tokStr;

    SWC_ASSERT(str.size() > 2);
    SWC_ASSERT(str[0] == '0' && (str[1] == 'b' || str[1] == 'B'));

    // Remove '0b' or '0B' prefix
    str = str.substr(2);

    const LangSpec& langSpec = sema.compiler().global().langSpec();
    ApsInt          value;
    for (const char c : str)
    {
        if (langSpec.isNumberSep(c))
            continue;

        bool over = false;
        value.logicalShiftLeft(1, over);
        if (over)
            return raiseNumberTooBig(sema, codeRef(), tokStr);

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
    const TaskContext& ctx    = sema.ctx();
    const Token&       tok    = sema.token(codeRef());
    const auto         tokStr = tok.string(sema.compiler().srcView(srcViewRef()));
    auto               str    = tokStr;

    SWC_ASSERT(str.size() > 2);
    SWC_ASSERT(str[0] == '0' && (str[1] == 'x' || str[1] == 'X'));

    // Remove '0x' or '0X' prefix
    str = str.substr(2);

    const LangSpec& langSpec = sema.compiler().global().langSpec();
    ApsInt          value;
    for (const char c : str)
    {
        if (langSpec.isNumberSep(c))
            continue;

        bool over = false;
        value.logicalShiftLeft(4, over); // multiply by 16
        if (over)
        {
            raiseNumberTooBig(sema, codeRef(), tokStr);
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
    const TaskContext& ctx = sema.ctx();
    const Token&       tok = sema.token(codeRef());
    const auto         str = tok.string(sema.compiler().srcView(srcViewRef()));

    SWC_ASSERT(!str.empty());

    const LangSpec& langSpec = sema.compiler().global().langSpec();

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

        const auto digit = static_cast<size_t>(c - '0');

        // multiply the current value by 10
        bool over = false;
        value.mul(10, over);
        if (over)
        {
            raiseNumberTooBig(sema, codeRef(), str);
            return Result::Error;
        }

        // add a digit
        value.add(digit, over);
        if (over)
        {
            raiseNumberTooBig(sema, codeRef(), str);
            return Result::Error;
        }
    }

    const auto val = ConstantValue::makeIntUnsized(ctx, ApsInt{value, false}, TypeInfo::Sign::Unknown);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
    return Result::SkipChildren;
}

Result AstFloatLiteral::semaPreNode(Sema& sema) const
{
    const TaskContext& ctx = sema.ctx();
    const Token&       tok = sema.token(codeRef());
    const auto         str = tok.string(sema.compiler().srcView(srcViewRef()));

    SWC_ASSERT(!str.empty());

    const LangSpec& langSpec = sema.compiler().global().langSpec();

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
            const auto digit = static_cast<uint32_t>(c - '0');

            if (!seenExp)
            {
                bool over = false;
                intValue.mul(10, over);
                if (over)
                {
                    raiseNumberTooBig(sema, codeRef(), str);
                    return Result::Error;
                }

                intValue.add(digit, over);
                if (over)
                {
                    raiseNumberTooBig(sema, codeRef(), str);
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
                    raiseNumberTooBig(sema, codeRef(), str);
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
            raiseNumberTooBig(sema, codeRef(), str);
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

Result AstStructLiteral::semaPostNode(Sema& sema) const
{
    SmallVector<AstNodeRef> children;
    collectChildren(children, sema.ast());
    // Auto-name fields from identifiers only for free tuple literals (no binding type).
    const bool autoName = sema.frame().bindingTypes().empty();
    SWC_RESULT(SemaHelpers::finalizeAggregateStruct(sema, children, autoName));
    const SemaNodeView literalView = sema.curViewNodeTypeConstant();
    return attachLiteralRuntimeStorageIfNeeded(sema, *this, literalView);
}

Result AstStructLiteral::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SmallVector<AstNodeRef> children;
    collectChildren(children, sema.ast());
    return pushLiteralChildBindingType(
        sema,
        children.span(),
        childRef,
        [&](TypeRef targetTypeRef, TypeRef& outBindingTypeRef) {
            return SemaHelpers::resolveStructLikeChildBindingType(sema, children.span(), childRef, targetTypeRef, outBindingTypeRef);
        });
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
        SemaNodeView view = sema.viewTypeConstant(child);
        SWC_ASSERT(view.typeRef().isValid());
        values.push_back(view.cstRef());
        elemTypes.push_back(view.typeRef());
        allConstant = allConstant && view.cstRef().isValid();
    }

    const TypeRef aggregateTypeRef = sema.typeMgr().addType(TypeInfo::makeAggregateArray(elemTypes));

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateArray(sema.ctx(), values);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        sema.setType(sema.curNodeRef(), aggregateTypeRef);
    }

    sema.setIsValue(*this);
    const SemaNodeView literalView = sema.curViewNodeTypeConstant();
    SWC_RESULT(attachLiteralRuntimeStorageIfNeeded(sema, *this, literalView));
    return Result::Continue;
}

Result AstArrayLiteral::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SmallVector<AstNodeRef> children;
    collectChildren(children, sema.ast());
    return pushLiteralChildBindingType(
        sema,
        children.span(),
        childRef,
        [&](TypeRef targetTypeRef, TypeRef& outBindingTypeRef) {
            return SemaHelpers::resolveArrayLikeChildBindingType(sema, children.span(), childRef, targetTypeRef, outBindingTypeRef);
        });
}

SWC_END_NAMESPACE();
