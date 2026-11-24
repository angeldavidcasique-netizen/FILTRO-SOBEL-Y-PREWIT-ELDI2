# Declaración de uso de Inteligencia Artificial

**Proyecto:** Detección de bordes Sobel / Prewitt en FPGA Basys 3
**Autor:** Ángel Casique

Este documento describe **de forma general** cómo se usó la IA en todo el proyecto.
Los **cambios específicos de cada módulo** (qué se corrigió y por qué) están escritos
**dentro de cada archivo**, en su encabezado, en las secciones *"DECLARACIÓN DE USO DE IA"*
y *"Correcciones respecto a la versión anterior"*.

| Dónde leer | Qué contiene |
|---|---|
| `USO_DE_IA.md` (este archivo) | Uso general de la IA en todo el proyecto |
| Encabezado de cada `.v` y `.py` | Cambios concretos hechos en ese módulo o testbench |

---

## 1. Herramientas usadas

| Herramienta | Empresa | Rol |
|---|---|---|
| **Gemini** | Google | Acompañamiento durante el desarrollo inicial |
| **Claude** | Anthropic | Revisión final, corrección de errores, verificación y documentación |

## 2. Qué hizo el autor

- Diseñó la arquitectura del sistema (UART RX → ventana 3×3 → Sobel/Prewitt → MUX y
  saturación → UART TX) y escogió la FPGA, las herramientas y el protocolo.
- Escribió e instanció la primera versión de todos los módulos Verilog
  (`uart_rx`, `uart_tx`, `window_gen`, `sobel`, `prewit`, `top_module`).
- Planteó los casos de prueba de los testbench (casos normales, casos límite, resets,
  pausas, cambio de filtro, saturación).
- Escribió la primera versión del script de Python y de la interfaz gráfica.
- Escribió el archivo de restricciones `.xdc` con los pines de la Basys 3.
- Ejecutó todas las simulaciones en Icarus Verilog / GTKWave en su computador,
  sintetizó e implementó el diseño en Vivado y lo probó en la placa física.
- Revisó y estudió cada cambio propuesto por la IA para poder explicarlo y defenderlo.

## 3. Uso de Gemini (Google)

Se usó durante el desarrollo inicial con una dinámica de **"toma y dame"**: el autor
escribía el código y Gemini lo revisaba y sugería correcciones, que el autor aplicaba.
Gemini no generó los módulos completos.

## 4. Uso de Claude (Anthropic)

### 4.1 Revisión y corrección del diseño (Verilog)
Claude revisó el código del autor, encontró errores y los corrigió manteniendo la
estructura original (mismos módulos, nombres de señales y FSM de 4 estados).
Errores principales encontrados:

- **`uart_rx`:** `rx_ready` se quedaba en 1 (debía ser un pulso de 1 ciclo); los bits se
  muestreaban en el borde y no en el centro; faltaba sincronizador de 2 flip-flops;
  la cuenta de bit era de 869 ciclos en lugar de 868.
- **`uart_tx`:** duración de bit de 869 ciclos (el transmisor se atrasaba y perdía
  bytes); desfase de un ciclo entre contador y salida; bit de parada acortado a 3/4.
- **`window_gen`:** `o_valid` se quedaba en 1 (debía ser un pulso por ventana); el
  reset de las memorias con un `for` no es sintetizable como RAM y se cambió por un
  bloque `initial`.
- **`sobel` y `prewit`:** no necesitaron cambios de lógica; solo se agregaron comentarios.
- **`top_module`:** se agregó el parámetro `CLKS_PER_BIT` para simular rápido y se
  ajustó el ancho de `prewit_pix` en el MUX.

El detalle de cada corrección está en el encabezado de cada módulo.

### 4.2 Testbench
- Encontró el error que causaba las **X rojas** en `tb_image_processing`
  (un `#100;` quedó dentro de un comentario y el reset nunca ocurría).
- Corrigió carreras con el reloj en los testbench unitarios.
- Convirtió todos los testbench en **autoverificables** (imprimen `PASS` / `FAIL`),
  conservando los casos de prueba planteados por el autor y agregando algunos.
- Escribió el verificador `tb_checker.v`, que calcula el resultado esperado y decodifica
  la salida UART.
- Creó una versión ligera de la simulación de la imagen completa.

### 4.3 Verificación
- Validó la lógica con un modelo ciclo a ciclo en Python mientras no había simulador
  disponible.
- Las simulaciones reales las ejecutó el autor en su computador: los 8 testbench
  dieron `RESULTADO: PASS`.

### 4.4 Python e interfaz
- Corrigió errores del script original: leer 15876 bytes (126×126) en vez de 16384,
  quitar un byte de comando que la FPGA no esperaba, enviar y recibir por bloques para
  no desbordar el buffer serial y guardar en PNG en vez de JPG.
- Reorganizó el código en `fpga_core.py`, `fpga_cli.py` y `fpga_gui.py`.
- Rediseñó el aspecto de la interfaz gráfica del autor y le agregó la comparación con
  una referencia calculada en software.

### 4.5 Documentación y repositorio
- Agregó los encabezados con autor, declaración de IA y casos críticos en cada archivo.
- Redactó el `README.md` y este documento.
- Ayudó a organizar el repositorio: subió el código, los esquemáticos y el informe, y
  ordenó los mensajes de los commits. Por esos commits, GitHub puede mostrar a
  **Claude** en la lista de *Contributors* del repositorio; no es un colaborador
  humano, es la herramienta de IA declarada en este documento.

## 5. Resultado
El diseño corregido funcionó en la placa Basys 3: la imagen devuelta por la FPGA
coincidió en un **100 %** (15876 de 15876 bytes) con el mismo filtro calculado en
software.
