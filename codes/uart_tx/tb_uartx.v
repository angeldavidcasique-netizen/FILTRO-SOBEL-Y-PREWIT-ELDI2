//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tb_uartx  (prueba unitaria del módulo uart_tx)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión del testbench, sincronización de los
//       pulsos con el reloj (antes había carreras) y adición de un decodificador
//       de la línea TX con verificaciones automáticas PASS/FAIL.
//
// CASOS CRÍTICOS EVALUADOS
//   1) Envío regular del píxel 0xAA (10101010): la línea debe sacar
//      START(0) + 8 bits (LSB primero) + STOP(1), con 'busy' en 1 durante la trama.
//   2) Píxel todo en 0 (0x00).
//   3) Píxel todo en 1 (0xFF).
//   4) o_valid mientras busy = 1: llega un segundo pulso en plena trama; el
//      módulo debe IGNORARLO y terminar la trama del primer píxel (0xA5).
//   5) Reset a mitad de la trama: la línea vuelve a 1, busy = 0 y la trama se
//      aborta (no sale un byte).
//
// NOTA: aquí se usa la temporización real (868 ciclos por bit = 8680 ns).
//==============================================================================
`timescale 1ns / 1ps

module tb_uartx;

localparam BIT_NS = 8680;          // 868 ciclos x 10 ns

reg   clk;
reg   rst;
reg [7:0] pixel;
reg o_valid;
wire busy;
wire pixel_out;

uart_tx UUT(
    .clk(clk),
    .rst(rst),
    .pixel(pixel),
    .o_valid(o_valid),
    .pixel_out(pixel_out),
    .busy(busy)
);

always #5 clk = ~clk;
integer test;
integer errors;
integer frames [1:5];             // tramas completas decodificadas por prueba
integer mi;
reg [7:0] rxb;
reg [7:0] exp_data;

// Pulso de o_valid de exactamente 1 ciclo, alineado con el reloj
task pulse(input [7:0] d);
    begin
        @(negedge clk);
        pixel = d; o_valid = 1;
        @(negedge clk);
        o_valid = 0;
    end
endtask

//------------------------------------------------------------------------------
// Decodificador de la línea TX (hace de "PC receptor")
//------------------------------------------------------------------------------
always begin : monitor
    @(negedge pixel_out);
    if (rst === 1'b0) begin
        #(BIT_NS/2);                       // centro del bit de inicio
        if (pixel_out === 1'b0) begin
            for (mi = 0; mi < 8; mi = mi + 1) begin
                #(BIT_NS);                 // centro de cada bit de datos
                rxb[mi] = pixel_out;
            end
            #(BIT_NS);                     // centro del bit de parada
            if (pixel_out !== 1'b1) begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: bit de parada incorrecto", test);
            end
            if (rxb !== exp_data) begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: se decodifico %h y se esperaba %h", test, rxb, exp_data);
            end else begin
                $display("[OK] prueba %0d: trama decodificada = %h", test, rxb);
            end
            frames[test] = frames[test] + 1;
        end
    end
end

// Un reset aborta la decodificación en curso
always @(posedge rst) disable monitor;

integer j;
initial begin
        $dumpfile("ondas_uartx.vcd");
        $dumpvars(0, tb_uartx);
    errors = 0; test = 0; exp_data = 0;
    for (j = 1; j <= 5; j = j + 1) frames[j] = 0;

    clk = 0;
    rst = 1;
    pixel = 0;
    o_valid = 0;

    #100 rst = 0;
    #100;

    /// PRIMER CASO ENVIO DE DATOS REGULAR
    test = 1; exp_data = 8'b10101010;
    pulse(8'b10101010);
    repeat (5) @(negedge clk);
    if (busy !== 1'b1) begin errors = errors + 1; $display("[ERROR] prueba 1: busy deberia ser 1 durante la trama"); end
    #(BIT_NS * 12);
    if (busy !== 1'b0) begin errors = errors + 1; $display("[ERROR] prueba 1: busy deberia volver a 0"); end

    /// SEGUNDO CASO TODOS EN 0
    test = 2; exp_data = 8'h00;
    pulse(8'h00);
    #(BIT_NS * 12);

     /// TERCER CASO TODOS EN 1
    test = 3; exp_data = 8'hFF;
    pulse(8'hFF);
    #(BIT_NS * 12);

    /// CUARTO CASO PROBAR o_valid MIENTRAS busy = 1
    test = 4; exp_data = 8'hA5;
    pulse(8'hA5);
    repeat (90) @(negedge clk);              // en plena trama
    pulse(8'h5A);                            // este segundo pulso debe ignorarse
    #(BIT_NS * 12);

    /// QUINTO CASO RESET A MITAD
    test = 5; exp_data = 8'hA5;
    pulse(8'hA5);
    #(BIT_NS * 3 + BIT_NS / 2);              // a mitad de la trama
    @(negedge clk); rst = 1;
    repeat (5) @(negedge clk);
    rst = 0;
    @(negedge clk);
    if (pixel_out !== 1'b1 || busy !== 1'b0) begin
        errors = errors + 1;
        $display("[ERROR] prueba 5: despues del reset la linea deberia estar en 1 y busy en 0");
    end
    #(BIT_NS * 12);                          // no debe aparecer ninguna trama nueva

    //--------------------------------------------------------------------------
    // Resumen
    //--------------------------------------------------------------------------
    for (j = 1; j <= 4; j = j + 1)
        if (frames[j] !== 1) begin
            errors = errors + 1;
            $display("[ERROR] prueba %0d: se esperaba 1 trama y hubo %0d", j, frames[j]);
        end
    if (frames[5] !== 0) begin
        errors = errors + 1;
        $display("[ERROR] prueba 5: la trama abortada no debia completarse (hubo %0d)", frames[5]);
    end
    $display("---------------- RESUMEN tb_uartx ----------------");
    $display(" Tramas por prueba: %0d %0d %0d %0d %0d (esperado 1 1 1 1 0)   Errores: %0d",
             frames[1], frames[2], frames[3], frames[4], frames[5], errors);
    if (errors == 0) $display(" RESULTADO: PASS");
    else             $display(" RESULTADO: FAIL");
    $finish;

end
endmodule
