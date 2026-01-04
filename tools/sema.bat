@echo off
echo SYNTAX
call syntax.bat %1 %2 %3 %4 %5 %6 %7 %8 %9
echo SEMA
swc sema --verify -d ../bin/tests/sema %1 %2 %3 %4 %5 %6 %7 %8 %9
