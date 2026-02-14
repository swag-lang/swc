#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

CodeGen::CodeGen(Sema& sema) :
    sema_(&sema)
{
    setVisitors();
}

Result CodeGen::exec(SymbolFunction& symbolFunc, AstNodeRef root)
{
    visit_.start(ast(), root);
    currentFunction_ = &symbolFunc;
    builder_         = symbolFunc.microInstrBuilder();
    if (!builder_)
        return Result::Error;

    while (true)
    {
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
            return Result::Pause;
        if (result == AstVisitResult::Error)
            return Result::Error;
        if (result == AstVisitResult::Stop)
            return Result::Continue;
    }
}

TaskContext& CodeGen::ctx()
{
    return sema().ctx();
}

const TaskContext& CodeGen::ctx() const
{
    return sema().ctx();
}

Ast& CodeGen::ast()
{
    return sema().ast();
}

const Ast& CodeGen::ast() const
{
    return sema().ast();
}

void CodeGen::setVisitors()
{
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
    visit_.setPostChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return postNodeChild(node, childRef); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
}

Result CodeGen::preNode(AstNode& node)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPreNode(*this, node);
}

Result CodeGen::postNode(AstNode& node)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPostNode(*this, node);
}

Result CodeGen::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPreNodeChild(*this, node, childRef);
}

Result CodeGen::postNodeChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPostNodeChild(*this, node, childRef);
}

SWC_END_NAMESPACE();
