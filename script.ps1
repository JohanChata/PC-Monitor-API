# Configuración de API
$API_URL = "https://pc-monitor-api.onrender.com/api/collect"
$API_KEY = "PCMONITOR_CAMBIA_ESTA_CLAVE_2026"

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Obtención de Ubicación Nativa en Tiempo Real (Windows Location API)
$Lat = $Lon = $Precision = $FuenteUbic = $GoogleMaps = $null

try {
    # Cargar API de geolocalización nativa de Windows
    Add-Type -AssemblyName System.Device
    $Watcher = New-Object System.Device.Location.GeoCoordinateWatcher([System.Device.Location.GeoPositionAccuracy]::High)
    $Watcher.Start()

    # Esperar a que los sensores de red/Wi-Fi triangulen la posición real (hasta 6 segundos)
    $timeout = 0
    while (($Watcher.Status -ne [System.Device.Location.GeoPositionStatus]::Ready) -and ($timeout -lt 60)) {
        Start-Sleep -Milliseconds 100
        $timeout++
    }

    $Pos = $Watcher.Position.Location
    if (-not $Pos.IsUnknown) {
        $Lat        = $Pos.Latitude
        $PosLat     = [math]::Round($Pos.Latitude, 6)
        $PosLon     = [math]::Round($Pos.Longitude, 6)
        $Lat        = $PosLat
        $Lon        = $PosLon
        $Precision  = [math]::Round($Pos.HorizontalAccuracy, 2)
        $FuenteUbic = "Windows Sensor (GPS/Wi-Fi Real Time)"
        $GoogleMaps = "https://www.google.com/maps?q=$PosLat,$PosLon"
    }
} catch {
    # Manejo en caso de fallo
}

# Si la ubicación por sensor está desactivada en Windows, usa IP pública como respaldo
if (-not $Lat) {
    $GeoIP = Try { Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 5 } Catch { $null }
    if ($GeoIP -and $GeoIP.loc) {
        $coords     = $GeoIP.loc -split ","
        $Lat        = $coords[0]
        $Lon        = $coords[1]
        $Precision  = 5000
        $FuenteUbic = "IP Geolocation (Nodo ISP / Aproximado)"
        $GoogleMaps = "https://www.google.com/maps?q=$Lat,$Lon"
    }
}

# 2. Recopilación de Hardware y Sistema
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
