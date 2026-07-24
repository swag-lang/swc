#global private
/**
# Source Files

Regular Swag source files use the '.swg' extension and UTF-8 encoding. A module
compiles every '.swg' file below its 'src' directory as one program. Directory
names do not affect symbol names, declaration order, or visibility.

Because module files are compiled together:

- declarations may be used before their textual definition;
- a declaration in one file can refer to a declaration in another;
- 'private' declarations remain file-local;
- 'internal' and 'public' declarations share the module namespace.

Use files and folders to group concepts for readers, then use namespaces when
the qualified program name should also express that grouping.

# Script Files

The '.swgs' extension is reserved for standalone scripts. A script is compiled
as an individual input rather than discovered as part of a workspace module.
Use '.swg' for reusable application and library code.

> NOTE:
> The compiler, not the host filesystem order, determines compilation. Never
> rely on file names to initialize runtime state; use '#init' and explicit
> dependencies between values instead.
*/
