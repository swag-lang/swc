#global if #os == Swag.TargetOs.Linux

const SupportsWinFspInstall = false

func hasInstalledWinFsp()->bool => false

func installWinFspNative() fail { fail volumeError(.DriverUnavailable) }
