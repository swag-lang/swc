using Core, Win32

// Groups voices in a controllable submix.
//
// Route one or more [[Audio.Voice]] instances through a bus with
// [[Audio.Voice.setRooting]]. Volume changes apply to every routed voice. Buses
// may target a parent bus to form a mixing graph.
public struct Bus
{
    handle: BusHandle     // Backend-owned submix handle, or `null` after destruction.
}

public impl Bus
{
    // Creates a bus with the requested channel count.
    //
    // When `parent` is non-null, this bus sends its output to that bus;
    // otherwise it sends to the mastering output. The caller owns the returned
    // allocation and must eventually call [[Audio.Bus.destroy]]. The parent
    // must outlive this bus.
    func create(numChannels: u32, parent: #null *Bus = null)->#null *Bus fail
    {
        let bus = Memory.new'Bus()
        defer #fail Memory.delete(bus)
        createNative(bus, numChannels, parent)

        Sync.scopedLock(&g_Driver.mutexBuses)
        g_Driver.buses.add(bus)
        return bus
    }

    // Destroys the native submix and frees this bus immediately.
    //
    // Voices and child buses must be rerouted or destroyed first. The pointer
    // is invalid after this method returns.
    mtd destroy() fail
    {
        .destroyNative()

        Sync.scopedLock(&g_Driver.mutexBuses)
        g_Driver.buses.remove(me)
        Memory.delete(&me)
    }

    // Sets the bus gain in decibels.
    //
    // `batchID` is forwarded to backends that support deferred operation sets.
    mtd setVolumeDB(volumeDB: f32, batchID: u32 = 0) fail
    {
        .setVolume(convertDBToPercent(volumeDB), batchID)
    }

    // Returns the current bus gain in decibels.
    mtd getVolumeDB()->f32 fail
    {
        return convertPercentToDB(.getVolume())
    }
}
