# Configuración de API y Autenticación
$API_URL = "https://pc-monitor-api.onrender.com/api/collect"
$API_KEY = "PCMONITOR_CAMBIA_ESTA_CLAVE_2026"

# Iniciar cronómetro de recopilación
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Obtención de Ubicación por IP (Con User-Agent de Chrome para evitar bloqueos)
$UA = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" }

# Intento 1: ipinfo.io
$GeoIP = Try { Invoke-RestMethod -Uri "https://ipinfo.io/json" -Headers $UA -TimeoutSec 5 } Catch { $null }

if ($GeoIP -and $GeoIP.loc) {
    $coords       = $GeoIP.loc -split ","
    $Lat          = $coords[0]
    $Lon          = $coords[1]
    $IP_Publica   = $GeoIP.ip
    $GoogleMaps   = "https://www.google.com/maps?q=$Lat,$Lon"
    $Precision    = 5000
    $FuenteUbic   = "ipinfo.io ($($GeoIP.city), $($GeoIP.country))"
} else {
    # Intento 2: ip-api.com
    $GeoIP2 = Try { Invoke-RestMethod -Uri "http://ip-api.com/json/" -Headers $UA -TimeoutSec 5 } Catch { $null }
    
    if ($GeoIP2 -and $GeoIP2.status -eq "success") {
        $Lat          = $GeoIP2.lat
        $Lon          = $GeoIP2.lon
        $IP_Publica   = $GeoIP2.query
        $GoogleMaps   = "https://www.google.com/maps?q=$Lat,$Lon"
        $Precision    = 5000 
        $FuenteUbic   = "ip-api.com ($($GeoIP2.city), $($GeoIP2.country))"
    } else {
        $Lat = $Lon = $IP_Publica = $GoogleMaps = $Precision = $FuenteUbic = $null
    }
}

# 2. Datos del Sistema y Usuario
$ComputerName = $env:COMPUTERNAME
$Username     = $env:USERNAME

# Hardware y Sistema Operativo
$CPU          = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
$CpuCount     = [Environment]::ProcessorCount
$Manufacturer = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer)
$Model        = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Model)
$OSName       = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)
$OSVersion    = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version)
$OSBuild      = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber)

# Memoria RAM
$RAMBytes     = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory)
$RAM_GB       = if ($RAMBytes) { [math]::Round($RAMBytes / 1GB, 2) } else { $null }

# Discos Rígidos y SSDs
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    @{
        Unidad      = $_.DeviceID
        CapacidadGB = [math]::Round($_.Size / 1GB, 2)
        LibreGB     = [math]::Round($_.FreeSpace / 1GB, 2)
    }
}

# Placa de Video / GPUs
$GPUs = Get-CimInstance Win32_VideoController | ForEach-Object {
    @{
        Nombre    = $_.Name
        MemoriaMB = [math]::Round($_.AdapterRAM / 1MB, 0)
        Driver    = $_.DriverVersion
    }
}

# Configuración e Interfaces de Red
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

# Detener cronómetro
$Stopwatch.Stop()
$TiempoProcesamientoMs = $Stopwatch.ElapsedMilliseconds

# 3. Estructura Completa del Reporte para la API
$Report = @{
    NombreEquipo          = $ComputerName
    Equipo                = $ComputerName
    Usuario               = $Username
    NombreUsuario         = $Username
    NombreCompleto        = ""
    CuentaActiva          = $true

    Fabricante            = $Manufacturer
    Modelo                = $Model
    FabricantePC          = $Manufacturer
    ModeloPC              = $Model

    SistemaOperativo      = $OSName
    VersionWindows        = $OSVersion
    BuildWindows          = $OSBuild
    Arquitectura          = if ([Environment]::Is64BitOperatingSystem) { "64bit" } else { "32bit" }

    Procesador            = $CPU
    Nucleos               = $CpuCount
    Hilos                 = $CpuCount

    RAM_Total_GB          = $RAM_GB
    ModulosRAM            = @()

    GPU                   = $GPUs
    Discos                = $Disks

    # Campos de Geolocalización
    IP_Publica            = $IP_Publica
    Latitud               = $Lat
    Longitud              = $Lon
    PrecisionMetros       = $Precision
    FuenteUbicacion       = $FuenteUbic
    GoogleMaps            = $GoogleMaps
    TiempoRecopilacionMs  = $TiempoProcesamientoMs

    AdaptadoresRed        = $NetAdapters
    ConfiguracionIP       = $IPConfig

    Consentimiento        = $true
}

# Convertir a JSON
$JsonPayload = $Report | ConvertTo-Json -Depth 5 -Compress

$Headers = @{
    "Content-Type" = "application/json; charset=utf-8"
    "X-API-Key"    = $API_KEY
}

# Enviar los datos POST a la API
try {
    Invoke-RestMethod -Uri $API_URL -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($JsonPayload)) -Headers $Headers -TimeoutSec 30
} catch {
    # Silencioso
}
