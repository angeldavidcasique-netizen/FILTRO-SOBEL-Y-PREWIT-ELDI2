"""
Proyecto : Procesador de imágenes 128x128 con detección de bordes (Sobel / Prewitt)
           en FPGA Basys 3 (xc7a35tcpg236-1)
Archivo  : fpga_core.py  (funciones comunes para la interfaz y el script de consola)
Autor    : Ángel Casique

DECLARACIÓN DE USO DE IA
  Este código fue diseñado y escrito por el autor (Ángel Casique). La IA se usó
  como apoyo de corrección:
    - Gemini (Google): revisó el código que el autor iba escribiendo.
    - Claude (Anthropic): revisión final y corrección de errores sobre el
      trabajo del autor (ver "Correcciones" más abajo).

Qué hace la FPGA con una imagen
  La PC envía 16384 bytes (128x128). La FPGA devuelve SOLO 15876 bytes (126x126):
  los píxeles del marco de la imagen no tienen ventana 3x3 completa. Aquí se
  rellena ese marco con ceros (np.pad) para volver a 128x128.
  El filtro (Sobel / Prewitt) NO se elige por UART: lo elige el switch SW0 de
  la Basys 3 (abajo = Sobel, arriba = Prewitt).

Correcciones respecto a la versión anterior
  1) Se leen 15876 bytes (126x126) y no 16384; luego se rellena el marco.
  2) Se quitó el byte de comando 0x01/0x02: la FPGA no lo espera y lo habría
     tomado como el primer píxel de la imagen (toda la imagen quedaba corrida).
  3) Envío por bloques leyendo a la vez: la FPGA contesta mientras la PC aún
     transmite, y con write() + read() el buffer de recepción de Windows
     (4096 bytes por defecto) se desbordaba y se perdían datos.
  4) Se limpia el buffer de entrada antes de enviar y se espera con un tiempo
     límite razonable en lugar de un timeout fijo de 5 s por llamada.
  5) filtro_referencia(): el mismo filtro calculado en software con NumPy
     para comparar contra lo que devuelve la FPGA.
"""
import time

import numpy as np
import serial
from serial.tools import list_ports
from PIL import Image

M = 128                      # lado de la imagen
BAUD_RATE = 115200
LADO_SALIDA = M - 2          # 126
N_ENTRADA = M * M            # 16384 bytes que se envían
N_SALIDA = LADO_SALIDA ** 2  # 15876 bytes que devuelve la FPGA

# Compatibilidad entre versiones de Pillow
NEAREST = getattr(Image, "Resampling", Image).NEAREST


def listar_puertos():
    """Devuelve [(puerto, descripción), ...] de los puertos serial disponibles."""
    return [(p.device, p.description) for p in list_ports.comports()]


def preparar_imagen(ruta):
    """Abre la imagen, la pasa a escala de grises y la deja en 128x128 (uint8)."""
    img = Image.open(ruta).convert("L").resize((M, M))
    return np.array(img, dtype=np.uint8)


def filtro_referencia(img, filtro):
    """
    Calcula en software lo mismo que hace la FPGA:
      |Gx| + |Gy| saturado a 255, con el marco de 1 píxel en 0.
    filtro: "Sobel" o "Prewitt". Devuelve una matriz uint8 de 128x128.
    """
    a = img.astype(np.int32)
    w11, w12, w13 = a[:-2, :-2], a[:-2, 1:-1], a[:-2, 2:]
    w21, w23 = a[1:-1, :-2], a[1:-1, 2:]
    w31, w32, w33 = a[2:, :-2], a[2:, 1:-1], a[2:, 2:]
    if filtro == "Sobel":
        gx = (w13 + 2 * w23 + w33) - (w11 + 2 * w21 + w31)
        gy = (w31 + 2 * w32 + w33) - (w11 + 2 * w12 + w13)
    else:  # Prewitt
        gx = (w13 + w23 + w33) - (w11 + w21 + w31)
        gy = (w31 + w32 + w33) - (w11 + w12 + w13)
    mag = np.minimum(np.abs(gx) + np.abs(gy), 255).astype(np.uint8)
    return np.pad(mag, 1)


def reconstruir(datos_rx):
    """Convierte los 15876 bytes recibidos en una imagen 128x128 con marco en 0."""
    arr = np.frombuffer(bytes(datos_rx[:N_SALIDA]), dtype=np.uint8)
    return np.pad(arr.reshape((LADO_SALIDA, LADO_SALIDA)), 1)


def procesar_en_fpga(puerto, img_array, progreso=None, espera_final=3.0, bloque=256):
    """
    Envía la imagen por UART y recibe el resultado.
    progreso(fraccion) se llama (si existe) con un valor entre 0 y 1.
    Devuelve (bytes_recibidos, segundos).
    """
    datos_tx = bytes(img_array.flatten())
    rx = bytearray()

    ser = serial.Serial(puerto, BAUD_RATE, timeout=0.05, write_timeout=10)
    try:
        try:
            ser.set_buffer_size(rx_size=1 << 16, tx_size=1 << 16)   # solo Windows
        except Exception:
            pass
        time.sleep(0.5)
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        t0 = time.time()
        # Se envía por bloques y, entre bloque y bloque, se vacía lo que ya devolvió la FPGA
        for i in range(0, len(datos_tx), bloque):
            ser.write(datos_tx[i:i + bloque])
            if ser.in_waiting:
                rx += ser.read(ser.in_waiting)
            if progreso:
                progreso(min((i + bloque) / len(datos_tx), 1.0) * 0.9)

        # Espera lo que falta (hasta que lleguen todos o pase 'espera_final' sin datos)
        ultimo = time.time()
        while len(rx) < N_SALIDA and (time.time() - ultimo) < espera_final:
            n = ser.in_waiting
            if n:
                rx += ser.read(n)
                ultimo = time.time()
                if progreso:
                    progreso(0.9 + 0.1 * min(len(rx) / N_SALIDA, 1.0))
            else:
                time.sleep(0.01)
        t1 = time.time()
    finally:
        ser.close()

    if progreso:
        progreso(1.0)
    return bytes(rx), t1 - t0
