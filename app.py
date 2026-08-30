from flask import Flask, request, jsonify
import psycopg
from psycopg.rows import tuple_row
import os
import json
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

API_KEY = os.getenv("API_KEY")
DATABASE_URL = os.getenv("DATABASE_URL")


# ============================================================
# CONEXIÓN POSTGRESQL
# ============================================================

def conectar_db():
    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL no configurada")

    return psycopg.connect(
        DATABASE_URL,
        row_factory=tuple_row
    )


# ============================================================
# AUTENTICACIÓN
# ============================================================

def autorizado():
    key = request.headers.get("X-API-Key")
    return bool(API_KEY and key and key == API_KEY)


# ============================================================
# INICIO
# ============================================================

@app.get("/")
def inicio():
    return jsonify({
        "service": "PC-Monitor API",
        "status": "online"
    })


# ============================================================
# RECIBIR DATOS
# ============================================================

@app.post("/api/collect")
def recibir_datos():

    if not autorizado():
        return jsonify({
            "error": "No autorizado"
        }), 401

    data = request.get_json(silent=True)

    if not data:
        return jsonify({
            "error": "JSON no válido"
        }), 400

    # ========================================================
    # CONSENTIMIENTO
    # ========================================================

    if data.get("Consentimiento") is not True:
        return jsonify({
            "error": "Se requiere consentimiento para registrar el equipo"
        }), 403

    nombre_equipo = data.get("NombreEquipo")

    if not nombre_equipo:
        return jsonify({
            "error": "Falta NombreEquipo"
        }), 400

    # ========================================================
    # USUARIO
    # ========================================================

    usuario_completo = data.get("Usuario")
    nombre_usuario = data.get("NombreUsuario")
    nombre_completo = data.get("NombreCompleto")

    fabricante = data.get("Fabricante")
    modelo = data.get("Modelo")

    sistema_operativo = data.get("SistemaOperativo")
    version_windows = data.get("VersionWindows")
    arquitectura = data.get("Arquitectura")

    ip_publica = data.get("IP_Publica")

    latitud = data.get("Latitud")
    longitud = data.get("Longitud")
    precision = data.get("PrecisionMetros")
    fuente = data.get("FuenteUbicacion")
    google_maps = data.get("GoogleMaps")

    datos_json = json.dumps(
        data,
        ensure_ascii=False
    )

    # ========================================================
    # DOMINIO
    # ========================================================

    dominio = None

    if usuario_completo and "\\" in usuario_completo:
        dominio = usuario_completo.split("\\", 1)[0]

    conexion = None
    cursor = None

    try:

        conexion = conectar_db()
        cursor = conexion.cursor()

        # ====================================================
        # USUARIO
        # ====================================================

        cursor.execute(
            """
            SELECT id
            FROM usuarios
            WHERE username = %s
              AND (
                    dominio = %s
                    OR (dominio IS NULL AND %s::VARCHAR IS NULL)
                  )
            LIMIT 1
            """,
            (
                nombre_usuario,
                dominio,
                dominio
            )
        )

        usuario_db = cursor.fetchone()

        if usuario_db:

            usuario_id = usuario_db[0]

            cursor.execute(
                """
                UPDATE usuarios
                SET nombre_completo = %s
                WHERE id = %s
                """,
                (
                    nombre_completo,
                    usuario_id
                )
            )

        else:

            cursor.execute(
                """
                INSERT INTO usuarios
                (
                    username,
                    nombre_completo,
                    dominio,
                    tipo_cuenta
                )
                VALUES
                (
                    %s,
                    %s,
                    %s,
                    %s
                )
                RETURNING id
                """,
                (
                    nombre_usuario,
                    nombre_completo,
                    dominio,
                    "Windows"
                )
            )

            usuario_id = cursor.fetchone()[0]

        # ====================================================
        # COMPUTADORA
        # ====================================================

        cursor.execute(
            """
            SELECT id
            FROM computadoras
            WHERE nombre_equipo = %s
            LIMIT 1
            """,
            (
                nombre_equipo,
            )
        )

        computadora_db = cursor.fetchone()

        if computadora_db:

            computadora_id = computadora_db[0]

            cursor.execute(
                """
                UPDATE computadoras
                SET
                    usuario_id = %s,
                    fabricante = %s,
                    modelo = %s,
                    sistema_operativo = %s,
                    version_windows = %s,
                    arquitectura = %s,
                    ip_publica = %s,
                    latitud = %s,
                    longitud = %s,
                    precision_metros = %s,
                    fuente_ubicacion = %s,
                    google_maps = %s,
                    datos_json = %s::jsonb,
                    ultima_actualizacion = CURRENT_TIMESTAMP
                WHERE id = %s
                """,
                (
                    usuario_id,
                    fabricante,
                    modelo,
                    sistema_operativo,
                    version_windows,
                    arquitectura,
                    ip_publica,
                    latitud,
                    longitud,
                    precision,
                    fuente,
                    google_maps,
                    datos_json,
                    computadora_id
                )
            )

        else:

            cursor.execute(
                """
                INSERT INTO computadoras
                (
                    usuario_id,
                    nombre_equipo,
                    fabricante,
                    modelo,
                    sistema_operativo,
                    version_windows,
                    arquitectura,
                    ip_publica,
                    latitud,
                    longitud,
                    precision_metros,
                    fuente_ubicacion,
                    google_maps,
                    datos_json
                )
                VALUES
                (
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s::jsonb
                )
                RETURNING id
                """,
                (
                    usuario_id,
                    nombre_equipo,
                    fabricante,
                    modelo,
                    sistema_operativo,
                    version_windows,
                    arquitectura,
                    ip_publica,
                    latitud,
                    longitud,
                    precision,
                    fuente,
                    google_maps,
                    datos_json
                )
            )

            computadora_id = cursor.fetchone()[0]

        # ====================================================
        # ADAPTADORES DE RED
        # ====================================================

        adaptadores = data.get(
            "AdaptadoresRed",
            []
        )

        cursor.execute(
            """
            DELETE FROM adaptadores_red
            WHERE computadora_id = %s
            """,
            (
                computadora_id,
            )
        )

        for adaptador in adaptadores:

            cursor.execute(
                """
                INSERT INTO adaptadores_red
                (
                    computadora_id,
                    nombre,
                    descripcion,
                    estado,
                    mac_address,
                    velocidad
                )
                VALUES
                (
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s
                )
                """,
                (
                    computadora_id,
                    adaptador.get("Nombre"),
                    adaptador.get("Descripcion"),
                    adaptador.get("Estado"),
                    adaptador.get("MAC"),
                    adaptador.get("Velocidad")
                )
            )

        # ====================================================
        # HISTORIAL
        # ====================================================

        ip_local = obtener_ip_local(data)

        cursor.execute(
            """
            INSERT INTO historial
            (
                computadora_id,
                ip_local,
                ip_publica
            )
            VALUES
            (
                %s,
                %s,
                %s
            )
            """,
            (
                computadora_id,
                ip_local,
                ip_publica
            )
        )

        # ====================================================
        # GUARDAR
        # ====================================================

        conexion.commit()

        return jsonify({
            "success": True,
            "message": "Datos almacenados correctamente",
            "computadora_id": computadora_id,
            "usuario_id": usuario_id
        }), 201

    except Exception as error:

        if conexion:
            conexion.rollback()

        print("ERROR:", error)

        return jsonify({
            "success": False,
            "error": "Error interno del servidor"
        }), 500

    finally:

        if cursor:
            cursor.close()

        if conexion:
            conexion.close()


# ============================================================
# OBTENER IP LOCAL
# ============================================================

def obtener_ip_local(data):

    configuracion = data.get(
        "ConfiguracionIP",
        []
    )

    for adaptador in configuracion:

        ipv4 = adaptador.get(
            "IPv4",
            []
        )

        for ip in ipv4:

            if ip and not ip.startswith("169.254."):
                return ip

    return None


# ============================================================
# SERVIDOR
# ============================================================

if __name__ == "__main__":

    port = int(os.getenv("PORT", "5050"))

    app.run(
        host="0.0.0.0",
        port=port,
        debug=False
    )