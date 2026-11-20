//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tb_uartrx  (prueba unitaria del módulo uart_rx)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión del testbench, corrección de la carrera
//       del reset inicial y adición de verificaciones automáticas PASS/FAIL.
//
// CASOS CRÍTICOS EVALUADOS
//   1) Byte regular 0xAA (10101010): rx_data = 0xAA y rx_ready = pulso de 1 ciclo.
//   2) Falso bit de inicio (glitch de 400 ciclos, menos de medio bit): la FSM
//      debe volver a IDLE sin generar rx_ready.
//   3) Byte con todos los datos en 0 (0x00).
//   4) Byte con todos los datos en 1 (0xFF).
//   5) Reset forzado a mitad de una recepción: la FSM vuelve a IDLE, rx_data
//      se limpia a 0x00 y NO se genera rx_ready.
//
// NOTA: aquí se usa la temporización real (868 ciclos por bit = 8680 ns).
//==============================================================================
`timescale 1ns / 1ps

module tb_uartrx;

reg   clk;
reg   rst;
reg   rx;
wire [7:0]  rx_data;
wire   rx_ready;

uart_rx UUT(
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .rx_data(rx_data),
    .rx_ready(rx_ready)
);
always #5 clk = ~clk;
integer test;

//------------------------------------------------------------------------------
// Verificación automática
//------------------------------------------------------------------------------
integer errors;
integer n_ready;
reg     ready_prev;

always @(posedge clk) begin
    if (rx_ready === 1'b1) begin
        n_ready = n_ready + 1;
        if (ready_prev) begin
            errors = errors + 1;
            $display("[ERROR] t=%0t: rx_ready dura mas de 1 ciclo", $time);
        end
        case (test)
            1: if (rx_data !== 8'hAA) begin errors = errors + 1; $display("[ERROR] prueba 1: rx_data=%h, esperado AA", rx_data); end
               else $display("[OK] prueba 1: rx_data = %h", rx_data);
            3: if (rx_data !== 8'h00) begin errors = errors + 1; $display("[ERROR] prueba 3: rx_data=%h, esperado 00", rx_data); end
               else $display("[OK] prueba 3: rx_data = %h", rx_data);
            4: if (rx_data !== 8'hFF) begin errors = errors + 1; $display("[ERROR] prueba 4: rx_data=%h, esperado FF", rx_data); end
               else $display("[OK] prueba 4: rx_data = %h", rx_data);
            default: begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: rx_ready NO debia activarse", test);
            end
        endcase
    end
    ready_prev = (rx_ready === 1'b1);
end

initial begin
        $dumpfile("ondas_uartrx.vcd");
        $dumpvars(0, tb_uartrx);

    errors = 0; n_ready = 0; ready_prev = 0; test = 0;
    clk = 0;
    rx  = 1;
    rst = 1;
    #100 rst = 0;                  // el reset dura varios ciclos (sin carrera con el reloj)
    #100;

    // PRUEBA 1: byte regular 0xAA
    // bit de inicio
    rx = 0;#8680;
    test = 1;
   // datos enviados (LSB primero: 0,1,0,1,0,1,0,1 = 0xAA)
    rx = 0;#8680;
    rx = 1;#8680;
    rx = 0;#8680;
    rx = 1;#8680;
    rx = 0;#8680;
    rx = 1;#8680;
    rx = 0;#8680;
    rx = 1;#8680;

    /// bit de cierre
    rx = 1;#8680;

    //// SEGUNDO CASO falso bit de inicio

    // bit de inicio
    test =2;
    rx = 0 ;#4000;                 // 400 ciclos < medio bit (434): es un glitch
    rx = 1 ;#8680;
    /// glitch de error

    //// TERCER CASO TODOS 0

    // bit de inicio
    rx = 0;#8680;
    test = 3;
   // datos enviados
    rx = 0;#8680;
    rx = 0;#8680;
    rx = 0;#8680;
    rx = 0;#8680;
    rx = 0;#8680;
    rx = 0;#8680;
    rx = 0;#8680;
    rx = 0;#8680;

    /// bit de cierre
    rx = 1;#8680;

    //// CUARTO CASO TODOS 1

    // bit de inicio
    rx = 0;#8680;
    test = 4;

   // datos enviados
    rx = 1;#8680;
    rx = 1;#8680;
    rx = 1;#8680;
    rx = 1;#8680;
    rx = 1;#8680;
    rx = 1;#8680;
    rx = 1;#8680;
    rx = 1;#8680;

    /// bit de cierre
    rx = 1;#8680;

    /// QUINTO CASO RESET FORZADO

      // bit de inicio
    rx = 0;#8680;
    test = 5;

   // datos enviados (solo 3 de los 8 bits)
    rx = 1;#8680;
    rx = 0;#8680;
    rx = 1;#8680;
    rst =1;#30; rst =0;

    /// volviendo a IDLE (la línea queda en reposo y no debe salir nada)
    rx = 1;#(8680 * 12);

    //--------------------------------------------------------------------------
    // Resumen
    //--------------------------------------------------------------------------
    if (rx_data !== 8'h00) begin
        errors = errors + 1;
        $display("[ERROR] despues del reset rx_data deberia ser 00 y es %h", rx_data);
    end
    if (n_ready !== 3) begin
        errors = errors + 1;
        $display("[ERROR] se esperaban 3 pulsos de rx_ready y hubo %0d", n_ready);
    end
    $display("---------------- RESUMEN tb_uartrx ----------------");
    $display(" Pulsos de rx_ready: %0d (esperados 3)   Errores: %0d", n_ready, errors);
    if (errors == 0) $display(" RESULTADO: PASS");
    else             $display(" RESULTADO: FAIL");
    $finish;

end
endmodule
