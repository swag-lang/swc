/*
#global internal

struct Empty {}
const A0: Empty = {}

Repro command:
swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema -ff sema-wrong.swg

Observed failure:
assertion failed structSize (C:\Perso\swag-lang\swc\src\Compiler\Sema\Cast\Cast.Struct.cpp:262)
*/
