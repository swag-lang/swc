#global private
/**
# Language Keyword Index

Keywords are reserved bare words. They cannot be reused as identifiers. This
page is an index; the surrounding chapters explain each active construct.

# Declarations and Organization

```swag
alias  attr  const  enum  func  global  impl  interface  internal  late
let  mtd  namespace  private  public  readonly  struct  tls  union  using  var  with
```

'readonly' applies to an aggregate field only.

'me' names the receiver inside methods.

# Control Flow and Expressions

```swag
and  as  break  case  continue  default  defer  do  elif  else
fallthrough  for  if  in  is  me  or  orelse  return  switch
to  unreachable  until  where  while
```

# Values, Errors, and Conversion

```swag
cast  catch  discard  expect  fail  false  null
retval  true  try
```

'not' is reserved for future use.

# Contextual Source and Module Names

'export', 'location', 'link', and 'version' are recognized in specific module-setup
positions. Outside those positions the lexer treats them as ordinary identifiers; they are
not part of the reserved keyword set above.

# Built-In Types

```swag
any  bool  cstring  f32  f64  rune
s8  s16  s32  s64  string  typeinfo
u8  u16  u32  u64  void
```

# Compiler Directives

Directives introduce compiler-executed blocks, conditional compilation, module
configuration, source inclusion, diagnostics, and code injection.

```swag
#ast  #assert  #code  #error
#foreignlib  #global  #import  #include  #inject
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

Modifiers refine the type, operand, conversion, literal, or statement that
follows them. They annotate what carries no symbol; a declaration takes an
attribute instead.

```swag
#bit  #complete  #fail  #fwd  #move  #nodrop  #nofail
#prom  #raw  #relocate  #simd  #unconst  #wrap
```

# Runtime and Compiler Intrinsics

Intrinsic values:

```swag
Swag.args()  Swag.compiler()  Swag.gvtd()  Swag.jit()
Swag.modules()  Swag.processInfos()  Swag.runtimeFlags()
```

Type, value, lifecycle, and control intrinsics:

```swag
Swag.typeAs  Swag.assert  Swag.breakpoint  Swag.compilerError  Swag.compilerWarning
.count  .buffer  Swag.drop  Swag.getContext  Swag.init  Swag.typeIs
Swag.kindOf  Swag.makeAny  Swag.makeInterface  Swag.makeSlice  Swag.makeString  Swag.panic
Swag.postCopy  Swag.postMove  Swag.print  Swag.safetyPanic  Swag.setContext
Swag.stringCmp  Swag.tableOf  Swag.typeCmp
```

Math and bit intrinsics:

```swag
Swag.abs  Swag.acos  Swag.asin  Swag.atan  Swag.atan2  Swag.bitCountLz  Swag.bitCountNz
Swag.bitCountTz  Swag.byteSwap  Swag.ceil  Swag.cos  Swag.cosh  Swag.exp  Swag.exp2
Swag.floor  Swag.log  Swag.log10  Swag.log2  Swag.max  Swag.min  Swag.muladd  Swag.pow
Swag.rol  Swag.ror  Swag.round  Swag.sin  Swag.sinh  Swag.sqrt  Swag.tan  Swag.tanh  Swag.trunc
```

Memory, atomic, and C variadic intrinsics:

```swag
Swag.atomadd  Swag.atomand  Swag.atomcmpxchg  Swag.atomget  Swag.atomor  Swag.atomxchg  Swag.atomxor
Swag.memcmp  Swag.memcpy  Swag.memmove  Swag.memset
```

Packed vector intrinsics:

```swag
Swag.vecalign  Swag.vecall  Swag.vecany  Swag.vecavgr  Swag.vecgather  Swag.vecinterleavehi
Swag.vecinterleavelo  Swag.vecmadd  Swag.vecmaddubs  Swag.vecmask  Swag.vecmulhi  Swag.vecpackss
Swag.vecpackus  Swag.vecperm  Swag.vecreduceadd  Swag.vecreduceand  Swag.vecreducemax
Swag.vecreducemin  Swag.vecreduceor  Swag.vecreducexor  Swag.vecsad  Swag.vecsatadd  Swag.vecsatsub
Swag.vecselect  Swag.vecshuffle  Swag.vecshuffle2  Swag.vecsplat  Swag.vectruncs32  Swag.vecwidenhi
Swag.vecwidenlo
```

> NOTE:
> The '#'-prefixed and '@'-prefixed names are reserved separately from bare
> identifiers. The next section explains why Swag uses both namespaces.
*/
