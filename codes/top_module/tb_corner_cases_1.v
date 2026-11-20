//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tb_corner_cases_1  (llenado de ventana, cambio de filtro, pausa)
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
//   1) Llenado inicial de la ventana (SOBEL): se envían 260 bytes de rampa.
//      Las 2 primeras filas (256 bytes) + 2 píxeles no generan salida; solo
//      deben aparecer 2 salidas (bytes 258 y 259).
//   2) Cambio de filtro "en caliente": el switch 'filter' alterna entre Sobel
//      y Prewitt cada 8 píxeles mientras llegan datos variados. Cada salida
//      debe corresponder al filtro activo en su píxel (el MUX está después
//      de los filtros, sin latencia extra).
//   3) Pausa en el puerto serial: RX queda en reposo (1) durante 30 tiempos
//      de bit y luego se reanuda la transmisión. La UART no debe generar
//      bytes falsos y la ventana no debe desplazarse durante la pausa.
//
// NOTA: CLKS_PER_BIT = 16 solo para simular rápido. El diseño real usa 868.
//==============================================================================
`timescale 1ns / 1ps

module tb_corner_cases_1;

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
        $dumpfile("onda_cc1.vcd");
        $dumpvars(1, tb_corner_cases_1);          // señales del testbench
        $dumpvars(0, UUT);                        // todo lo que hay dentro del diseño

        clk    = 0;
        rst    = 1;
        rx     = 1;
        filter = 0; #100;
        rst    = 0; #100;

        // PRUEBA 1: Llenado continuo inicial (Sobel)
        $display("Test 1: Llenado continuo inicial (Filter = 0)");
        for (k = 0; k < 260; k = k + 1) begin
            send_byte(k[7:0]);
        end

        // PRUEBA 2: Cambio de filtro en caliente (alterna cada 8 pixeles)
        $display("Test 2: Cambio dinamico de filtro Sobel/Prewitt");
        for (k = 0; k < 128; k = k + 1) begin
            filter = k[3];
            send_byte(k * 97 + 31);               // datos variados (pseudo-aleatorios)
        end

        // PRUEBA 3: Pausa en el puerto serial (Linea RX en reposo high)
        $display("Test 3: Pausa en el puerto UART");
        rx = 1; #(BIT_NS * 30);                   // congelamiento temporal
        for (k = 0; k < 64; k = k + 1) begin
            send_byte(8'hFF);
        end

        #(BIT_NS * 40);                           // deja vaciar el transmisor
        chk.summary;
        $finish;
    end

endmodule
