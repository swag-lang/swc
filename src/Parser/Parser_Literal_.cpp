#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseLiteral()
{
    std::pair<AstNodeRef, AstLiteralBase*> literal;
    switch (id())
    {
    case TokenId::NumberInteger:
    case TokenId::NumberBinary:
    case TokenId::NumberHexadecimal:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::IntegerLiteral);
        break;

    case TokenId::NumberFloat:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::FloatLiteral);
        break;

    case TokenId::StringLine:
    case TokenId::StringMultiLine:
    case TokenId::StringRaw:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::StringLiteral);
        break;

    case TokenId::Character:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::CharacterLiteral);
        break;

    case TokenId::KwdTrue:
    case TokenId::KwdFalse:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::BoolLiteral);
        break;

    case TokenId::KwdNull:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::NullLiteral);
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
    case TokenId::CompilerScopeName:
    case TokenId::CompilerCurLocation:
        literal = ast_->makeNode<AstLiteralBase>(AstNodeId::CompilerLiteral);
        break;

    default:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return AstNodeRef::invalid();
    }

    literal.second->tokValue = consume();
    return literal.first;
}

AstNodeRef Parser::parseLiteralExpression()
{
    const auto literal = parseLiteral();
    if (literal.isInvalid())
        return AstNodeRef::invalid();

    const auto quoteTknRef = ref();
    if (consumeIf(TokenId::SymQuote).isInvalid())
        return literal;

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::PostfixedLiteral>();
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
        raiseError(DiagnosticId::parser_err_invalid_literal_suffix, ref());
        consume();
        return nodeRef;

    default:
        raiseError(DiagnosticId::parser_err_empty_literal_suffix, quoteTknRef);
        return nodeRef;
    }
}

AstNodeRef Parser::parseLiteralArray()
{
    return parseCompound<AstNodeId::ArrayLiteral>(TokenId::SymLeftBracket);
}

AstNodeRef Parser::parseLiteralStruct()
{
    return parseCompound<AstNodeId::StructLiteral>(TokenId::SymLeftCurly);
}

SWC_END_NAMESPACE()
