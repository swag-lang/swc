#include "pch.h"
#include "Compiler/Parser/Ast/AstPrinter.h"
#include "Compiler/Lexer/SourceView.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AstPrintStackEntry
    {
        AstNodeRef nodeRef;
        Utf8       prefix;
        bool       isLastChild = false;
    };

    constexpr uint32_t K_MAX_TOKEN_TEXT = 48;

    void appendColored(Utf8& out, const TaskContext& ctx, SyntaxColor color, std::string_view value)
    {
        out += SyntaxColorHelper::toAnsi(ctx, color);
        out += value;
        out += SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default);
    }

    Utf8 sanitizeTokenText(std::string_view tokenText)
    {
        Utf8 out;
        out.reserve(tokenText.size());

        for (const char c : tokenText)
        {
            if (c == '\r' || c == '\n' || c == '\t')
                out += ' ';
            else
                out += c;
        }

        out.trim();
        if (out.length() > K_MAX_TOKEN_TEXT)
        {
            out.resize(K_MAX_TOKEN_TEXT);
            out += "...";
        }

        return out;
    }

    void appendNodeLine(Utf8& out, const TaskContext& ctx, const Ast& ast, const AstPrintStackEntry& entry)
    {
        const AstNode&      node     = ast.node(entry.nodeRef);
        const AstNodeIdInfo nodeInfo = Ast::nodeIdInfos(node.id());

        out += entry.prefix;
        appendColored(out, ctx, SyntaxColor::Code, entry.isLastChild ? "+- " : "|- ");
        appendColored(out, ctx, SyntaxColor::Type, nodeInfo.name);
        if (node.tokRef().isValid())
        {
            out += " ";
            const SourceView& sourceView = ctx.compiler().srcView(node.srcViewRef());
            const auto        codeRange  = node.codeRange(ctx);
            appendColored(out, ctx, SyntaxColor::Number, std::format("@{}:{}", codeRange.line, codeRange.column));

            const Token& tok       = sourceView.token(node.tokRef());
            const Utf8   tokenText = sanitizeTokenText(tok.string(sourceView));
            if (!tokenText.empty())
            {
                out += " ";
                appendColored(out, ctx, SyntaxColor::String, std::format("\"{}\"", tokenText));
            }
        }

        out += "\n";
    }
}

Utf8 AstPrinter::format(const TaskContext& ctx, const Ast& ast, AstNodeRef root)
{
    Utf8 out;
    if (root.isInvalid())
        return out;

    SmallVector<AstPrintStackEntry> stack;
    stack.push_back({.nodeRef = root, .prefix = Utf8{}, .isLastChild = true});

    while (!stack.empty())
    {
        const AstPrintStackEntry entry = stack.back();
        stack.pop_back();

        appendNodeLine(out, ctx, ast, entry);

        SmallVector<AstNodeRef> children;
        ast.node(entry.nodeRef).collectChildrenFromAst(children, ast);
        for (size_t i = children.size(); i > 0; --i)
        {
            const AstNodeRef childRef = children[i - 1];
            if (childRef.isInvalid())
                continue;

            AstPrintStackEntry childEntry;
            childEntry.nodeRef      = childRef;
            childEntry.prefix       = entry.prefix;
            childEntry.prefix      += entry.isLastChild ? "   " : "|  ";
            childEntry.isLastChild  = (i == children.size());
            stack.push_back(childEntry);
        }
    }

    return out;
}

void AstPrinter::print(const TaskContext& ctx, const Ast& ast, AstNodeRef root)
{
    Logger::print(ctx, format(ctx, ast, root));
    Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
}

SWC_END_NAMESPACE();
