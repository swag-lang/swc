#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    int getBinaryPrecedence(TokenId id)
    {
        switch (id)
        {
            // Multiplicative
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
            case TokenId::SymPercent:
                return 40;

                // Additive (including ++ if you treat it as concat/add)
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymPlusPlus:
                return 30;

                // Shifts
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                return 20;

                // Bitwise AND
            case TokenId::SymAmpersand:
                return 15;

                // Bitwise XOR
            case TokenId::SymCircumflex:
                return 12;

                // Bitwise OR
            case TokenId::SymPipe:
                return 10;

            default:
                return -1; // not a binary operator handled here
        }
    }

    bool isBinaryOperator(TokenId id)
    {
        switch (id)
        {
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
            case TokenId::SymPlusPlus:
            case TokenId::SymCircumflex:
                return true;
            default:
                return false;
        }
    }

    int getRelationalPrecedence(TokenId id)
    {
        switch (id)
        {
            // Equality
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
                return 5;

                // Relational / ordering
            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return 6;

            default:
                return -1;
        }
    }

    bool isRelationalOperator(TokenId id)
    {
        switch (id)
        {
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
            case TokenId::SymLessEqual:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLess:
            case TokenId::SymGreater:
            case TokenId::SymLessEqualGreater:
                return true;
            default:
                return false;
        }
    }

    bool isLogicalOperator(TokenId id)
    {
        switch (id)
        {
            case TokenId::KwdAnd:
            case TokenId::KwdOr:
            case TokenId::SymAmpersandAmpersand:
            case TokenId::SymPipePipe:
                return true;
            default:
                return false;
        }
    }

    int getLogicalPrecedence(TokenId id)
    {
        switch (id)
        {
            case TokenId::KwdOr:
                return 1;
            case TokenId::KwdAnd:
                return 2;
            default:
                return -1;
        }
    }
}

AstModifierFlags Parser::parseModifiers()
{
    AstModifierFlags                     result = AstModifierFlagsE::Zero;
    std::map<AstModifierFlags, TokenRef> done;

    while (true)
    {
        auto toSet = AstModifierFlagsE::Zero;
        switch (id())
        {
            case TokenId::ModifierBit:
                toSet = AstModifierFlagsE::Bit;
                break;
            case TokenId::ModifierUnConst:
                toSet = AstModifierFlagsE::UnConst;
                break;
            case TokenId::ModifierErr:
                toSet = AstModifierFlagsE::Err;
                break;
            case TokenId::ModifierNoErr:
                toSet = AstModifierFlagsE::NoErr;
                break;
            case TokenId::ModifierPromote:
                toSet = AstModifierFlagsE::Promote;
                break;
            case TokenId::ModifierWrap:
                toSet = AstModifierFlagsE::Wrap;
                break;
            case TokenId::ModifierNoDrop:
                toSet = AstModifierFlagsE::NoDrop;
                break;
            case TokenId::ModifierRef:
                toSet = AstModifierFlagsE::Ref;
                break;
            case TokenId::ModifierConstRef:
                toSet = AstModifierFlagsE::ConstRef;
                break;
            case TokenId::ModifierReverse:
                toSet = AstModifierFlagsE::Reverse;
                break;
            case TokenId::ModifierMove:
                toSet = AstModifierFlagsE::Move;
                break;
            case TokenId::ModifierMoveRaw:
                toSet = AstModifierFlagsE::MoveRaw;
                break;
            case TokenId::ModifierNullable:
                toSet = AstModifierFlagsE::Nullable;
                break;
            default:
                break;
        }

        if (toSet == AstModifierFlagsE::Zero)
            break;

        if (result.has(toSet))
        {
            auto       diag = reportError(DiagnosticId::parser_err_duplicated_modifier, ref());
            const auto loc  = ast_->srcView().token(done[toSet]).location(*ctx_, ast_->srcView());
            diag.last().addSpan(loc, DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
            diag.report(*ctx_);
        }

        done[toSet] = ref();
        result.add(toSet);
        consume();
    }

    return result;
}

AstNodeRef Parser::parseBinaryExpr(int minPrecedence)
{
    auto left = parsePrefixExpr();
    if (left.isInvalid())
        return AstNodeRef::invalid();

    while (true)
    {
        const auto opId = id();
        if (!isBinaryOperator(opId))
            break;

        const int precedence = getBinaryPrecedence(opId);
        if (precedence < minPrecedence)
            break;

        const auto tokOp = consume();

        // Modifier flags.
        const auto modifierFlags = parseModifiers();

        // All these operators are left-associative.
        // For right-associative ops, use 'precedence' instead of 'precedence + 1'
        const int nextMinPrecedence = precedence + 1;

        auto right = parseBinaryExpr(nextMinPrecedence);
        if (right.isInvalid())
            return AstNodeRef::invalid();

        // Build the BinaryExpr node
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BinaryExpr>(tokOp);
        nodePtr->nodeLeftRef          = left;
        nodePtr->modifierFlags        = modifierFlags;
        nodePtr->nodeRightRef         = right;

        // The new node becomes the left side for the next operator
        left = nodeRef;
    }

    return left;
}

AstNodeRef Parser::parseBinaryExpr()
{
    return parseBinaryExpr(0);
}

AstNodeRef Parser::parseCast()
{
    const auto tknOp         = consume();
    const auto openRef       = ref();
    const auto modifierFlags = parseModifiers();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    if (consumeIf(TokenId::SymRightParen).isValid())
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AutoCastExpr>(tknOp);
        nodePtr->modifierFlags        = modifierFlags;
        nodePtr->nodeExprRef          = parsePrefixExpr();
        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ExplicitCastExpr>(tknOp);
    nodePtr->modifierFlags        = modifierFlags;
    nodePtr->nodeTypeRef          = parseType();
    if (nodePtr->nodeTypeRef.isInvalid())
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    nodePtr->nodeExprRef = parsePrefixExpr();

    return nodeRef;
}

AstNodeRef Parser::parseExpression()
{
    const auto nodeExpr1 = parseLogicalExpr();

    if (is(TokenId::KwdOrElse))
    {
        const auto tokOp              = consume();
        const auto nodeExpr2          = parseExpression();
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BinaryConditionalExpr>(tokOp);
        nodePtr->nodeLeftRef          = nodeExpr1;
        nodePtr->nodeRightRef         = nodeExpr2;
        return nodeRef;
    }

    if (is(TokenId::SymQuestion))
    {
        const auto tokOp     = consume();
        const auto nodeExpr2 = parseExpression();
        expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
        const auto nodeExpr3 = parseExpression();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConditionalExpr>(tokOp);
        nodePtr->nodeCondRef          = nodeExpr1;
        nodePtr->nodeTrueRef          = nodeExpr2;
        nodePtr->nodeFalseRef         = nodeExpr3;
        return nodeRef;
    }

    return nodeExpr1;
}

AstNodeRef Parser::parseRangeExpression()
{
    AstNodeRef nodeExpr1 = AstNodeRef::invalid();
    if (!isAny(TokenId::KwdTo, TokenId::KwdUntil))
        nodeExpr1 = parseExpression();

    if (isAny(TokenId::KwdTo, TokenId::KwdUntil))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RangeExpr>(ref());
        if (is(TokenId::KwdTo))
            nodePtr->addParserFlag(AstRangeExpr::Inclusive);
        consume();
        nodePtr->nodeExprDownRef = nodeExpr1;
        nodePtr->nodeExprUpRef   = parseExpression();
        return nodeRef;
    }

    return nodeExpr1;
}

AstNodeRef Parser::parseIdentifierSuffixValue()
{
    if (isAny(TokenId::SymLeftCurly, TokenId::KwdFunc, TokenId::KwdMtd))
        return parseType();
    return parseExpression();
}

AstNodeRef Parser::parseIdentifier()
{
    switch (id())
    {
        case TokenId::KwdMe:
        case TokenId::CompilerAlias0:
        case TokenId::CompilerAlias1:
        case TokenId::CompilerAlias2:
        case TokenId::CompilerAlias3:
        case TokenId::CompilerAlias4:
        case TokenId::CompilerAlias5:
        case TokenId::CompilerAlias6:
        case TokenId::CompilerAlias7:
        case TokenId::CompilerAlias8:
        case TokenId::CompilerAlias9:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerUniq3:
        case TokenId::CompilerUniq4:
        case TokenId::CompilerUniq5:
        case TokenId::CompilerUniq6:
        case TokenId::CompilerUniq7:
        case TokenId::CompilerUniq8:
        case TokenId::CompilerUniq9:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>(consume());
            return nodeRef;
        }

        default:
            break;
    }

    const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (tokName.isInvalid())
        return AstNodeRef::invalid();
    auto [identRef, identPtr] = ast_->makeNode<AstNodeId::Identifier>(tokName);

    // Quote
    if (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::BlankBefore))
    {
        const auto tokQuote = consume();

        if (is(TokenId::SymLeftParen))
        {
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::PostfixQuoteSuffixListExpr>(tokQuote);
            nodePtr->nodeExprRef     = identRef;
            nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::PostfixQuoteSuffixListExpr, TokenId::SymLeftParen);
            return nodeRef;
        }

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::PostfixQuoteSuffixExpr>(tokQuote);
        nodePtr->nodeExprRef    = identRef;
        nodePtr->nodeSuffixRef  = parseIdentifierSuffixValue();
        return nodeRef;
    }

    return identRef;
}

AstNodeRef Parser::parseInitializerExpression()
{
    if (is(TokenId::KwdUndefined))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UndefinedExpr>(consume());
        return nodeRef;
    }

    const auto modifierFlags = parseModifiers();
    if (modifierFlags == AstModifierFlagsE::Zero)
        return parseExpression();

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::InitializerExpr>(ref());
    nodePtr->modifierFlags        = modifierFlags;
    nodePtr->nodeExprRef          = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicValue()
{
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicValue>(consume());
    return nodeRef;
}

AstNodeRef Parser::parseLogicalExpr(int minPrecedence)
{
    auto left = parseRelationalExpr();
    if (left.isInvalid())
        return AstNodeRef::invalid();

    while (true)
    {
        const auto opId = id();
        if (!isLogicalOperator(opId))
            break;

        if (isAny(TokenId::SymAmpersandAmpersand, TokenId::SymPipePipe))
            raiseError(DiagnosticId::parser_err_unexpected_and_or, ref());

        const int precedence = getLogicalPrecedence(opId);
        if (precedence < minPrecedence)
            break;

        const auto tokOp             = consume();
        const int  nextMinPrecedence = precedence + 1;

        auto right = parseLogicalExpr(nextMinPrecedence);
        if (right.isInvalid())
            return AstNodeRef::invalid();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LogicalExpr>(tokOp);
        nodePtr->nodeLeftRef          = left;
        nodePtr->nodeRightRef         = right;
        left                          = nodeRef;
    }

    return left;
}

AstNodeRef Parser::parseLogicalExpr()
{
    return parseLogicalExpr(0);
}

AstNodeRef Parser::parseNamedArg()
{
    // The name
    if (is(TokenId::Identifier) && nextIs(TokenId::SymColon) && !tok().flags.has(TokenFlagsE::BlankAfter))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedArgument>(consume());
        consumeAssert(TokenId::SymColon);
        nodePtr->nodeArgRef = parseExpression();
        return nodeRef;
    }

    // The argument
    return parseExpression();
}

AstNodeRef Parser::parseParenExpr()
{
    const auto openRef            = ref();
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ParenExpr>(consume());
    nodePtr->nodeExprRef          = parseExpression();
    if (nodePtr->nodeExprRef.isInvalid())
        skipTo({TokenId::SymRightParen}, SkipUntilFlagsE::EolBefore);
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parsePostFixExpression()
{
    auto nodeRef = parsePrimaryExpression();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    // Handle chained postfix operations: A.B.C()[5](args)
    while (true)
    {
        // Scope resolution
        if (is(TokenId::SymDot) && !tok().flags.has(TokenFlagsE::EolBefore))
        {
            const auto tokDot = consume();

            const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            if (tokName.isInvalid())
                return AstNodeRef::invalid();

            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::MemberAccessExpr>(tokDot);
            nodePtr->nodeLeftRef       = nodeRef;
            nodePtr->tokMemberRef      = tokName;

            nodeRef = nodeParent;
            continue;
        }

        // Array indexing or slicing
        if (is(TokenId::SymLeftBracket) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            nodeRef = parseArraySlicingIndex(nodeRef);
            continue;
        }

        // Function call
        if (is(TokenId::SymLeftParen) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            nodeRef = parseFunctionArguments(nodeRef);
            continue;
        }

        // Struct init: A{args}
        if (is(TokenId::SymLeftCurly) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            nodeRef = parseInitializerList(nodeRef);
            continue;
        }

        // Quote
        if (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            const auto tokQuote = consume();

            if (is(TokenId::SymLeftParen))
            {
                auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::PostfixQuoteSuffixListExpr>(tokQuote);
                nodePtr->nodeExprRef       = nodeRef;
                nodePtr->spanChildrenRef   = parseCompoundContent(AstNodeId::PostfixQuoteSuffixListExpr, TokenId::SymLeftParen);
                nodeRef                    = nodeParent;
                continue;
            }

            auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::PostfixQuoteSuffixExpr>(tokQuote);
            nodePtr->nodeExprRef       = nodeRef;
            nodePtr->nodeSuffixRef     = parseIdentifierSuffixValue();
            nodeRef                    = nodeParent;
            continue;
        }

        break;
    }

    // 'as'
    if (is(TokenId::KwdAs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::AsCastExpr>(consume());
        nodePtr->nodeExprRef             = nodeRef;
        nodePtr->nodeTypeRef             = parseType();
        return nodeParent;
    }

    // 'is'
    if (is(TokenId::KwdIs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IsTypeExpr>(consume());
        nodePtr->nodeExprRef             = nodeRef;
        nodePtr->nodeTypeRef             = parseType();
        return nodeParent;
    }

    return nodeRef;
}

AstNodeRef Parser::parseScopedIdentifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ScopedIdentifier>(consume());
    nodePtr->nodeIdentRef   = parseQualifiedIdentifier();
    return nodeRef;
}

AstNodeRef Parser::parsePrimaryExpression()
{
    switch (id())
    {
        case TokenId::SymDot:
            return parseScopedIdentifier();

        case TokenId::CompilerUp:
            return parseCompilerUp();

        case TokenId::CompilerTypeOf:
            return parseCompilerTypeOf();

        case TokenId::CompilerSizeOf:
        case TokenId::CompilerAlignOf:
        case TokenId::CompilerOffsetOf:
        case TokenId::CompilerDeclType:
        case TokenId::CompilerStringOf:
        case TokenId::CompilerNameOf:
        case TokenId::CompilerRunes:
        case TokenId::CompilerIsConstExpr:
        case TokenId::CompilerDefined:
        case TokenId::CompilerInclude:
        case TokenId::CompilerSafety:
        case TokenId::CompilerHasTag:
        case TokenId::CompilerInject:
        case TokenId::CompilerLocation:
            return parseCompilerCallUnary();

        case TokenId::CompilerRun:
            return parseCompilerRun();
        case TokenId::CompilerCode:
            return parseCompilerCode();

        case TokenId::IntrinsicErr:
        case TokenId::IntrinsicArgs:
        case TokenId::IntrinsicByteCode:
        case TokenId::IntrinsicProcessInfos:
        case TokenId::IntrinsicIndex:
        case TokenId::IntrinsicRtFlags:
        case TokenId::IntrinsicModules:
        case TokenId::IntrinsicGvtd:
        case TokenId::IntrinsicCompiler:
            return parseIntrinsicValue();

        case TokenId::KwdTry:
        case TokenId::KwdCatch:
        case TokenId::KwdTryCatch:
        case TokenId::KwdAssume:
            return parseTryCatchAssume();

        case TokenId::IntrinsicGetContext:
        case TokenId::IntrinsicDbgAlloc:
        case TokenId::IntrinsicSysAlloc:
            return parseIntrinsicCallZero();

        case TokenId::IntrinsicKindOf:
        case TokenId::IntrinsicCountOf:
        case TokenId::IntrinsicDataOf:
        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicMakeCallback:
        case TokenId::IntrinsicAlloc:
        case TokenId::IntrinsicFree:
        case TokenId::IntrinsicStrLen:
        case TokenId::IntrinsicAbs:
        case TokenId::IntrinsicSqrt:
        case TokenId::IntrinsicSin:
        case TokenId::IntrinsicCos:
        case TokenId::IntrinsicTan:
        case TokenId::IntrinsicSinh:
        case TokenId::IntrinsicCosh:
        case TokenId::IntrinsicTanh:
        case TokenId::IntrinsicASin:
        case TokenId::IntrinsicACos:
        case TokenId::IntrinsicATan:
        case TokenId::IntrinsicLog:
        case TokenId::IntrinsicLog2:
        case TokenId::IntrinsicLog10:
        case TokenId::IntrinsicFloor:
        case TokenId::IntrinsicCeil:
        case TokenId::IntrinsicTrunc:
        case TokenId::IntrinsicRound:
        case TokenId::IntrinsicExp:
        case TokenId::IntrinsicExp2:
        case TokenId::IntrinsicByteSwap:
        case TokenId::IntrinsicBitCountNz:
        case TokenId::IntrinsicBitCountTz:
        case TokenId::IntrinsicBitCountLz:
            return parseIntrinsicCallUnary();

        case TokenId::IntrinsicMakeAny:
        case TokenId::IntrinsicMakeSlice:
        case TokenId::IntrinsicMakeString:
        case TokenId::IntrinsicCVaArg:
        case TokenId::IntrinsicRealloc:
        case TokenId::IntrinsicStrCmp:
        case TokenId::IntrinsicStringCmp:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicTableOf:
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        case TokenId::IntrinsicRol:
        case TokenId::IntrinsicRor:
        case TokenId::IntrinsicPow:
        case TokenId::IntrinsicATan2:
        case TokenId::IntrinsicAtomicXchg:
        case TokenId::IntrinsicAtomicXor:
        case TokenId::IntrinsicAtomicOr:
        case TokenId::IntrinsicAtomicAnd:
        case TokenId::IntrinsicAtomicAdd:
            return parseIntrinsicCallBinary();

        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicMemCmp:
        case TokenId::IntrinsicAs:
        case TokenId::CompilerGetTag:
        case TokenId::IntrinsicAtomicCmpXchg:
        case TokenId::IntrinsicTypeCmp:
        case TokenId::IntrinsicMulAdd:
            return parseIntrinsicCallTernary();

        case TokenId::NumberInteger:
        case TokenId::NumberBin:
        case TokenId::NumberHex:
        case TokenId::NumberFloat:
        case TokenId::Character:
            return parseLiteralExpression();

        case TokenId::StringLine:
        case TokenId::StringMultiLine:
        case TokenId::StringRaw:
        case TokenId::KwdTrue:
        case TokenId::KwdFalse:
        case TokenId::KwdNull:
            return parseLiteral();

        case TokenId::CompilerFile:
        case TokenId::CompilerModule:
        case TokenId::CompilerLine:
        case TokenId::CompilerSwcVersion:
        case TokenId::CompilerSwcRevision:
        case TokenId::CompilerSwcBuildNum:
        case TokenId::CompilerBuildCfg:
        case TokenId::CompilerCallerFunction:
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerOs:
        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerSwagOs:
        case TokenId::CompilerBackend:
        case TokenId::CompilerScopeName:
        case TokenId::CompilerCurLocation:
            return parseLiteral();

        case TokenId::SymLeftParen:
            return parseParenExpr();

        case TokenId::SymLeftCurly:
            return parseLiteralStruct();

        case TokenId::SymLeftBracket:
            if (nextIs(TokenId::SymDotDot) || nextIs(TokenId::SymQuestion) || nextIs(TokenId::SymAsterisk))
                return parseTypeValue();
            return parseLiteralArray();

        case TokenId::TypeAny:
        case TokenId::TypeCString:
        case TokenId::TypeCVarArgs:
        case TokenId::TypeString:
        case TokenId::TypeTypeInfo:
        case TokenId::TypeVoid:
        case TokenId::TypeBool:
        case TokenId::TypeS8:
        case TokenId::TypeS16:
        case TokenId::TypeS32:
        case TokenId::TypeS64:
        case TokenId::TypeU8:
        case TokenId::TypeU16:
        case TokenId::TypeU32:
        case TokenId::TypeU64:
        case TokenId::TypeRune:
        case TokenId::TypeF32:
        case TokenId::TypeF64:
        case TokenId::KwdConst:
        case TokenId::KwdStruct:
        case TokenId::KwdUnion:
        case TokenId::SymAsterisk:
        case TokenId::SymAmpersand:
        case TokenId::ModifierNullable:
            return parseTypeValue();

        case TokenId::Identifier:
        case TokenId::KwdMe:
        case TokenId::CompilerAlias0:
        case TokenId::CompilerAlias1:
        case TokenId::CompilerAlias2:
        case TokenId::CompilerAlias3:
        case TokenId::CompilerAlias4:
        case TokenId::CompilerAlias5:
        case TokenId::CompilerAlias6:
        case TokenId::CompilerAlias7:
        case TokenId::CompilerAlias8:
        case TokenId::CompilerAlias9:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerUniq3:
        case TokenId::CompilerUniq4:
        case TokenId::CompilerUniq5:
        case TokenId::CompilerUniq6:
        case TokenId::CompilerUniq7:
        case TokenId::CompilerUniq8:
        case TokenId::CompilerUniq9:
            return parseIdentifier();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseLambdaExpression();

        case TokenId::CompilerType:
            return parseCompilerTypeExpr();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseQualifiedIdentifier()
{
    // Parse the first identifier (already supports A's32)
    auto leftNode = parseIdentifier();
    if (leftNode.isInvalid())
        return AstNodeRef::invalid();

    // Parse A.B.C... and allow postfix quote after each step: A.B's32.C's32
    while (!tok().startsLine() && is(TokenId::SymDot))
    {
        const auto tokDot = consume();

        const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
        if (tokName.isInvalid())
            return AstNodeRef::invalid();

        // Build member access: left.member
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MemberAccessExpr>(tokDot);
        nodePtr->nodeLeftRef    = leftNode;
        nodePtr->tokMemberRef   = tokName;

        leftNode = nodeRef;

        while (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::BlankBefore))
        {
            const auto tokQuote = consume();

            if (is(TokenId::SymLeftParen))
            {
                auto [qRef, qPtr]     = ast_->makeNode<AstNodeId::PostfixQuoteSuffixListExpr>(tokQuote);
                qPtr->nodeExprRef     = leftNode;
                qPtr->spanChildrenRef = parseCompoundContent(AstNodeId::PostfixQuoteSuffixListExpr, TokenId::SymLeftParen);
                leftNode              = qRef;
            }
            else
            {
                auto [qRef, qPtr]   = ast_->makeNode<AstNodeId::PostfixQuoteSuffixExpr>(tokQuote);
                qPtr->nodeExprRef   = leftNode;
                qPtr->nodeSuffixRef = parseIdentifierSuffixValue();
                leftNode            = qRef;
            }
        }
    }

    return leftNode;
}

AstNodeRef Parser::parseRelationalExpr(int minPrecedence)
{
    // Parse the left-hand side from the next lower level (binary expr)
    auto left = parseBinaryExpr();
    if (left.isInvalid())
        return AstNodeRef::invalid();

    while (true)
    {
        const auto opId = id();
        if (!isRelationalOperator(opId))
            break;

        const int precedence = getRelationalPrecedence(opId);
        if (precedence < minPrecedence)
            break;

        const auto tokOp = consume();

        const int nextMinPrecedence = precedence + 1;

        auto right = parseRelationalExpr(nextMinPrecedence);
        if (right.isInvalid())
            return AstNodeRef::invalid();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RelationalExpr>(tokOp);
        nodePtr->nodeLeftRef          = left;
        nodePtr->nodeRightRef         = right;

        left = nodeRef;
    }

    return left;
}

AstNodeRef Parser::parseRelationalExpr()
{
    return parseRelationalExpr(0);
}

AstNodeRef Parser::parsePrefixExpr()
{
    switch (id())
    {
        case TokenId::KwdCast:
            return parseCast();

        case TokenId::KwdDRef:
        case TokenId::KwdMoveRef:
        case TokenId::SymAmpersand:
        {
            const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>(consume());
            nodePtr->nodeExprRef            = parsePrefixExpr();
            return nodeParen;
        }

        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymBang:
        case TokenId::SymTilde:
        {
            const auto tokOp = consume();
            if (isAny(TokenId::SymPlus, TokenId::SymMinus, TokenId::SymBang, TokenId::SymTilde))
            {
                const auto diag = reportError(DiagnosticId::parser_err_unexpected_token, ref());
                diag.report(*ctx_);
                consume();
            }

            const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>(tokOp);
            nodePtr->nodeExprRef            = parsePrefixExpr();
            return nodeParen;
        }

        default:
            return parsePostFixExpression();
    }
}

AstNodeRef Parser::parseInitializerList(AstNodeRef nodeWhat)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructInitializerList>(ref());
    nodePtr->nodeWhatRef    = nodeWhat;
    nodePtr->spanArgsRef    = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseTryCatchAssume()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TryCatchExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseArraySlicingIndex(AstNodeRef nodeRef)
{
    const auto openRef = consumeAssert(TokenId::SymLeftBracket);
    if (is(TokenId::SymRightBracket))
    {
        raiseError(DiagnosticId::parser_err_empty_indexing, ref());
        return AstNodeRef::invalid();
    }

    AstNodeRef nodeExpr = AstNodeRef::invalid();
    if (!isAny(TokenId::KwdTo, TokenId::KwdUntil))
        nodeExpr = parseExpression();

    if (!isAny(TokenId::KwdTo, TokenId::KwdUntil))
    {
        SmallVector<AstNodeRef> nodeArgs;
        nodeArgs.push_back(nodeExpr);
        while (consumeIf(TokenId::SymComma).isValid())
        {
            nodeExpr = parseExpression();
            if (nodeExpr.isInvalid())
                return AstNodeRef::invalid();
            nodeArgs.push_back(nodeExpr);
        }

        expectAndConsumeClosing(TokenId::SymRightBracket, openRef);

        if (nodeArgs.size() == 1)
        {
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IndexExpr>(ref());
            nodePtr->nodeExprRef             = nodeRef;
            nodePtr->nodeArgRef              = nodeExpr;
            return nodeParent;
        }

        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IndexListExpr>(ref());
        nodePtr->nodeExprRef             = nodeRef;
        nodePtr->spanChildrenRef         = ast_->pushSpan(nodeArgs.span());
        return nodeParent;
    }

    // Slicing
    const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::RangeExpr>(ref());
    if (is(TokenId::KwdTo))
        nodePtr->addParserFlag(AstRangeExpr::Inclusive);
    consume();
    nodePtr->nodeExprDownRef = nodeExpr;
    if (!is(TokenId::SymRightBracket))
        nodePtr->nodeExprUpRef = parseExpression();
    else
        nodePtr->nodeExprUpRef.setInvalid();

    expectAndConsumeClosing(TokenId::SymRightBracket, openRef);
    return nodeParent;
}

AstNodeRef Parser::parseThrow()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ThrowExpr>(consume());
    nodePtr->nodeExprRef    = parseExpression();
    return nodeRef;
}

SWC_END_NAMESPACE()
