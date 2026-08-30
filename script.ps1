# Configuración de API y Autenticación
$API_URL = "https://pc-monitor-api.onrender.com/api/collect"
$API_KEY = "PCMONITOR_CAMBIA_ESTA_CLAVE_2026"

# Iniciar cronómetro de recopilación
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Obtención de Ubicación por IP y enlace a Google Maps
$GeoIP = Try { Invoke-RestMethod -Uri "https://ipapi.co/json/" -TimeoutSec 5 } Catch { $null }

if ($GeoIP -and $GeoIP.latitude -and $GeoIP.longitude) {
    $Lat          = $GeoIP.latitude
    $Lon          = $GeoIP.longitude
    $IP_Publica   = $GeoIP.ip
    $GoogleMaps   = "https://www.google.com/maps?q=$Lat,$Lon"
    $Precision    = 5000 # Precisión estimada por IP en metros (~5 km)
    $FuenteUbic   = "IP Geolocation ($($GeoIP.city), $($GeoIP.country_name))"
} else {
    $Lat          = $null
    $Lon          = $null
    $IP_Publica   = $null
    $GoogleMaps   = $null
    $Precision    = $null
    $FuenteUbic   = $null
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

    # Campos de Geolocalización y Maps
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

# Convertir a JSON enviando todos los datos
$JsonPayload = $Report | ConvertTo-Json -Depth 5 -Compress

$Headers = @{
    "Content-Type" = "application/json; charset=utf-8"
    "X-API-Key"    = $API_KEY
}

# Enviar los datos POST a la API de Render
try {
    Invoke-RestMethod -Uri $API_URL -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($JsonPayload)) -Headers $Headers -TimeoutSec 30
} catch {
    # Silencioso en caso de error
}
