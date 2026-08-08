#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The serialized shape of every persisted struct, pinned as text. TagBin matches fields
// by name and stores this exact list per type, so any line changing below is a
// compatibility event for existing '.scapture' files and saved quick styles: it must be
// deliberate, a removed field loses data, and a renamed one must leave a
// 'Serialization.Alias' behind.
func testSchemaOf(type: typeinfo)->String
{
    var result: retval
    let plan = catch Serialization.planFor(cast(const *Swag.TypeInfoStruct) type) as errplan
    @assert(errplan == null)

    for &pf in plan.fields
    {
        if !result.isEmpty() do
            result += ","
        result += pf.value.name
        result += ":"
        result += pf.value.pointedType!.name
    }

    return result
}

func testAssertSchema(type: typeinfo, expected: string)
{
    let actual = testSchemaOf(type)
    if actual != expected
    {
        Console.print("schema drift for ", type.name, "\n")
        Console.print("  expected: ", expected, "\n")
        Console.print("  actual:   ", actual, "\n")
    }

    @assert(actual == expected)
}

#test
{
    testAssertSchema(#typeof(Capture), "width:s32,height:s32,backImg:Image,widthOrg:s32,heightOrg:s32,backImgOriginal:Image,backImagePos:Point,preview:Image,file:String,forms:Array'IForm,nextStepIndex:u32,nextGroupId:u64,linkedImage:String,linkedUpToDate:bool,title:String")
    testAssertSchema(#typeof(BaseForm), "x:s32,y:s32,w:s32,h:s32,borderSize:f32,joinStyle:JoinStyle,bezier:bool,scale:f32,rotate:f32,alpha:u8,paintShadow:bool,shadowOffsetX:f32,shadowOffsetY:f32,borderColor:Color,backColor:Color,dashStyle:DashStyle,subKind:FormSubKind,groups:Array'u64")
    testAssertSchema(#typeof(QuickStyle), "forms:Array'IForm")
}

#test
{
    testAssertSchema(#typeof(FormArrow), "line:FormLine")
    testAssertSchema(#typeof(FormLine), "base:BaseForm,beginCap:LineCapStyle,endCap:LineCapStyle,dashCap:DashCapStyle,startSize:f32,endSize:f32,xa:f32,ya:f32,xb:f32,yb:f32,xc:f32,yc:f32,cacheCoords:Rectangle,cacheCoords2:Point,cacheBv:Rectangle")
    testAssertSchema(#typeof(FormShape), "base:BaseForm,kind:FormShapeKind,roundSize:f32")
    testAssertSchema(#typeof(FormStep), "base:BaseForm,kind:FormShapeKind,index:u32,typeIndex:FormStepType")
    testAssertSchema(#typeof(FormText), "base:BaseForm,fontName:String,text:String,fontStyle:FontFamilyStyle,alignHorz:FormTextAlign,alignVert:FormTextAlign,fontSize:f32,boldSize:f32,lineSpacing:f32")
    testAssertSchema(#typeof(FormImage), "base:BaseForm,image:Image,kind:FormImageKind,strength:s32,place:FormImagePlacement,freePos:Rectangle")
    testAssertSchema(#typeof(FormPolygon), "base:BaseForm,points:Array'Vector2")
    testAssertSchema(#typeof(FormDraw), "base:BaseForm,points:Array'Vector2,anchorSize:f32")
    testAssertSchema(#typeof(FormCallout), "base:BaseForm,fontName:String,text:String,fontStyle:FontFamilyStyle,alignHorz:FormTextAlign,alignVert:FormTextAlign,fontSize:f32,roundSize:f32,tailX:f32,tailY:f32,boldSize:f32,lineSpacing:f32,textColor:Color")
}
