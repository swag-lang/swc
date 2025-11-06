#include "pch.h"
#include "Core/Types.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseTopLevelStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnumDecl();
    case TokenId::KwdStruct:
        return parseStructDecl();

    case TokenId::KwdImpl:
        return parseImplDecl();

    case TokenId::CompilerFuncTest:
    case TokenId::CompilerFuncMain:
    case TokenId::CompilerFuncPreMain:
    case TokenId::CompilerFuncInit:
    case TokenId::CompilerFuncDrop:
    case TokenId::CompilerAst:
    case TokenId::CompilerRun:
        return parseCompilerFunc();

    case TokenId::KwdNamespace:
        return parseNamespace();
    case TokenId::CompilerDependencies:
        return parseCompilerDependencies();

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::TopLevelBlock);

        // case TokenId::KwdUsing:
        //     return parseUsingDecl();

    default:
    {
        // @skip
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
    }
}

AstNodeRef Parser::parseEmbeddedStmt()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
    case TokenId::SymRightCurly:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;

    case TokenId::SymSemiColon:
        consume();
        return INVALID_REF;

    case TokenId::KwdEnum:
        return parseEnumDecl();
    case TokenId::KwdStruct:
        return parseStructDecl();

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::EmbeddedBlock);

    default:
    {
        // @skip
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::EolBefore);
        return INVALID_REF;
    }
    }
}

AstNodeRef Parser::parseUsingDecl()
{
    consume();
    const auto nodeRef = parseBlock(AstNodeId::Using, TokenId::Invalid, true);
    expectEndStatement();
    return nodeRef;
}

SWC_END_NAMESPACE()
