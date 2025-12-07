#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    // Precedence: bigger = binds tighter
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

    if (is(TokenId::SymSingleQuote) && !tok().hasFlag(TokenFlagsE::BlankBefore))
    {
        consume();
        if (is(TokenId::SymLeftParen))
        {
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IdentifierSuffixList>(tokName);
            nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::IdentifierSuffixList, TokenId::SymLeftParen);
            return nodeRef;
        }

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IdentifierSuffix>(tokName);
        nodePtr->nodeSuffixRef  = parseIdentifierSuffixValue();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>(tokName);
    return nodeRef;
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

AstNodeRef Parser::parseLogicalExpr()
{
    const auto nodeRef = parseRelationalExpr();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    if (isAny(TokenId::KwdAnd, TokenId::KwdOr, TokenId::SymAmpersandAmpersand, TokenId::SymPipePipe))
    {
        if (isAny(TokenId::SymAmpersandAmpersand, TokenId::SymPipePipe))
            raiseError(DiagnosticId::parser_err_unexpected_and_or, ref());

        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::LogicalExpr>(consume());
        nodePtr->nodeLeftRef            = nodeRef;
        nodePtr->nodeRightRef           = parseLogicalExpr();
        return nodeParen;
    }

    return nodeRef;
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
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::ScopeResolution>(consume());
            nodePtr->nodeLeftRef             = nodeRef;
            nodePtr->nodeRightRef            = parsePostFixExpression();
            nodeRef                          = nodeParent;
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
        case TokenId::CompilerBuildVersion:
        case TokenId::CompilerBuildRevision:
        case TokenId::CompilerBuildNum:
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
                return parseType();
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
            return parseType();

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
    // Parse the first identifier
    auto leftNode = parseIdentifier();
    if (leftNode.isInvalid())
        return AstNodeRef::invalid();

    // Check if there's a scope access operator
    while (!tok().startsLine() && is(TokenId::SymDot))
    {
        const auto tokDot = consume();

        // Parse the right side (another identifier)
        const auto rightNode = parseIdentifier();
        if (rightNode.isInvalid())
            return AstNodeRef::invalid();

        // Create a ScopeResolution node with left and right
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ScopeResolution>(tokDot);
        nodePtr->nodeLeftRef    = leftNode;
        nodePtr->nodeRightRef   = rightNode;

        // The new ScopeResolution becomes the left node for the next iteration
        leftNode = nodeRef;
    }

    return leftNode;
}

AstNodeRef Parser::parseRelationalExpr()
{
    const auto nodeRef = parseBinaryExpr();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    if (isAny(TokenId::SymEqualEqual,
              TokenId::SymBangEqual,
              TokenId::SymLessEqual,
              TokenId::SymGreaterEqual,
              TokenId::SymLess,
              TokenId::SymGreater,
              TokenId::SymLessEqualGreater))
    {
        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::RelationalExpr>(consume());
        nodePtr->nodeLeftRef            = nodeRef;
        nodePtr->nodeRightRef           = parseRelationalExpr();
        return nodeParen;
    }

    return nodeRef;
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
        nodePtr->spanChildrenRef         = ast_->store().push_span(nodeArgs.span());
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
