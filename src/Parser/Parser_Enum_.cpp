#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImplEnum()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplEnum>(ref());
    consumeAssert(TokenId::KwdImpl);
    consumeAssert(TokenId::KwdEnum);

    nodePtr->nodeName = parseQualifiedIdentifier();
    if (nodePtr->nodeName.isInvalid())
        skipTo({TokenId::SymLeftCurly});

    nodePtr->spanChildren = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    switch (id())
    {
        case TokenId::CompilerAssert:
            return parseCompilerDiagnostic();
        case TokenId::CompilerError:
            return parseCompilerDiagnostic();
        case TokenId::CompilerWarning:
            return parseCompilerDiagnostic();
        case TokenId::CompilerPrint:
            return parseCompilerDiagnostic();
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::EnumBody>();

        case TokenId::KwdUsing:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingEnumDecl>(ref());
            consume();
            nodePtr->nodeName = parseQualifiedIdentifier();
            return nodeRef;
        }

        case TokenId::Identifier:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumValue>(ref());
            consume();
            if (consumeIf(TokenId::SymEqual).isValid())
            {
                nodePtr->nodeValue = parseExpression();
                if (nodePtr->nodeValue.isInvalid())
                    skipTo(ENUM_VALUE_SYNC, SkipUntilFlagsE::EolBefore);
            }
            else
                nodePtr->nodeValue.setInvalid();
            return nodeRef;
        }

        case TokenId::CompilerAst:
            return parseCompilerFunc();

        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::EnumBody>();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseEnumDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumDecl>(ref());
    consumeAssert(TokenId::KwdEnum);

    // Name
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (nodePtr->tokName.isInvalid())
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon).isValid())
    {
        nodePtr->nodeType = parseType();
        if (nodePtr->nodeType.isInvalid())
            skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly});
    }
    else
        nodePtr->nodeType.setInvalid();

    // Content
    nodePtr->nodeBody = parseCompound<AstNodeId::EnumBody>(TokenId::SymLeftCurly);

    return nodeRef;
}

SWC_END_NAMESPACE()
