#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseLiteral()
{
    std::pair<AstNodeRef, AstNodeLiteral*> literal;
    switch (id())
    {
    case TokenId::NumberInteger:
    case TokenId::NumberBinary:
    case TokenId::NumberHexadecimal:
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::IntegerLiteral);
        break;

    case TokenId::NumberFloat:
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::FloatLiteral);
        break;

    case TokenId::StringLine:
    case TokenId::StringRaw:
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::StringLiteral);
        break;

    case TokenId::Character:
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::CharacterLiteral);
        break;

    case TokenId::KwdTrue:
    case TokenId::KwdFalse:
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::BoolLiteral);
        break;

    case TokenId::KwdNull:
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::NullLiteral);
        break;

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
        literal = ast_->makeNode<AstNodeLiteral>(AstNodeId::CompilerLiteral);
        break;

    default:
        (void) reportError(DiagnosticId::ParserExpectedTokenFam, tok());
        return INVALID_REF;
    }

    literal.second->tknValue = consume();
    return literal.first;
}

AstNodeRef Parser::parseLiteralExpression()
{
    const auto literal = parseLiteral();
    if (isInvalid(literal))
        return INVALID_REF;

    const auto quoteTknRef = ref();
    if (!consumeIf(TokenId::SymQuote))
        return literal;

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::QuotedLiteral>();
    nodePtr->nodeLiteral          = literal;

    switch (id())
    {
    case TokenId::Identifier:
        nodePtr->nodeQuote = parseIdentifier();
        return nodeRef;

    case TokenId::TypeF32:
    case TokenId::TypeF64:
    case TokenId::TypeS8:
    case TokenId::TypeS16:
    case TokenId::TypeS32:
    case TokenId::TypeS64:
    case TokenId::TypeU8:
    case TokenId::TypeU16:
    case TokenId::TypeU32:
    case TokenId::TypeU64:
    case TokenId::TypeRune:
    case TokenId::TypeBool:
        nodePtr->nodeQuote = parseType();
        return nodeRef;

    case TokenId::TypeAny:
    case TokenId::TypeCString:
    case TokenId::TypeCVarArgs:
    case TokenId::TypeString:
    case TokenId::TypeTypeInfo:
    case TokenId::TypeVoid:
        (void) reportError(DiagnosticId::ParserInvalidLiteralSuffix, tok());
        consume();
        return nodeRef;

    default:
        (void) reportError(DiagnosticId::ParserEmptyLiteralSuffix, quoteTknRef);
        return nodeRef;
    }
}

AstNodeRef Parser::parsePrimaryExpression()
{
    switch (id())
    {
    case TokenId::Identifier:
        return parseIdentifier();

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

    default:
        (void) reportError(DiagnosticId::ParserUnexpectedToken, tok());
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseFactorExpression()
{
    const auto nodeRef = parsePrimaryExpression();
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
            (void) reportError(DiagnosticId::ParserUnexpectedAndOr, tok());

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
    expectAndConsumeClosing(TokenId::SymLeftParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIdentifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>();
    nodePtr->tknName        = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
    return nodeRef;
}

AstNodeRef Parser::parseLiteralArray()
{
    return parseBlock(AstNodeId::ArrayLiteral, TokenId::SymLeftBracket);
}

SWC_END_NAMESPACE()
