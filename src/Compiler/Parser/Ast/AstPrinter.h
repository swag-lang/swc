#pragma once
#include "Compiler/Parser/Ast/Ast.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class AstPrinter
{
public:
    static Utf8 format(const TaskContext& ctx, const Ast& ast, AstNodeRef root);
    static void print(const TaskContext& ctx, const Ast& ast, AstNodeRef root);
};

SWC_END_NAMESPACE();
