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
        raiseError(DiagnosticId::ParserExpectedTokenFam, tok());
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
        raiseError(DiagnosticId::ParserInvalidLiteralSuffix, tok());
        consume();
        return nodeRef;

    default:
        raiseError(DiagnosticId::ParserEmptyLiteralSuffix, quoteTknRef);
        return nodeRef;
    }
}

AstNodeRef Parser::parseLiteralArray()
{
    return parseBlock(AstNodeId::ArrayLiteral, TokenId::SymLeftBracket);
}

SWC_END_NAMESPACE()
