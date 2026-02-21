#pragma once
#include "Compiler/Parser/Ast/Ast.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Sema;

class AstPrinter
{
public:
    static Utf8 format(const TaskContext& ctx, const Ast& ast, AstNodeRef root, Sema* sema = nullptr);
    static void print(const TaskContext& ctx, const Ast& ast, AstNodeRef root, Sema* sema = nullptr);
};

SWC_END_NAMESPACE();
