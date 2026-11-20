//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tb_image_processing  (versión ligera: una sola imagen)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): corrección de errores del testbench, adición del
//       verificador automático (tb_checker) y versión ligera de la simulación.
//
// CASOS CRÍTICOS EVALUADOS
//   1) Imagen completa 128x128 (16384 bytes) con una frontera vertical en la
//      columna 64 (izquierda 0x00 negro, derecha 0xFF blanco), filtro SOBEL.
//   2) Zonas planas (todo negro / todo blanco): el gradiente es 0 y la salida
//      debe ser 0x00.
//   3) Borde de máximo contraste: |Gx| = 1020 supera 255, por lo que la
//      SATURACIÓN debe entregar 0xFF. Se esperan 2 columnas de 0xFF por fila.
//   4) Llenado de ventana / bordes de la imagen: no hay salida en las 2
//      primeras filas ni en las 2 primeras columnas de cada fila ->
//      15876 salidas (126x126) y no 16384.
//
// PARÁMETROS (para aligerar la simulación)
//   FILAS         : 128 = imagen completa. Se puede bajar (p. ej. 8) para una
//                   prueba rapidísima; los conteos esperados se recalculan.
//   FILTRO        : 0 = Sobel, 1 = Prewitt (el resultado esperado es igual).
//   GUARDAR_ONDAS : 1 = guarda el .vcd solo de la fila 2 (la primera con
//                   ventanas completas, donde se ve la frontera de la col. 64).
//                   0 = no genera .vcd (la simulación corre aún más rápido).
//
// NOTA: CLKS_PER_BIT = 16 solo para simular rápido. El diseño real usa 868.
//       Con 868 esta simulación tardaría horas.
//==============================================================================
`timescale 1ns / 1ps

module tb_image_processing;

    localparam FILAS         = 128;
    localparam FILTRO        = 0;
    localparam GUARDAR_ONDAS = 1;

    localparam CLKS_PER_BIT = 16;                 // 868 = temporización real
    localparam BIT_NS       = CLKS_PER_BIT * 10;  // reloj de 10 ns

    // Conteos esperados: (FILAS-2) filas con ventana, 126 ventanas por fila,
    // y en cada una 2 salidas 0xFF (columnas 63 y 64 del centro de la ventana)
    localparam ESP_FF = (FILAS - 2) * 2;
    localparam ESP_00 = (FILAS - 2) * 124;

    reg        clk;
    reg        rst;
    reg        filter;
    reg        rx;
    wire       tx;

    // Instancia del Top Module
    top_module #(.CLKS_PER_BIT(CLKS_PER_BIT)) UUT (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .tx(tx),
        .filter(filter)
    );

    // Verificador automático (no es parte del diseño)
    tb_checker #(.CLKS_PER_BIT(CLKS_PER_BIT)) chk (
        .rst(rst),
        .tx(tx)
    );

    always #5 clk = ~clk;                         // 100 MHz

    // Envía un byte por UART (8N1, LSB primero)
    task send_byte(input [7:0] data);
        integer i;
        begin
            chk.push(data, filter);               // avisa al verificador
            rx = 0; #(BIT_NS);                    // Bit de Inicio
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i]; #(BIT_NS);          // Bits de Datos
            end
            rx = 1; #(BIT_NS);                    // Bit de Parada
        end
    endtask

    integer row, col;

    initial begin
        if (GUARDAR_ONDAS) begin
            $dumpfile("onda_imagen.vcd");
            $dumpvars(1, tb_image_processing);    // señales del testbench
            $dumpvars(0, UUT);                    // todo lo que hay dentro del diseño
            $dumpoff;                             // apagado hasta llegar a la fila 2
        end

        // Inicialización de señales
        clk    = 0;
        rst    = 1;
        rx     = 1;
        filter = FILTRO;                          // 0 = Sobel
        #100;
        rst    = 0;
        #100;

        $display("--- Inicio de transmision: imagen %0dx128, filtro = %0d ---", FILAS, FILTRO);

        for (row = 0; row < FILAS; row = row + 1) begin
            // Solo se guardan las ondas de la fila 2
            if (GUARDAR_ONDAS && row == 2) $dumpon;
            if (GUARDAR_ONDAS && row == 3) $dumpoff;

            for (col = 0; col < 128; col = col + 1) begin
                if (col < 64)
                    send_byte(8'h00);             // Mitad izquierda: Negro (0)
                else
                    send_byte(8'hFF);             // Mitad derecha: Blanco (255)
            end
        end

        #(BIT_NS * 40);                           // deja vaciar el transmisor
        chk.summary;
        if (chk.cnt_ff !== ESP_FF || chk.cnt_00 !== ESP_00)
            $display("[FAIL] Se esperaban %0d salidas 0xFF y %0d salidas 0x00", ESP_FF, ESP_00);
        else
            $display("[OK] Conteo de bordes correcto (%0d x 0xFF, %0d x 0x00)", ESP_FF, ESP_00);

        $display("--- Transmision finalizada ---");
        $finish;
    end

endmodule
