#include "pch.h"
#include "Lexer/SourceView.h"
#include "Main/TaskContext.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/ConstantManager.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef)
{
    ast.nodes(out, spanRef);
}

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes)
{
    for (auto n : nodes)
        out.push_back(n);
}

void AstNode::setSemaConstant(ConstantRef ref)
{
    SWC_ASSERT(ref.isValid());
    semaFlags_.clearMask(SemaFlagE::RefMask);
    addSemaFlag(SemaFlagE::IsConst);
    sema_.constant = ref;
}

void AstNode::setSemaType(TypeInfoRef ref)
{
    SWC_ASSERT(ref.isValid());
    semaFlags_.clearMask(SemaFlagE::RefMask);
    addSemaFlag(SemaFlagE::IsType);
    sema_.type = ref;
}

const ConstantValue& AstNode::getSemaConstant(const TaskContext& ctx) const
{
    SWC_ASSERT(isSemaConstant());
    return ctx.compiler().constMgr().get(sema_.constant);
}

ConstantRef AstNode::getSemaConstantRef(const TaskContext& ctx) const
{
    SWC_ASSERT(isSemaConstant());
    return sema_.constant;
}

const TypeInfo& AstNode::getSemaType(const TaskContext& ctx) const
{
    SWC_ASSERT(isSemaType());
    return ctx.compiler().typeMgr().get(sema_.type);
}

TypeInfoRef AstNode::getSemaTypeRef(const TaskContext& ctx) const
{
    SWC_ASSERT(isSemaType());
    return sema_.type;
}

TypeInfoRef AstNode::getNodeTypeRef(const TaskContext& ctx) const
{
    if (isSemaConstant())
        return getSemaConstant(ctx).typeRef();
    if (isSemaType())
        return getSemaTypeRef(ctx);
    return TypeInfoRef::invalid();
}

TokenRef AstNode::tokRefEnd(const Ast& ast) const
{
    const auto& info = Ast::nodeIdInfos(id_);

    SmallVector<AstNodeRef> children;
    info.collectChildren(children, ast, *this);

    if (children.empty())
        return tokRef_;

    const AstNode& nodePtr = ast.node(children.back());
    return nodePtr.tokRefEnd(ast);
}

SourceCodeLocation AstNode::location(const TaskContext& ctx, const Ast& ast) const
{
    SourceCodeLocation loc{};

    // Always use the SourceView of the node itself
    const auto baseViewRef = srcViewRef_;
    auto&      view        = ctx.compiler().srcView(baseViewRef);
    if (tokRef_.isInvalid() || view.tokens().empty())
        return loc;

    // Baseline comes from this node token
    const auto& baseTok  = view.token(tokRef_);
    const auto  baseLoc  = baseTok.location(ctx, view);
    const auto  baseLine = baseLoc.line;

    // Descend left-most while staying on the same line and same SourceView
    auto               leftMost = this;
    SourceCodeLocation startLoc = baseLoc;
    while (true)
    {
        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(leftMost->id()).collectChildren(children, ast, *leftMost);
        if (children.empty() || children.front().isInvalid())
            break;
        const AstNode& childPtr = ast.node(children.front());
        if (childPtr.srcViewRef() != baseViewRef)
            break;
        const auto& childTok = view.token(childPtr.tokRef());
        const auto  childLoc = childTok.location(ctx, view);
        if (childLoc.line != baseLine)
            break;
        leftMost = &childPtr;
        if (childLoc.offset < startLoc.offset)
            startLoc = childLoc;
    }

    // Descend right-most while staying on the same line and same SourceView
    auto               rightMost = this;
    SourceCodeLocation endLoc    = baseTok.location(ctx, view);
    while (true)
    {
        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(rightMost->id()).collectChildren(children, ast, *rightMost);
        if (children.empty() || children.back().isInvalid())
            break;
        const AstNode& childPtr = ast.node(children.back());
        if (childPtr.srcViewRef() != baseViewRef)
            break;
        const auto& childTok = view.token(childPtr.tokRef());
        const auto  childLoc = childTok.location(ctx, view);
        if (childLoc.line != baseLine)
            break;
        rightMost = &childPtr;
        if (childLoc.offset > endLoc.offset)
            endLoc = childLoc;
    }

    // Compute span and fill location
    const uint32_t startOff = startLoc.offset;
    const uint32_t endByte  = endLoc.offset + endLoc.len;
    const uint32_t spanLen  = endByte > startOff ? (endByte - startOff) : 1u;
    loc.fromOffset(ctx, view, startOff, spanLen);
    return loc;
}

SWC_END_NAMESPACE()
