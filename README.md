# Detección de bordes Sobel / Prewitt en FPGA Basys 3

Procesador de imágenes en escala de grises de 128×128 implementado en Verilog sobre la
FPGA Digilent Basys 3 (`xc7a35tcpg236-1`, reloj de 100 MHz). La PC envía la imagen por
UART (115200 baudios, 8N1), la FPGA aplica el filtro **Sobel** o **Prewitt** (elegido con
el switch **SW0**) y devuelve la imagen de bordes.

**Autor:** Ángel Casique

**Uso de IA:** el código fue diseñado y escrito por el autor. Gemini (Google) y Claude
(Anthropic) se usaron como apoyo de revisión y corrección (detalle en el encabezado de
cada archivo).

## Arquitectura

```
rx ─► uart_rx ─► window_gen ─► sobel ──┐
                       │                ├─► MUX (SW0) ─► saturación 8 bits ─► uart_tx ─► tx
                       └─────► prewit ──┘
```

| Módulo | Función |
|---|---|
| `uart_rx` | Receptor UART, FSM de 4 estados (IDLE, START, DATA, STOP), muestreo en el centro de cada bit |
| `window_gen` | Ventana 3×3 con 2 line buffers de 128 píxeles |
| `sobel` / `prewit` | Gradiente \|Gx\| + \|Gy\| en un pipeline de 2 ciclos |
| `top_module` | Conexión, MUX del filtro y saturación a 255 |
| `uart_tx` | Transmisor UART, FSM de 4 estados |

Por cada imagen entran 16384 bytes y salen **15876 (126×126)**: los píxeles del borde no
tienen ventana 3×3 completa. El script de Python rellena ese marco con ceros.

## Estructura

```
codes/
  uart_rx/        uart_rx.v      + tb_uartrx.v
  uart_tx/        uart_tx.v      + tb_uartx.v
  window/         window_gen.v   + tbwindow_gen.v
  filtro_sobel/   sobel.v        + tbsobel.v
  filtro_prewit/  prewit.v       + tbprewit.v
  top_module/     top_module.v, tb_checker.v, tb_image_processing.v,
                  tb_corner_cases_1.v, tb_corner_cases_2.v
python/
  fpga_core.py    comunicación serial, reconstrucción y filtro de referencia (NumPy)
  fpga_gui.py     interfaz gráfica
  fpga_cli.py     versión de consola
```

## Simulación (Icarus Verilog)

Todos los testbench son autoverificables e imprimen `RESULTADO: PASS` o `FAIL`.
Desde la carpeta `codes`:

```bash
(cd uart_rx       && iverilog -o sim_rx     uart_rx.v tb_uartrx.v       && vvp sim_rx)
(cd uart_tx       && iverilog -o sim_tx     uart_tx.v tb_uartx.v        && vvp sim_tx)
(cd window        && iverilog -o sim_window window_gen.v tbwindow_gen.v && vvp sim_window)
(cd filtro_sobel  && iverilog -o sim_sobel  sobel.v tbsobel.v           && vvp sim_sobel)
(cd filtro_prewit && iverilog -o sim_prewit prewit.v tbprewit.v         && vvp sim_prewit)

D="../uart_rx/uart_rx.v ../uart_tx/uart_tx.v ../window/window_gen.v ../filtro_sobel/sobel.v ../filtro_prewit/prewit.v top_module.v tb_checker.v"
(cd top_module && iverilog -o sim_img $D tb_image_processing.v && vvp sim_img)
(cd top_module && iverilog -o sim_cc1 $D tb_corner_cases_1.v   && vvp sim_cc1)
(cd top_module && iverilog -o sim_cc2 $D tb_corner_cases_2.v   && vvp sim_cc2)
```

Los testbench de integración usan `CLKS_PER_BIT = 16` para simular rápido; el hardware
usa 868 (100 MHz / 115200).

## Pines (Basys 3)

| Puerto | Pin | Descripción |
|---|---|---|
| `clk` | W5 | Reloj 100 MHz |
| `rst` | U18 | Botón central (btnC) |
| `filter` | V17 | SW0: 0 = Sobel, 1 = Prewitt |
| `rx` | B18 | USB-UART (PC → FPGA) |
| `tx` | A18 | USB-UART (FPGA → PC) |

## Interfaz en la PC

```bash
pip install pyserial pillow numpy
python python/fpga_gui.py
```

Carga una imagen, elige el puerto COM del UART, pon SW0 según el filtro y pulsa
**Procesar**. La interfaz compara el resultado de la FPGA con el mismo filtro calculado
en software; en la placa se obtuvo **100 % de coincidencia** (15876 de 15876 bytes).
