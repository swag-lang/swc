#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isCharacterLiteralTypeSuffix(const TokenId id)
    {
        return id == TokenId::TypeU8 ||
               id == TokenId::TypeU16 ||
               id == TokenId::TypeU32 ||
               id == TokenId::TypeU64 ||
               id == TokenId::TypeRune;
    }
}

// '#raw' only qualifies how the lexer read the literal that follows, so the node is the plain
// string literal and the modifier leaves no trace in the AST.
AstNodeRef Parser::parseRawStringLiteral()
{
    consume();

    if (isNot(TokenId::StringLine) && isNot(TokenId::StringMultiLine))
    {
        // Parse the operand anyway: the modifier is what is wrong, not the expression, so the
        // rest of the statement must not produce a second error.
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

    TokenRef suffixTknRef = TokenRef::invalid();
    TokenRef quoteTknRef  = TokenRef::invalid();

    // Blanks and comments between the literal and its quote are transparent, but a line
    // break is not: a statement ends at the end of a line, so the suffix stays on it.
    if (is(TokenId::SymSingleQuote) && !tok().flags.has(TokenFlagsE::EolBefore))
    {
        quoteTknRef  = ref();
        suffixTknRef = consume();
    }
    else if (ast_->node(literal).is(AstNodeId::CharacterLiteral) && isCharacterLiteralTypeSuffix(id()))
    {
        // The closing delimiter doubles as the suffix separator, but trivia must break adjacency.
        const auto literalRange = ast_->srcView().tokenCodeRange(*ctx_, ast_->node(literal).tokRef());
        const auto suffixRange  = ast_->srcView().tokenCodeRange(*ctx_, ref());
        if (literalRange.offset + literalRange.len == suffixRange.offset)
            suffixTknRef = ref();
    }

    if (suffixTknRef.isInvalid())
        return literal;

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SuffixLiteral>(suffixTknRef);
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
        case TokenId::TypeString:
        case TokenId::TypeTypeInfo:
        case TokenId::TypeVoid:
            raiseError(DiagnosticId::parser_err_invalid_literal_suffix, ref());
            consume();
            return nodeRef;

        default:
            SWC_ASSERT(quoteTknRef.isValid());
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

SWC_END_NAMESPACE();
