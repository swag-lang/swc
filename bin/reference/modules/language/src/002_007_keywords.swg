#global private
/**
# Language Keyword Index

Keywords are reserved bare words. They cannot be reused as identifiers. This
page is an index; the surrounding chapters explain each active construct.

# Declarations and Organization

```swag
alias  attr  const  enum  func  impl  interface  internal
let  mtd  namespace  private  public  struct  union  using  var  with
```

'me' names the receiver inside methods.

# Control Flow and Expressions

```swag
and  as  break  case  continue  default  defer  do  elif  else
fallthrough  for  if  in  is  me  or  orelse  return  switch
to  unreachable  until  where  while
```

'foreach' is no longer part of the language; the compiler recognizes it only to
produce a migration diagnostic that points to 'for'.

'verify' is no longer part of the language either, and is now an ordinary identifier. It
used to be accepted on function declarations but was never executed. Express a compile-time
overload contract with a 'where' constraint, and a runtime precondition with ordinary code.

# Values, Errors, and Conversion

```swag
cast  catch  discard  dref  expect  fail  false  notnull
null  retval  true  try  undefined
```

'not' is reserved for future use.

# Contextual Source and Module Names

'export', 'generated', 'location', 'link', and 'version' are recognized in
specific module-setup or generated-source positions. Outside those positions
the lexer treats them as ordinary identifiers; they are not part of the
reserved keyword set above.

# Built-In Types

```swag
any  bool  cstring  cvarargs  f32  f64  rune
s8  s16  s32  s64  string  typeinfo
u8  u16  u32  u64  void
```

# Compiler Directives

Directives introduce compiler-executed blocks, conditional compilation, module
configuration, source inclusion, diagnostics, and code injection.

```swag
#ast  #assert  #code  #dependencies  #elif  #else  #error
#foreignlib  #global  #if  #import  #include  #inject
#load  #main  #message  #premain  #print  #run  #scope
#static  #test  #type  #warning  #init  #drop
```

# Compile-Time Introspection

```swag
#alignof  #defined  #decltype  #fullnameof  #gettag  #hastag
#isconstexpr  #kindof  #location  #nameof  #offsetof  #runes
#safety  #sanity  #sizeof  #stringof  #typeof
```

# Compiler Context Values

```swag
#arch  #callerlocation  #cfg  #command  #cpu  #curlocation
#file  #line  #module  #os  #scopename  #swcbuildnum
#swagos  #swcrevision  #swcversion
```

Collision-free compiler identifiers for mixins and macros:

```swag
#uniq0  #uniq1  #uniq2  #uniq3  #uniq4
#uniq5  #uniq6  #uniq7  #uniq8  #uniq9
```

# Modifiers

Modifiers refine the declaration, type, loop, argument, or operation that
follows them.

```swag
#bit  #fail  #fwd  #late  #move  #nodrop  #nofail  #null
#prom  #relocate  #reverse  #unconst  #wrap
```

# Runtime and Compiler Intrinsics

Intrinsic values:

```swag
@args  @compiler  @gvtd  @index  @jit
@modules  @pinfos  @rtflags
```

Type, value, lifecycle, and control intrinsics:

```swag
@as  @assert  @breakpoint  @compilererror  @compilerwarning
@countof  @dataof  @drop  @getcontext  @init  @is  @isset
@kindof  @mkany  @mkinterface  @mkslice  @mkstring  @panic
@postcopy  @postmove  @print  @safetypanic  @setcontext
@stringcmp  @tableof  @typecmp
```

Math and bit intrinsics:

```swag
@abs  @acos  @asin  @atan  @atan2  @bitcountlz  @bitcountnz
@bitcounttz  @byteswap  @ceil  @cos  @cosh  @exp  @exp2
@floor  @log  @log10  @log2  @max  @min  @muladd  @pow
@rol  @ror  @round  @sin  @sinh  @sqrt  @tan  @tanh  @trunc
```

Memory, atomic, and C variadic intrinsics:

```swag
@alloc  @atomadd  @atomand  @atomcmpxchg  @atomor  @atomxchg
@atomxor  @cvaarg  @cvaend  @cvastart  @free  @memcmp
@memcpy  @memmove  @memset  @realloc
```

> NOTE:
> The '#'-prefixed and '@'-prefixed names are reserved separately from bare
> identifiers. The next section explains why Swag uses both namespaces.
*/
