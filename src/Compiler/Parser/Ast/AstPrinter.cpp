#include "pch.h"
#include "Compiler/Parser/Ast/AstPrinter.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AstPrintNodeEntry
    {
        Utf8 prefix;
        bool isLastChild = false;
    };

    constexpr uint32_t K_MAX_TOKEN_TEXT = 48;
    constexpr uint32_t K_MAX_SEMA_TEXT  = 64;

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

    Utf8 sanitizeSemaText(const Utf8& text)
    {
        Utf8 out = text;
        out.trim();
        if (out.length() > K_MAX_SEMA_TEXT)
        {
            out.resize(K_MAX_SEMA_TEXT);
            out += "...";
        }

        return out;
    }

    void appendSemaPayload(Utf8& out, const TaskContext& ctx, Sema& sema, AstNodeRef nodeRef)
    {
        const bool         isSubstitute = sema.hasSubstitute(nodeRef);
        const SemaNodeView view         = isSubstitute ? sema.viewStored(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol)
                                                       : sema.view(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);

        out += " ";
        appendColored(out, ctx, SyntaxColor::Code, "[");

        bool first = true;
        if (view.hasType())
        {
            appendColored(out, ctx, SyntaxColor::Attribute, "type = ");
            appendColored(out, ctx, SyntaxColor::Type, sanitizeSemaText(view.type()->toName(ctx)));
            first = false;
        }

        if (view.hasConstant())
        {
            if (!first)
                appendColored(out, ctx, SyntaxColor::Code, ", ");
            appendColored(out, ctx, SyntaxColor::Attribute, "const = ");
            appendColored(out, ctx, SyntaxColor::Constant, sanitizeSemaText(view.cst()->toString(ctx)));
            first = false;
        }

        if (view.hasSymbol())
        {
            if (!first)
                appendColored(out, ctx, SyntaxColor::Code, ", ");
            appendColored(out, ctx, SyntaxColor::Attribute, "sym = ");
            appendColored(out, ctx, SyntaxColor::Function, view.sym()->name(ctx));
            first = false;
        }

        const bool isValue = isSubstitute ? sema.isValueStored(nodeRef) : sema.isValue(nodeRef);
        if (isValue)
        {
            if (!first)
                appendColored(out, ctx, SyntaxColor::Code, ", ");
            appendColored(out, ctx, SyntaxColor::Attribute, "value");
            first = false;
        }

        const bool isLValue = isSubstitute ? sema.isLValueStored(nodeRef) : sema.isLValue(nodeRef);
        if (isLValue)
        {
            if (!first)
                appendColored(out, ctx, SyntaxColor::Code, ", ");
            appendColored(out, ctx, SyntaxColor::Attribute, "lvalue");
            first = false;
        }

        const bool isFolded = isSubstitute ? sema.isFoldedTypedConstStored(nodeRef) : sema.isFoldedTypedConst(nodeRef);
        if (isFolded)
        {
            if (!first)
                appendColored(out, ctx, SyntaxColor::Code, ", ");
            appendColored(out, ctx, SyntaxColor::Attribute, "folded");
        }

        appendColored(out, ctx, SyntaxColor::Code, "]");
    }

    void appendNodeLine(Utf8& out, const TaskContext& ctx, const Ast& ast, AstNodeRef nodeRef, const AstPrintNodeEntry& entry, Sema* sema)
    {
        const AstNode&      node     = ast.node(nodeRef);
        const AstNodeIdInfo nodeInfo = Ast::nodeIdInfos(node.id());

        out += entry.prefix;
        appendColored(out, ctx, SyntaxColor::Code, entry.isLastChild ? "+- " : "|- ");

        const SyntaxColor nodeColor = ast.isAdditionalNode(nodeRef) ? SyntaxColor::Intrinsic : SyntaxColor::Function;
        appendColored(out, ctx, nodeColor, nodeInfo.name);
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

        if (sema)
            appendSemaPayload(out, ctx, *sema, nodeRef);

        out += "\n";
    }

    AstVisitResult runVisit(AstVisit& visit, const TaskContext& ctx)
    {
        while (true)
        {
            const AstVisitResult result = visit.step(ctx);
            if (result == AstVisitResult::Continue)
                continue;
            return result;
        }
    }
}

Utf8 AstPrinter::format(const TaskContext& ctx, const Ast& ast, AstNodeRef root, Sema* sema)
{
    Utf8 out;
    if (root.isInvalid())
        return out;

    std::unordered_map<AstNodeRef, uint32_t>          totalChildrenByParent;
    std::unordered_map<AstNodeRef, uint32_t>          visitedChildrenByParent;
    std::unordered_map<AstNodeRef, AstPrintNodeEntry> nodeEntries;
    nodeEntries.reserve(256);

    auto resolveNodeRef = [sema](AstNodeRef nodeRef) -> AstNodeRef {
        if (!sema)
            return nodeRef;
        return sema->viewZero(nodeRef).nodeRef();
    };
    // Count children per node
    AstVisit orderingVisit;
    orderingVisit.setMode(AstVisitMode::ResolveBeforeCallbacks);
    orderingVisit.setNodeRefResolver(resolveNodeRef);

    orderingVisit.setPreChildVisitor([&](AstNode&, AstNodeRef&) -> Result {
        const AstNodeRef parentRef = orderingVisit.currentNodeRef();
        uint32_t&        numChild  = totalChildrenByParent[parentRef];
        numChild++;
        return Result::Continue;
    });

    auto& mutableAst = const_cast<Ast&>(ast);
    orderingVisit.start(mutableAst, root);
    if (runVisit(orderingVisit, ctx) == AstVisitResult::Error)
        return out;

    // Print
    AstVisit printVisit;
    printVisit.setMode(AstVisitMode::ResolveBeforeCallbacks);
    printVisit.setNodeRefResolver(resolveNodeRef);
    printVisit.setPreChildVisitor([&](AstNode&, AstNodeRef&) -> Result {
        const AstNodeRef parentRef = printVisit.currentNodeRef();
        uint32_t&        numChild  = visitedChildrenByParent[parentRef];
        numChild++;
        return Result::Continue;
    });

    printVisit.setPreNodeVisitor([&](AstNode&) -> Result {
        const AstNodeRef nodeRef   = printVisit.currentNodeRef();
        const AstNodeRef parentRef = printVisit.parentNodeRef();

        AstPrintNodeEntry entry;
        if (parentRef.isInvalid())
        {
            entry.prefix.clear();
            entry.isLastChild = true;
        }
        else
        {
            const auto parentIt = nodeEntries.find(parentRef);
            SWC_ASSERT(parentIt != nodeEntries.end());
            entry.prefix = parentIt->second.prefix;
            entry.prefix += parentIt->second.isLastChild ? "   " : "|  ";

            const uint32_t totalChildren = totalChildrenByParent[parentRef];
            const uint32_t childOrder    = visitedChildrenByParent[parentRef];
            entry.isLastChild            = childOrder == totalChildren;
        }

        appendNodeLine(out, ctx, ast, nodeRef, entry, sema);
        nodeEntries[nodeRef] = entry;

        return Result::Continue;
    });

    printVisit.start(mutableAst, root);
    if (runVisit(printVisit, ctx) == AstVisitResult::Error)
        return {};

    return out;
}

void AstPrinter::print(const TaskContext& ctx, const Ast& ast, AstNodeRef root, Sema* sema)
{
    Logger::print(ctx, format(ctx, ast, root, sema));
    Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
}

SWC_END_NAMESPACE();
