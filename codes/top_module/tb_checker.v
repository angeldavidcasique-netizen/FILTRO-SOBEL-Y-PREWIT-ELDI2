//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : tb_checker  (verificador automático para los testbench)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): propuso y escribió la estructura de este
//       verificador a partir de los testbench del autor, para que la
//       simulación diga PASS/FAIL sin tener que leer ondas a mano.
//
// ¿Qué hace?
//   Es un "árbitro" que NO forma parte del diseño (no se sintetiza):
//   1) push(): el testbench le avisa cada byte que envía por RX. Con esos
//      bytes calcula, en software, el resultado esperado de Sobel/Prewitt
//      (misma fórmula del hardware) para cada ventana 3x3 completa.
//   2) monitor: decodifica la línea TX como lo haría el PC (bit de inicio,
//      8 bits, parada) y compara cada byte recibido con el esperado.
//   3) summary(): imprime el resumen y PASS / FAIL.
//   Un reset reinicia las cuentas (igual que el hardware reinicia sus
//   contadores de fila/columna).
//==============================================================================
`timescale 1ns / 1ps

module tb_checker #(
    parameter CLKS_PER_BIT = 868
)(
    input wire rst,
    input wire tx
);

    localparam BIT_NS = CLKS_PER_BIT * 10;     // el reloj es de 10 ns
    localparam MAXN   = 20000;

    reg [7:0] in_mem  [0:MAXN-1];              // bytes enviados por RX
    reg [7:0] exp_mem [0:MAXN-1];              // salidas esperadas

    integer n_in, n_exp, n_out;                // contadores (fase actual)
    integer errors;                            // errores acumulados
    integer cnt_ff, cnt_00;                    // cuántas salidas 0xFF y 0x00
    integer mi;
    reg [7:0] rxb;

    initial begin
        n_in = 0; n_exp = 0; n_out = 0;
        errors = 0; cnt_ff = 0; cnt_00 = 0;
    end

    //--------------------------------------------------------------------------
    // push: registra un byte de entrada y calcula la salida esperada
    //--------------------------------------------------------------------------
    task push(input [7:0] data, input flt);
        integer r, c, gx, gy, mag;
        begin
            in_mem[n_in] = data;
            r = (n_in / 128) % 128;
            c = n_in % 128;
            if (r >= 2 && c >= 2) begin
                // Ventana: w33 = n_in, w32 = n_in-1, w31 = n_in-2,
                //          w23 = n_in-128, ..., w13 = n_in-256, ...
                if (flt == 1'b0) begin   // Sobel
                    gx = (in_mem[n_in-256] + 2*in_mem[n_in-128] + in_mem[n_in])
                       - (in_mem[n_in-258] + 2*in_mem[n_in-130] + in_mem[n_in-2]);
                    gy = (in_mem[n_in-2]   + 2*in_mem[n_in-1]   + in_mem[n_in])
                       - (in_mem[n_in-258] + 2*in_mem[n_in-257] + in_mem[n_in-256]);
                end else begin           // Prewitt
                    gx = (in_mem[n_in-256] + in_mem[n_in-128] + in_mem[n_in])
                       - (in_mem[n_in-258] + in_mem[n_in-130] + in_mem[n_in-2]);
                    gy = (in_mem[n_in-2]   + in_mem[n_in-1]   + in_mem[n_in])
                       - (in_mem[n_in-258] + in_mem[n_in-257] + in_mem[n_in-256]);
                end
                if (gx < 0) gx = -gx;
                if (gy < 0) gy = -gy;
                mag = gx + gy;
                if (mag > 255) mag = 255;          // saturación
                exp_mem[n_exp] = mag;
                n_exp = n_exp + 1;
            end
            n_in = n_in + 1;
        end
    endtask

    //--------------------------------------------------------------------------
    // monitor: decodifica la línea TX (UART 8N1) y compara con lo esperado
    //--------------------------------------------------------------------------
    always begin : monitor
        @(negedge tx);                          // flanco de bajada = bit de inicio
        if (rst === 1'b0) begin
            #(BIT_NS/2);                        // centro del bit de inicio
            if (tx === 1'b0) begin
                for (mi = 0; mi < 8; mi = mi + 1) begin
                    #(BIT_NS);                  // centro de cada bit de datos
                    rxb[mi] = tx;
                end
                #(BIT_NS);                      // centro del bit de parada
                if (tx !== 1'b1) begin
                    errors = errors + 1;
                    $display("[ERROR] t=%0t: bit de parada incorrecto en la salida %0d", $time, n_out);
                end
                if (n_out < n_exp) begin
                    if (rxb !== exp_mem[n_out]) begin
                        errors = errors + 1;
                        if (errors <= 10)
                            $display("[ERROR] t=%0t: salida %0d = %0d, esperado %0d",
                                     $time, n_out, rxb, exp_mem[n_out]);
                    end
                end else begin
                    errors = errors + 1;
                    $display("[ERROR] t=%0t: byte de salida %0d NO esperado (sobra)", $time, n_out);
                end
                if (rxb == 8'hFF)      cnt_ff = cnt_ff + 1;
                else if (rxb == 8'h00) cnt_00 = cnt_00 + 1;
                n_out = n_out + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Un reset aborta la decodificación en curso y reinicia las cuentas
    //--------------------------------------------------------------------------
    always @(posedge rst) begin
        disable monitor;
        if (n_exp != n_out)
            $display("[INFO] t=%0t: reset con %0d salidas en vuelo (descartadas)", $time, n_exp - n_out);
        n_in = 0; n_exp = 0; n_out = 0;
        cnt_ff = 0; cnt_00 = 0;
    end

    //--------------------------------------------------------------------------
    // summary: resumen final de la fase actual
    //--------------------------------------------------------------------------
    task summary;
        begin
            $display("---------------- RESUMEN DEL VERIFICADOR ----------------");
            $display(" Bytes enviados por RX        : %0d", n_in);
            $display(" Salidas esperadas (ventanas) : %0d", n_exp);
            $display(" Salidas recibidas por TX     : %0d", n_out);
            $display("   - con valor 0xFF (255)     : %0d", cnt_ff);
            $display("   - con valor 0x00           : %0d", cnt_00);
            $display(" Errores acumulados           : %0d", errors);
            if (errors == 0 && n_out == n_exp)
                $display(" RESULTADO: PASS");
            else
                $display(" RESULTADO: FAIL");
            $display("---------------------------------------------------------");
        end
    endtask

endmodule
