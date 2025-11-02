#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parsePrimaryExpression()
{
    switch (id())
    {
    case TokenId::Identifier:
        return parseIdentifierExpression();

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

AstNodeRef Parser::parseIdentifierExpression()
{
    if (!has_any(tok().flags, TokenFlags::BlankAfter))
    {
        switch (nextId())
        {
        case TokenId::SymLeftParen:
        {
            const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FuncCall>();
            nodePtr->nodeIdentifier       = parseIdentifier();
            nodePtr->nodeArgs             = parseBlock(AstNodeId::NamedArgumentBlock, TokenId::SymLeftParen);
            return nodeRef;
        }
        case TokenId::SymLeftCurly:
        {
            const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructInit>();
            nodePtr->nodeIdentifier       = parseIdentifier();
            nodePtr->nodeArgs             = parseBlock(AstNodeId::NamedArgumentBlock, TokenId::SymLeftCurly);
            return nodeRef;
        }
        case TokenId::SymLeftBracket:
        {
            const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ArrayDeref>();
            nodePtr->nodeIdentifier       = parseIdentifier();
            nodePtr->nodeArgs             = parseBlock(AstNodeId::UnnamedArgumentBlock, TokenId::SymLeftBracket);
            return nodeRef;
        }
        default:
            break;
        }
    }

    return parseIdentifier();
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
