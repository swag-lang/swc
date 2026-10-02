#global private

struct(T) MetadataSignal
{
    callbacks: [..] T?
}

impl MetadataSignal
{
    mtd call(params: ...)
    {
        for callback in .callbacks
        {
            #ast
            {
                let signature = #typeof(T)
                return #stringof("callback(cast #assume(", signature.parameters[0].pointedType.fullname, ") params[0])")
            }
        }
    }
}

interface IMetadataReceiver
{
    mtd notify()
}

struct MetadataReceiver
{
    signal: MetadataSignal'func||(*MetadataReceiver)
    count:  s32
}

// Reflection reaches this completed method while emit is still instantiating the
// signal's #ast. Its runtime call graph must not become a compile-time dependency.
impl IMetadataReceiver for MetadataReceiver
{
    mtd impl notify()
    {
        .emit()
    }
}

impl MetadataReceiver
{
    mtd emit()
    {
        .signal.call(me)
        .count += 1
    }
}

// A method whose analysis has completed must be callable through metadata during #run.
#[Swag.ExportType(.Methods)]
struct MetadataReady
{
    value: s32
}

impl MetadataReady
{
    mtd read()->s32
    {
        return .value
    }
}

#[Swag.ExportType(.Methods)]
struct(T) MetadataLazyReady
{
    value: T
}

impl MetadataLazyReady
{
    mtd read()->T
    {
        return .value
    }
}

func metadataLazyMethodWorks()
{
    // This idle generic body is reached only through optional metadata, without a direct call.
    var ready = MetadataLazyReady's32{value: 42}
    let info  = cast(const *Swag.TypeInfoStruct) #typeof(MetadataLazyReady's32)
    Swag.assert(info.methods.count == 1)
    let address = info.methods![0].value
    Swag.assert(address != null)
    let read  = cast(func(*MetadataLazyReady's32)->s32) address
    let value = read(&ready)
    Swag.assert(value == 42)
}

func metadataCallGraphWorks()
{
    var receiver: MetadataReceiver
    receiver.emit()
    let callback: IMetadataReceiver = &receiver
    callback.notify()
    Swag.assert(receiver.count == 2)

    var ready = MetadataReady{value: 42}
    // Complete this body's analysis before requiring its optional metadata address.
    let readyValue = ready.read()
    Swag.assert(readyValue == 42)
    let info = cast(const *Swag.TypeInfoStruct) #typeof(MetadataReady)
    Swag.assert(info.methods.count == 1)
    let address = info.methods![0].value
    Swag.assert(address != null)
    let read = cast(func(*MetadataReady)->s32) address
    Swag.assert(read(&ready) == 42)
}

#run
{
    metadataCallGraphWorks()
    metadataLazyMethodWorks()
}

#test
{
    metadataCallGraphWorks()
    metadataLazyMethodWorks()
}
