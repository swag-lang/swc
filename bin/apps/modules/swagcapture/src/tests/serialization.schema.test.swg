#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The serialized shape of every persisted struct, pinned as text. TagBin matches fields
// by canonical key and stores this exact list per type, so any line changing below is a
// format event for '.scc' files and saved quick styles: it must be deliberate,
// because removing or renaming a field changes the data the current format stores.
func testSchemaOf(type: typeinfo)->String fail
{
    var result: retval
    let plan = Serialization.planFor(cast(const *Swag.TypeInfoStruct) type)

    for &pf in plan.fields
    {
        if !result.isEmpty() do
            result += ","
        result += pf.key
        result += ":"
        result += pf.value.pointedType!.name
    }

    return result
}

func testAssertSchema(type: typeinfo, expected: string) fail
{
    let actual = testSchemaOf(type)
    if actual != expected
    {
        Console.print("schema drift for ", type.name, "\n")
        Console.print("  expected: ", expected, "\n")
        Console.print("  actual:   ", actual, "\n")
    }

    Swag.assert(actual == expected)
}

#test
{
    expect testAssertSchema(#typeof(CaptureLibraryMetadata), "width:s32,height:s32,linkedImage:String,linkedUpToDate:bool,sourceKind:CaptureSourceKind,capturedAt:DateTime,sourceApplication:String,sourceExecutable:String,sourceWindowTitle:String,sourceWindowClass:String,favorite:bool,rating:u8")
    expect testAssertSchema(#typeof(CaptureFileModel), "width:s32,height:s32,widthOrg:s32,heightOrg:s32,backImagePos:Point,forms:Array'(IForm),nextStepIndex:u32,nextGroupId:u64,linkedImage:String,linkedUpToDate:bool,title:String,sourceKind:CaptureSourceKind,capturedAt:DateTime,sourceApplication:String,sourceExecutable:String,sourceWindowTitle:String,sourceWindowClass:String,tags:Array'(String),favorite:bool,rating:u8")
    expect testAssertSchema(#typeof(Capture), "width:s32,height:s32,backImg:Image,widthOrg:s32,heightOrg:s32,backImgOriginal:Image,backImagePos:Point,preview:Image,file:String,forms:Array'(IForm),nextStepIndex:u32,nextGroupId:u64,linkedImage:String,linkedUpToDate:bool,title:String,sourceKind:CaptureSourceKind,capturedAt:DateTime,sourceApplication:String,sourceExecutable:String,sourceWindowTitle:String,sourceWindowClass:String,tags:Array'(String),favorite:bool,rating:u8")
    expect testAssertSchema(#typeof(BaseForm), "x:s32,y:s32,w:s32,h:s32,borderSize:f32,joinStyle:JoinStyle,bezier:bool,scale:f32,rotate:f32,alpha:u8,paintShadow:bool,shadowOffsetX:f32,shadowOffsetY:f32,borderColor:Color,backColor:Color,dashStyle:DashStyle,subKind:FormSubKind,groups:Array'(u64)")
    expect testAssertSchema(#typeof(QuickStyle), "forms:Array'(IForm)")
}

#test
{
    expect testAssertSchema(#typeof(FormArrow), "line:FormLine")
    expect testAssertSchema(#typeof(FormLine), "base:BaseForm,beginCap:LineCapStyle,endCap:LineCapStyle,dashCap:DashCapStyle,startSize:f32,endSize:f32,xa:f32,ya:f32,xb:f32,yb:f32,xc:f32,yc:f32,cacheCoords:Rectangle,cacheCoords2:Point,cacheBv:Rectangle")
    expect testAssertSchema(#typeof(FormShape), "base:BaseForm,kind:FormShapeKind,roundSize:f32")
    expect testAssertSchema(#typeof(FormStep), "base:BaseForm,kind:FormShapeKind,index:u32,typeIndex:FormStepType")
    expect testAssertSchema(#typeof(FormText), "base:BaseForm,text:String,fontName:String,fontStyle:FontFamilyStyle,alignHorz:FormTextAlign,alignVert:FormTextAlign,fontSize:f32,boldSize:f32,lineSpacing:f32")
    expect testAssertSchema(#typeof(FormImage), "base:BaseForm,image:Image,kind:FormImageKind,strength:s32,place:FormImagePlacement,freePos:Rectangle")
    expect testAssertSchema(#typeof(FormPolygon), "base:BaseForm,points:Array'(Vector2)")
    expect testAssertSchema(#typeof(FormDraw), "base:BaseForm,points:Array'(Vector2),anchorSize:f32")
    expect testAssertSchema(#typeof(FormCallout), "base:BaseForm,text:String,fontName:String,fontStyle:FontFamilyStyle,alignHorz:FormTextAlign,alignVert:FormTextAlign,fontSize:f32,roundSize:f32,tailX:f32,tailY:f32,boldSize:f32,lineSpacing:f32,textColor:Color")
}
