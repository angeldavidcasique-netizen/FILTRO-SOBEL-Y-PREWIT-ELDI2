//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tb_corner_cases_2  (saturación y reset en mitad de transmisión)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): corrección de errores del testbench y adición del
//       verificador automático (tb_checker) para obtener PASS/FAIL.
//
// CASOS CRÍTICOS EVALUADOS
//   1) Saturación máxima (SOBEL): patrón 00 00 FF FF repetido. Entre las
//      columnas c-2 y c hay 0x00 contra 0xFF, así |Gx| = 1020 > 255 y la
//      salida debe saturar a 0xFF en todas las ventanas válidas.
//      (Con el patrón 00 FF 00 FF la salida sería 0 porque c y c-2 son
//      iguales; por eso se usó un periodo de 4 píxeles.)
//   2) Reset en mitad de una transmisión: se envían 50 bytes más, se empieza
//      un byte nuevo (bit de inicio + 3 bits) y en ese momento se activa rst.
//      Todo el sistema (UART, contadores, ventana, TX) debe volver a reposo.
//   3) Recuperación después del reset: se envía una secuencia de datos
//      variados; los contadores de fila/columna deben haber vuelto a cero
//      (no hay salida hasta el byte 258) y los resultados deben ser correctos.
//
// NOTA: CLKS_PER_BIT = 16 solo para simular rápido. El diseño real usa 868.
//==============================================================================
`timescale 1ns / 1ps

module tb_corner_cases_2;

    localparam CLKS_PER_BIT = 16;                 // 868 = temporización real
    localparam BIT_NS       = CLKS_PER_BIT * 10;  // reloj de 10 ns

    reg        clk;
    reg        rst;
    reg        filter;
    reg        rx;
    wire       tx;

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

    always #5 clk = ~clk;

    task send_byte(input [7:0] data);
        integer i;
        begin
            chk.push(data, filter);
            rx = 0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i]; #(BIT_NS);
            end
            rx = 1; #(BIT_NS);
        end
    endtask

    integer k;

    initial begin
        $dumpfile("onda_cc2.vcd");
        $dumpvars(1, tb_corner_cases_2);          // señales del testbench
        $dumpvars(0, UUT);                        // todo lo que hay dentro del diseño

        clk    = 0;
        rst    = 1;
        rx     = 1;
        filter = 0; #100;
        rst    = 0; #100;

        // PRUEBA 1: Saturación Máxima (patrón 00 00 FF FF -> |Gx| = 1020)
        $display("Test 1: Prueba de Saturacion de Gradiente");
        for (k = 0; k < 300; k = k + 1) begin
            if (k % 4 < 2)
                send_byte(8'h00);
            else
                send_byte(8'hFF);
        end
        #(BIT_NS * 20);
        chk.summary;                              // revisa la fase de saturación
        $display("   (todas las salidas validas deben ser 0xFF)");

        // PRUEBA 2: Reset Forzado durante transmisión activa
        $display("Test 2: Reset a mitad de camino");
        for (k = 0; k < 50; k = k + 1) begin
            send_byte(k[7:0]);
        end

        // Se empieza un byte nuevo: bit de inicio + 3 bits de datos...
        rx = 0; #(BIT_NS);
        for (k = 0; k < 3; k = k + 1) begin
            rx = 1; #(BIT_NS);
        end

        // ...y en ese instante llega el reset (la línea vuelve a reposo)
        rst = 1; rx = 1; #500;
        rst = 0; #100;
        #(BIT_NS * 3);                            // reposo antes de reanudar

        // PRUEBA 3: Verificación de recuperación post-reset
        $display("Test 3: Recuperacion despues del reset");
        for (k = 0; k < 260; k = k + 1) begin
            send_byte(k * 53 + 7);                // datos variados
        end

        #(BIT_NS * 40);                           // deja vaciar el transmisor
        chk.summary;
        $finish;
    end

endmodule
