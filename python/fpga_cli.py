"""
Proyecto : Procesador de imágenes 128x128 con detección de bordes (Sobel / Prewitt)
           en FPGA Basys 3 (xc7a35tcpg236-1)
Archivo  : fpga_cli.py  (versión de consola, sin interfaz gráfica)
Autor    : Ángel Casique

DECLARACIÓN DE USO DE IA
  Este código fue diseñado y escrito por el autor (Ángel Casique). La IA se usó
  como apoyo de corrección:
    - Gemini (Google): revisó el código que el autor iba escribiendo.
    - Claude (Anthropic): revisión final y corrección de errores (ver
      "Correcciones" en fpga_core.py).

Uso:   python fpga_cli.py
  1) Pon el switch SW0 de la Basys 3 (abajo = Sobel, arriba = Prewitt).
  2) Ajusta PUERTO y FILTRO_EN_PLACA (debe coincidir con SW0).
"""
import numpy as np
from PIL import Image

import fpga_core as core

# 1. CONFIGURACIÓN
PUERTO = "COM3"
FILTRO_EN_PLACA = "Sobel"        # "Sobel" si SW0 = 0, "Prewitt" si SW0 = 1
IMAGEN = "foto_prueba.jpg"


def main():
    # 2. PREPARACIÓN DE LA IMAGEN: gris, 128x128, aplanada a 16384 bytes
    print("Cargando y formateando la imagen...")
    img_array = core.preparar_imagen(IMAGEN)

    # 3. TRANSMISIÓN Y RECEPCIÓN
    print(f"Enviando {core.N_ENTRADA} píxeles a la FPGA ({PUERTO})...")
    datos_rx, segundos = core.procesar_en_fpga(
        PUERTO, img_array, progreso=lambda f: print(f"\r  {f * 100:5.1f} %", end="")
    )
    print()

    if len(datos_rx) < core.N_SALIDA:
        print(f"Error: se esperaban {core.N_SALIDA} bytes y llegaron {len(datos_rx)}.")
        print("Revisa: bitstream cargado, SW0, reset (btnC) y que el puerto sea el UART.")
        return
    print(f"¡Proceso completo! {len(datos_rx)} bytes en {segundos:.2f} s.")

    # 4. RECONSTRUCCIÓN: 126x126 + marco de ceros = 128x128
    resultado = core.reconstruir(datos_rx)

    # 5. COMPARACIÓN CON EL MISMO FILTRO CALCULADO EN SOFTWARE
    referencia = core.filtro_referencia(img_array, FILTRO_EN_PLACA)
    coincide = np.mean(resultado == referencia) * 100
    print(f"Coincidencia con la referencia en software ({FILTRO_EN_PLACA}): {coincide:.2f} %")

    # 6. GUARDAR Y MOSTRAR (PNG: sin pérdida; JPG alteraría los valores)
    imagen_final = Image.fromarray(resultado)
    imagen_final.save("resultado_fpga.png")
    imagen_final.show()


if __name__ == "__main__":
    main()
