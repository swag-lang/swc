#global public
#global namespace QualifiedGenericCrossFile

#[Swag.ConstExpr]
func(T) useLater(value: T)->T => QualifiedGenericCrossFile.later(value)

#[Swag.ConstExpr]
func later(value: s32)->s32 => value + 1
