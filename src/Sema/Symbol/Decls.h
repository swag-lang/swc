#pragma once
#include "Sema/Symbol/DeclContext.h"

SWC_BEGIN_NAMESPACE()

class ModuleDecl : public DeclContext
{
public:
    ModuleDecl() :
        DeclContext(DeclContextKind::Module)
    {
    }
};

class NamespaceDecl : public DeclContext
{
public:
    NamespaceDecl() :
        DeclContext(DeclContextKind::Namespace)
    {
    }
};

SWC_END_NAMESPACE()
