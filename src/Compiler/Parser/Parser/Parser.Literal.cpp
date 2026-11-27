#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

// The lexer already applied #raw, so the modifier needs no AST node.
AstNodeRef Parser::parseRawStringLiteral()
{
    consume();

    if (isNot(TokenId::StringLine) && isNot(TokenId::StringMultiLine))
    {
        // Parse the operand after diagnosing the modifier to avoid a second error
        // for the remaining statement.
        raiseError(DiagnosticId::parser_err_raw_needs_string, ref());
        return parsePrimaryExpression();
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StringLiteral>(consume());
    return nodeRef;
}

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
        case TokenId::CompilerCommand:
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerOs:
        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerSwagOs:
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
    const AstNodeRef literal = parseLiteral();
    if (literal.isInvalid())
        return AstNodeRef::invalid();

    const TokenRef suffixMarkerRef = consumeIf(TokenId::SymLiteralSuffixStart);
    if (suffixMarkerRef.isInvalid())
        return literal;

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SuffixLiteral>(suffixMarkerRef);

    nodePtr->nodeLiteralRef = literal;
    nodePtr->nodeSuffixRef.setInvalid();

    switch (id())
    {
        case TokenId::Identifier:
            nodePtr->nodeSuffixRef = parseIdentifier();
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
        case TokenId::TypeString:
        case TokenId::TypeTypeInfo:
        case TokenId::TypeVoid:
            raiseError(DiagnosticId::parser_err_invalid_literal_suffix, ref());
            consume();
            return nodeRef;

        default:
            raiseError(DiagnosticId::parser_err_empty_literal_suffix, suffixMarkerRef);
            return nodeRef;
    }
}

AstNodeRef Parser::parseLiteralArray()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ArrayLiteral>(ref());

    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::UnnamedArgumentList, TokenId::SymLeftBracket);

    return nodeRef;
}

AstNodeRef Parser::parseLiteralStruct()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructLiteral>(ref());

    const SpanRef           fields = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftCurly);
    SmallVector<AstNodeRef> children;
    ast_->appendNodes(children, fields);
    for (AstNodeRef& child : children)
    {
        const AstNode& field = ast_->node(child);
        if (field.isNot(AstNodeId::Identifier))
            continue;
        const auto [argumentRef, argument] = ast_->makeNode<AstNodeId::NamedArgument>(field.tokRef());
        argument->nodeArgRef               = child;
        child                              = argumentRef;
    }
    nodePtr->spanChildrenRef = ast_->pushSpan(children.span());

    return nodeRef;
}

SWC_END_NAMESPACE();
