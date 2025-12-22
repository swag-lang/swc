#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseLiteral()
{
    switch (id())
    {
        case TokenId::NumberInteger:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntegerLiteral>(consume());
            return nodeRef;
        }

        case TokenId::NumberBin:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BinaryLiteral>(consume());
            return nodeRef;
        }

        case TokenId::NumberHex:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::HexaLiteral>(consume());
            return nodeRef;
        }

        case TokenId::NumberFloat:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FloatLiteral>(consume());
            return nodeRef;
        }

        case TokenId::StringLine:
        case TokenId::StringMultiLine:
        case TokenId::StringRaw:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StringLiteral>(consume());
            return nodeRef;
        }

        case TokenId::Character:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CharacterLiteral>(consume());
            return nodeRef;
        }

        case TokenId::KwdTrue:
        case TokenId::KwdFalse:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BoolLiteral>(consume());
            return nodeRef;
        }

        case TokenId::KwdNull:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NullLiteral>(consume());
            return nodeRef;
        }

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
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerLiteral>(consume());
            return nodeRef;
        }

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseLiteralExpression()
{
    const auto literal = parseLiteral();
    if (literal.isInvalid())
        return AstNodeRef::invalid();

    const auto quoteTknRef = ref();
    if (isNot(TokenId::SymSingleQuote))
        return literal;

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SuffixLiteral>(consume());
    nodePtr->nodeLiteralRef       = literal;
    nodePtr->nodeSuffixRef.setInvalid();

    switch (id())
    {
        case TokenId::Identifier:
            nodePtr->nodeSuffixRef = parseQuotedIdentifier();
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
            nodePtr->nodeSuffixRef = parseType();
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
    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::ArrayLiteral>(ref());
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::UnnamedArgumentList, TokenId::SymLeftBracket);
    return nodeRef;
}

AstNodeRef Parser::parseLiteralStruct()
{
    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::StructLiteral>(ref());
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
