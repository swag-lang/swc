#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parsePrimaryExpression()
{
    switch (id())
    {
    case TokenId::Identifier:
        return parseIdentifier();

    case TokenId::CompilerSizeOf:
    case TokenId::CompilerAlignOf:
    case TokenId::CompilerOffsetOf:
    case TokenId::CompilerTypeOf:
    case TokenId::CompilerDeclType:
    case TokenId::CompilerStringOf:
    case TokenId::CompilerNameOf:
    case TokenId::CompilerRunes:
    case TokenId::CompilerIsConstExpr:
    case TokenId::CompilerDefined:
    case TokenId::CompilerInclude:
        return parseCallerArg1(AstNodeId::CompilerIntrinsic1);

    case TokenId::IntrinsicKindOf:
    case TokenId::IntrinsicCountOf:
    case TokenId::IntrinsicDataOf:
    case TokenId::IntrinsicCVaStart:
    case TokenId::IntrinsicCVaEnd:
    case TokenId::IntrinsicMakeCallback:
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
        return parseCallerArg1(AstNodeId::Intrinsic1);

    case TokenId::IntrinsicMakeAny:
    case TokenId::IntrinsicMakeSlice:
    case TokenId::IntrinsicMakeString:
    case TokenId::IntrinsicCVaArg:
    case TokenId::IntrinsicMin:
    case TokenId::IntrinsicMax:
    case TokenId::IntrinsicMulAdd:
    case TokenId::IntrinsicRol:
    case TokenId::IntrinsicRor:
    case TokenId::IntrinsicPow:
    case TokenId::IntrinsicATan2:
    case TokenId::IntrinsicAtomicCmpXchg:
    case TokenId::IntrinsicAtomicXchg:
    case TokenId::IntrinsicAtomicXor:
    case TokenId::IntrinsicAtomicOr:
    case TokenId::IntrinsicAtomicAnd:
    case TokenId::IntrinsicAtomicAdd:
        return parseCallerArg2(AstNodeId::Intrinsic2);

    case TokenId::IntrinsicMakeInterface:
        return parseCallerArg3(AstNodeId::Intrinsic3);

    case TokenId::NumberInteger:
    case TokenId::NumberBinary:
    case TokenId::NumberHexadecimal:
    case TokenId::NumberFloat:
    case TokenId::Character:
        return parseLiteralExpression();

    case TokenId::StringLine:
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
        return parseLiteral();

    case TokenId::SymLeftParen:
        return parseParenExpression();

    case TokenId::SymLeftBracket:
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
    case TokenId::CompilerCode:
        return parseType();

    default:
        raiseError(DiagnosticId::ParserUnexpectedToken, ref());
        return INVALID_REF;
    }
}

AstNodeRef Parser::parsePostFixExpression()
{
    auto nodeRef = parsePrimaryExpression();
    if (isInvalid(nodeRef))
        return INVALID_REF;

    // Handle chained postfix operations: A.B.C()[5](args)
    while (true)
    {
        // Member access: A.B
        if (is(TokenId::SymDot))
        {
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::MemberAccess>();
            consume();
            nodePtr->nodeLeft  = nodeRef;
            nodePtr->nodeRight = parsePostFixExpression();
            nodeRef            = nodeParent;
            continue;
        }

        // Array indexing: A[index]
        if (is(TokenId::SymLeftBracket) && !has_any(tok().flags, TokenFlags::BlankBefore))
        {
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::ArrayDeref>();
            nodePtr->nodeExpr                = nodeRef;
            nodePtr->nodeArgs                = parseBlock(AstNodeId::UnnamedArgumentBlock, TokenId::SymLeftBracket);
            nodeRef                          = nodeParent;
            continue;
        }

        // Function call: A(args)
        if (is(TokenId::SymLeftParen) && !has_any(tok().flags, TokenFlags::BlankBefore))
        {
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::FuncCall>();
            nodePtr->nodeExpr                = nodeRef;
            nodePtr->nodeArgs                = parseBlock(AstNodeId::NamedArgumentBlock, TokenId::SymLeftParen);
            nodeRef                          = nodeParent;
            continue;
        }

        // Struct init: A{args}
        if (is(TokenId::SymLeftCurly) && !has_any(tok().flags, TokenFlags::BlankBefore))
        {
            const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::StructInit>();
            nodePtr->nodeExpr                = nodeRef;
            nodePtr->nodeArgs                = parseBlock(AstNodeId::NamedArgumentBlock, TokenId::SymLeftCurly);
            nodeRef                          = nodeParent;
            continue;
        }
        break;
    }

    // 'as'
    if (is(TokenId::KwdAs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::As>();
        consume();
        nodePtr->nodeExpr = nodeRef;
        nodePtr->nodeType = parseType();
        nodeRef           = nodeParent;
        return nodeRef;
    }

    // 'is'
    if (is(TokenId::KwdIs))
    {
        const auto [nodeParent, nodePtr] = ast_->makeNode<AstNodeId::Is>();
        consume();
        nodePtr->nodeExpr = nodeRef;
        nodePtr->nodeType = parseType();
        nodeRef           = nodeParent;
        return nodeRef;
    }

    return nodeRef;
}

AstModifierFlags Parser::parseModifiers()
{
    auto                                 result = AstModifierFlags::Zero;
    std::map<AstModifierFlags, TokenRef> done;

    while (true)
    {
        auto toSet = AstModifierFlags::Zero;
        switch (id())
        {
        case TokenId::ModifierBit:
            toSet = AstModifierFlags::Bit;
            break;
        case TokenId::ModifierUnConst:
            toSet = AstModifierFlags::UnConst;
            break;
        case TokenId::ModifierErr:
            toSet = AstModifierFlags::Err;
            break;
        case TokenId::ModifierNoErr:
            toSet = AstModifierFlags::NoErr;
            break;
        case TokenId::ModifierPromote:
            toSet = AstModifierFlags::Promote;
            break;
        case TokenId::ModifierWrap:
            toSet = AstModifierFlags::Wrap;
            break;
        case TokenId::ModifierNoDrop:
            toSet = AstModifierFlags::NoDrop;
            break;
        case TokenId::ModifierRef:
            toSet = AstModifierFlags::Ref;
            break;
        case TokenId::ModifierConstRef:
            toSet = AstModifierFlags::ConstRef;
            break;
        case TokenId::ModifierReverse:
            toSet = AstModifierFlags::Reverse;
            break;
        case TokenId::ModifierMove:
            toSet = AstModifierFlags::Move;
            break;
        case TokenId::ModifierMoveRaw:
            toSet = AstModifierFlags::MoveRaw;
            break;
        case TokenId::ModifierNullable:
            toSet = AstModifierFlags::Nullable;
            break;
        case TokenId::Identifier:
        {
            const auto name = tok().toString(*file_);
            if (name[0] == '#')
            {
                raiseError(DiagnosticId::ParserInvalidModifier, ref());
                consume();
                continue;
            }
            break;
        }
        default:
            break;
        }

        if (toSet == AstModifierFlags::Zero)
            break;

        if (has_any(result, toSet))
        {
            auto diag = reportError(DiagnosticId::ParserDuplicatedModifier, ref());
            diag.addElement(DiagnosticId::ParserOtherDefinition);
            diag.last().setLocation(file_->lexOut().token(done[toSet]).toLocation(*ctx_, *file_));
            diag.report(*ctx_);
        }

        done[toSet] = ref();
        result |= toSet;
        consume();
    }

    return result;
}

AstNodeRef Parser::parseCast()
{
    const auto tknOp         = consume();
    const auto openRef       = ref();
    const auto modifierFlags = parseModifiers();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::ParserExpectedTokenAfter);
    if (consumeIf(TokenId::SymRightParen))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CastAuto>();
        nodePtr->tknOp                = tknOp;
        nodePtr->modifierFlags        = modifierFlags;
        nodePtr->nodeExpr             = parseExpression();
        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Cast>();
    nodePtr->tknOp                = tknOp;
    nodePtr->modifierFlags        = modifierFlags;
    nodePtr->nodeType             = parseType();
    if (isInvalid(nodePtr->nodeType))
        skipTo({TokenId::SymRightParen});
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    nodePtr->nodeExpr = parseExpression();

    return nodeRef;
}

AstNodeRef Parser::parseUnaryExpression()
{
    switch (id())
    {
    case TokenId::KwdCast:
        return parseCast();

    case TokenId::SymPlus:
    case TokenId::SymMinus:
    case TokenId::SymExclamation:
    case TokenId::SymTilde:
    case TokenId::SymAmpersand:
    case TokenId::KwdDRef:
    {
        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::UnaryExpression>();
        nodePtr->tknOp                  = consume();
        nodePtr->nodeExpr               = parsePrimaryExpression();
        return nodeParen;
    }

    default:
        break;
    }

    return parsePostFixExpression();
}

AstNodeRef Parser::parseFactorExpression()
{
    const auto nodeRef = parseUnaryExpression();
    if (isInvalid(nodeRef))
        return INVALID_REF;

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
        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::FactorExpression>();
        nodePtr->tknOp                  = consume();
        nodePtr->nodeLeft               = nodeRef;
        nodePtr->modifiersFlags         = parseModifiers();
        nodePtr->nodeRight              = parseFactorExpression();
        return nodeParen;
    }

    return nodeRef;
}

AstNodeRef Parser::parseCompareExpression()
{
    const auto nodeRef = parseFactorExpression();
    if (isInvalid(nodeRef))
        return INVALID_REF;

    if (isAny(TokenId::SymEqualEqual,
              TokenId::SymExclamationEqual,
              TokenId::SymLowerEqual,
              TokenId::SymGreaterEqual,
              TokenId::SymLower,
              TokenId::SymGreater,
              TokenId::SymEqual,
              TokenId::SymLowerEqualGreater))
    {
        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::CompareExpression>();
        nodePtr->tknOp                  = consume();
        nodePtr->nodeLeft               = nodeRef;
        nodePtr->nodeRight              = parseCompareExpression();
        return nodeParen;
    }

    return nodeRef;
}

AstNodeRef Parser::parseBoolExpression()
{
    const auto nodeRef = parseCompareExpression();
    if (isInvalid(nodeRef))
        return INVALID_REF;

    if (isAny(TokenId::KwdAnd, TokenId::KwdOr, TokenId::SymAmpersandAmpersand, TokenId::SymVerticalVertical))
    {
        if (isAny(TokenId::SymAmpersandAmpersand, TokenId::SymVerticalVertical))
            raiseError(DiagnosticId::ParserUnexpectedAndOr, ref());

        const auto [nodeParen, nodePtr] = ast_->makeNode<AstNodeId::BoolExpression>();
        nodePtr->tknOp                  = consume();
        nodePtr->nodeLeft               = nodeRef;
        nodePtr->nodeRight              = parseBoolExpression();
        return nodeParen;
    }

    return nodeRef;
}

AstNodeRef Parser::parseExpression()
{
    return parseBoolExpression();
}

AstNodeRef Parser::parseParenExpression()
{
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ParenExpression>();
    const auto openRef            = ref();
    consume(TokenId::SymLeftParen);
    nodePtr->nodeExpr = parseExpression();
    if (isInvalid(nodePtr->nodeExpr))
        skipTo({TokenId::SymRightParen}, SkipUntilFlags::EolBefore);
    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIdentifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>();
    nodePtr->tknName        = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
    return nodeRef;
}

AstNodeRef Parser::parseNamedArgument()
{
    // The name
    if (is(TokenId::Identifier) && nextIs(TokenId::SymColon) && !has_any(tok().flags, TokenFlags::BlankAfter))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedArgument>();
        nodePtr->tknName              = consume();
        consume(TokenId::SymColon);
        nodePtr->nodeArg = parseExpression();
        return nodeRef;
    }

    // The argument
    return parseExpression();
}

SWC_END_NAMESPACE()
