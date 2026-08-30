# Configuración de API
$API_URL = "https://pc-monitor-api.onrender.com/api/collect"
$API_KEY = "PCMONITOR_CAMBIA_ESTA_CLAVE_2026"

# Recopilación de información del sistema
$ComputerName = $env:COMPUTERNAME
$Username     = $env:USERNAME

# Hardware y SO
$CPU          = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
$Manufacturer = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer)
$Model        = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Model)
$OSName       = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)
$OSVersion    = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version)
$OSBuild      = (Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber)

$RAMBytes     = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory)
$RAM_GB       = if ($RAMBytes) { [math]::Round($RAMBytes / 1GB, 2) } else { $null }

# Discos
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    @{
        Unidad      = $_.DeviceID
        CapacidadGB = [math]::Round($_.Size / 1GB, 2)
        LibreGB     = [math]::Round($_.FreeSpace / 1GB, 2)
    }
}

# GPU
$GPUs = Get-CimInstance Win32_VideoController | ForEach-Object {
    @{
        Nombre    = $_.Name
        MemoriaMB = [math]::Round($_.AdapterRAM / 1MB, 0)
        Driver    = $_.DriverVersion
    }
}

# Red
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

# Estructura del reporte
$Report = @{
    NombreEquipo      = $ComputerName
    Equipo            = $ComputerName
    Usuario           = $Username
    NombreUsuario     = $Username
    Fabricante        = $Manufacturer
    Modelo            = $Model
    SistemaOperativo  = $OSName
    VersionWindows    = $OSVersion
    BuildWindows      = $OSBuild
    Procesador        = $CPU
    RAM_Total_GB      = $RAM_GB
    GPU               = $GPUs
    Discos            = $Disks
    AdaptadoresRed    = $NetAdapters
    ConfiguracionIP   = $IPConfig
    Consentimiento    = $true
}

# Convertir a JSON y enviar a la API
$JsonPayload = $Report | ConvertTo-Json -Depth 5 -Compress

$Headers = @{
    "Content-Type" = "application/json; charset=utf-8"
    "X-API-Key"    = $API_KEY
}

try {
    Invoke-RestMethod -Uri $API_URL -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($JsonPayload)) -Headers $Headers -TimeoutSec 30
} catch {
    # Manejo silencioso de errores
}
