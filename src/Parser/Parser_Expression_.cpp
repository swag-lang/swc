#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

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
            const auto loc  = ast_->lexOut().token(done[toSet]).location(*ctx_, ast_->lexOut());
            diag.last().addSpan(loc, DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
            diag.report(*ctx_);
        }

        done[toSet] = ref();
        result.add(toSet);
        consume();
    }

    return result;
}

AstNodeRef Parser::parseBinaryExpr()
{
    const auto nodeRef = parsePrefixExpr();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    if (isAny(TokenId::SymPlus,
              TokenId::SymMinus,
              TokenId::SymAsterisk,
              TokenId::SymSlash,
              TokenId::SymPercent,
              TokenId::SymAmpersand,
              TokenId::SymVertical,
              TokenId::SymGreaterGreater,
              TokenId::SymLowerLower,
              TokenId::SymPlusPlus,
              TokenId::SymCircumflex))
    {
        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::BinaryExpr>();
        nodePtr->tokOp                  = consume();
        nodePtr->nodeLeft               = nodeRef;
        nodePtr->modifierFlags          = parseModifiers();
        nodePtr->nodeRight              = parseBinaryExpr();
        return nodeParen;
    }

    return nodeRef;
}

AstNodeRef Parser::parseCast()
{
    const auto tknOp         = consume();
    const auto openRef       = ref();
    const auto modifierFlags = parseModifiers();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    if (consumeIf(TokenId::SymRightParen).isValid())
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AutoCastExpr>();
        nodePtr->tokOp                = tknOp;
        nodePtr->modifierFlags        = modifierFlags;
        nodePtr->nodeExpr             = parseExpression();
        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ExplicitCastExpr>();
    nodePtr->tokOp                = tknOp;
    nodePtr->modifierFlags        = modifierFlags;
    nodePtr->nodeType             = parseType();
    if (nodePtr->nodeType.isInvalid())
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    nodePtr->nodeExpr = parseExpression();

    return nodeRef;
}

AstNodeRef Parser::parseExpression()
{
    const auto nodeExpr1 = parseLogicalExpr();

    if (consumeIf(TokenId::KwdOrElse).isValid())
    {
        const auto nodeExpr2          = parseExpression();
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BinaryConditionalOp>();
        nodePtr->nodeLeft             = nodeExpr1;
        nodePtr->nodeRight            = nodeExpr2;
        return nodeRef;
    }

    if (consumeIf(TokenId::SymQuestion).isValid())
    {
        const auto nodeExpr2 = parseExpression();
        expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
        const auto nodeExpr3 = parseExpression();

        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConditionalOp>();
        nodePtr->nodeCond             = nodeExpr1;
        nodePtr->nodeTrue             = nodeExpr2;
        nodePtr->nodeFalse            = nodeExpr3;
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
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RangeExpr>();
        if (is(TokenId::KwdTo))
            nodePtr->addFlag(AstRangeExpr::FlagsE::Inclusive);
        consume();
        nodePtr->nodeExprDown = nodeExpr1;
        nodePtr->nodeExprUp   = parseExpression();
        return nodeRef;
    }

    return nodeExpr1;
}

AstNodeRef Parser::parseSuffixIdentifierValue()
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
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>();
            nodePtr->tokName        = consume();
            return nodeRef;
        }

        default:
            break;
    }

    const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (tokName.isInvalid())
        return AstNodeRef::invalid();

    if (is(TokenId::SymQuote) && tok().hasNotFlag(TokenFlagsE::BlankBefore))
    {
        consume();
        if (is(TokenId::SymLeftParen))
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MultiSuffixIdentifier>();
            nodePtr->tokName        = tokName;
            nodePtr->spanChildren   = parseCompoundContent(AstNodeId::MultiSuffixIdentifier, TokenId::SymLeftParen);
            return nodeRef;
        }

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SuffixIdentifier>();
        nodePtr->tokName        = tokName;
        nodePtr->nodeSuffix     = parseSuffixIdentifierValue();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>();
    nodePtr->tokName        = tokName;
    return nodeRef;
}

AstNodeRef Parser::parseInitializerExpression()
{
    if (consumeIf(TokenId::KwdUndefined).isValid())
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Undefined>();
        return nodeRef;
    }

    const auto modifierFlags = parseModifiers();
    if (modifierFlags == AstModifierFlagsE::Zero)
        return parseExpression();

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::InitializerExpr>();
    nodePtr->modifierFlags        = modifierFlags;
    nodePtr->nodeExpr             = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicValue()
{
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicValue>();
    nodePtr->tokName              = consume();
    return nodeRef;
}

AstNodeRef Parser::parseLogicalExpr()
{
    const auto nodeRef = parseRelationalExpr();
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    if (isAny(TokenId::KwdAnd, TokenId::KwdOr, TokenId::SymAmpersandAmpersand, TokenId::SymVerticalVertical))
    {
        if (isAny(TokenId::SymAmpersandAmpersand, TokenId::SymVerticalVertical))
            raiseError(DiagnosticId::parser_err_unexpected_and_or, ref());

        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::LogicalExpr>();
        nodePtr->tokOp                  = consume();
        nodePtr->nodeLeft               = nodeRef;
        nodePtr->nodeRight              = parseLogicalExpr();
        return nodeParen;
    }

    return nodeRef;
}

AstNodeRef Parser::parseNamedArg()
{
    // The name
    if (is(TokenId::Identifier) && nextIs(TokenId::SymColon) && !tok().flags.has(TokenFlagsE::BlankAfter))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedArgument>();
        nodePtr->tokName              = consume();
        consumeAssert(TokenId::SymColon);
        nodePtr->nodeArg = parseExpression();
        return nodeRef;
    }

    // The argument
    return parseExpression();
}

AstNodeRef Parser::parseParenExpr()
{
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ParenExpr>();
    const auto openRef            = ref();
    consumeAssert(TokenId::SymLeftParen);
    nodePtr->nodeExpr = parseExpression();
    if (nodePtr->nodeExpr.isInvalid())
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
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::ScopeResolution>();
            consume();
            nodePtr->nodeLeft  = nodeRef;
            nodePtr->nodeRight = parsePostFixExpression();
            nodeRef            = nodeParent;
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
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::AsCastExpr>();
        consume();
        nodePtr->nodeExpr = nodeRef;
        nodePtr->nodeType = parseType();
        return nodeParent;
    }

    // 'is'
    if (is(TokenId::KwdIs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IsTypeExpr>();
        consume();
        nodePtr->nodeExpr = nodeRef;
        nodePtr->nodeType = parseType();
        return nodeParent;
    }

    return nodeRef;
}

AstNodeRef Parser::parsePreQualifiedIdentifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::PreQualifiedIdentifier>();
    consumeAssert(TokenId::SymDot);
    nodePtr->nodeIdent = parseQualifiedIdentifier();
    return nodeRef;
}

AstNodeRef Parser::parsePrimaryExpression()
{
    switch (id())
    {
        case TokenId::SymDot:
            return parsePreQualifiedIdentifier();

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
        case TokenId::CompilerCode:
            return parseCompilerExpr();

        case TokenId::IntrinsicErr:
        case TokenId::IntrinsicArgs:
        case TokenId::IntrinsicByteCode:
        case TokenId::IntrinsicIndex:
        case TokenId::IntrinsicRtFlags:
        case TokenId::IntrinsicProcessInfos:
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
        case TokenId::NumberBinary:
        case TokenId::NumberHexadecimal:
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
    while (!tok().startsLine() && consumeIf(TokenId::SymDot).isValid())
    {
        // Parse the right side (another identifier)
        const auto rightNode = parseIdentifier();
        if (rightNode.isInvalid())
            return AstNodeRef::invalid();

        // Create a ScopeResolution node with left and right
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ScopeResolution>();
        nodePtr->nodeLeft       = leftNode;
        nodePtr->nodeRight      = rightNode;

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
              TokenId::SymExclamationEqual,
              TokenId::SymLowerEqual,
              TokenId::SymGreaterEqual,
              TokenId::SymLower,
              TokenId::SymGreater,
              TokenId::SymLowerEqualGreater))
    {
        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::RelationalExpr>();
        nodePtr->tokOp                  = consume();
        nodePtr->nodeLeft               = nodeRef;
        nodePtr->nodeRight              = parseRelationalExpr();
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
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymExclamation:
        case TokenId::SymTilde:
        case TokenId::SymAmpersand:
        {
            const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpr>();
            nodePtr->tokOp                  = consume();
            nodePtr->nodeExpr               = parseExpression();
            return nodeParen;
        }

        default:
            return parsePostFixExpression();
    }
}

AstNodeRef Parser::parseInitializerList(AstNodeRef nodeWhat)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructInitializerList>();
    nodePtr->nodeWhat       = nodeWhat;
    nodePtr->spanArgs       = parseCompoundContent(AstNodeId::NamedArgList, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseTryCatchAssume()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TryCatchAssumeExpr>();
    nodePtr->tokName        = consume();
    nodePtr->nodeExpr       = parseExpression();
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
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::IndexExpr>();
            nodePtr->nodeExpr                = nodeRef;
            nodePtr->nodeArg                 = nodeExpr;
            return nodeParent;
        }

        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::MultiIndexExpr>();
        nodePtr->nodeExpr                = nodeRef;
        nodePtr->spanChildren            = ast_->store().push_span(nodeArgs.span());
        return nodeParent;
    }

    // Slicing
    const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::RangeExpr>();
    if (is(TokenId::KwdTo))
        nodePtr->addFlag(AstRangeExpr::FlagsE::Inclusive);
    consume();
    nodePtr->nodeExprDown = nodeExpr;
    if (!is(TokenId::SymRightBracket))
        nodePtr->nodeExprUp = parseExpression();
    else
        nodePtr->nodeExprUp.setInvalid();

    expectAndConsumeClosing(TokenId::SymRightBracket, openRef);
    return nodeParent;
}

SWC_END_NAMESPACE()
