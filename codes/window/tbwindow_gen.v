//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tbwindow_gen  (prueba unitaria del módulo window_gen)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión del testbench, sincronización con el reloj,
//       reset entre pruebas y adición de verificaciones automáticas PASS/FAIL
//       (se compara cada ventana 3x3 contra los píxeles enviados).
//
// CASOS CRÍTICOS EVALUADOS
//   1) Rampa de 384 píxeles (3 filas): llenado de la ventana. No debe haber
//      o_valid en las 2 primeras filas ni en las columnas 0 y 1; solo cuando
//      row >= 2 y col >= 2 (126 pulsos). Cada ventana w11..w33 debe coincidir
//      con los píxeles enviados (w33 = actual, w23 = el de arriba, etc.).
//   2) Imagen constante 0xAA: todas las ventanas deben valer 0xAA.
//   3) Imagen negra (0x00): todas las ventanas deben valer 0x00.
//   4) Reset a mitad de la imagen: se envían 50 píxeles, se activa rst y se
//      envía una imagen nueva. Los contadores deben reiniciarse (nada de
//      o_valid hasta el píxel 258) y no deben usarse datos viejos.
//   Además: o_valid debe ser un pulso de 1 ciclo, y tras un reset las
//   salidas deben quedar en 0.
//==============================================================================
`timescale 1ns / 1ps

module tbwindow_gen;

localparam GAP = 900;              // ciclos entre píxeles (parecido a la UART)

reg   clk;
reg   rst;
reg i_valid;
reg [7:0] i_data;
wire o_valid;
    wire  [7:0] w11, w12, w13;
    wire  [7:0] w21, w22, w23;
    wire  [7:0] w31, w32, w33;



window_gen UUT (
    .clk(clk),
    .rst(rst),
    .i_valid(i_valid),
    .i_data(i_data),
    .o_valid(o_valid),
    .w11(w11),
    .w12(w12),
    .w13(w13),
    .w21(w21),
    .w22(w22),
    .w23(w23),
    .w31(w31),
    .w32(w32),
    .w33(w33)
);
always #5 clk = ~clk;
  integer k;
  integer test;

//------------------------------------------------------------------------------
// Verificación automática
//------------------------------------------------------------------------------
reg [7:0] mem [0:2047];            // píxeles enviados
integer n_in;                      // píxeles enviados en esta prueba
integer exp_cnt;                   // pulsos o_valid esperados
integer got_cnt;                   // pulsos o_valid recibidos
integer errors;
integer idx, r, c;
reg     prev_valid;

// Envía un píxel con i_valid de exactamente 1 ciclo y espera 'gap' ciclos
task send_pixel(input [7:0] d, input integer gap);
    integer rr, cc;
    begin
        @(negedge clk);
        i_data = d; i_valid = 1;
        mem[n_in] = d;
        rr = (n_in / 128) % 128;
        cc = n_in % 128;
        if (rr >= 2 && cc >= 2) exp_cnt = exp_cnt + 1;
        n_in = n_in + 1;
        @(negedge clk);
        i_valid = 0;
        repeat (gap) @(negedge clk);
    end
endtask

// Reset entre pruebas: reinicia el DUT y las cuentas del verificador
task do_reset;
    begin
        @(negedge clk); rst = 1;
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);
        if (o_valid !== 1'b0 ||
            w11 !== 8'h00 || w12 !== 8'h00 || w13 !== 8'h00 ||
            w21 !== 8'h00 || w22 !== 8'h00 || w23 !== 8'h00 ||
            w31 !== 8'h00 || w32 !== 8'h00 || w33 !== 8'h00) begin
            errors = errors + 1;
            $display("[ERROR] despues del reset las salidas deberian ser 0");
        end
        n_in = 0; exp_cnt = 0; got_cnt = 0;
    end
endtask

task fin_prueba(input integer num);
    begin
        repeat (5) @(negedge clk);
        if (got_cnt !== exp_cnt) begin
            errors = errors + 1;
            $display("[ERROR] prueba %0d: pulsos o_valid = %0d, esperados %0d", num, got_cnt, exp_cnt);
        end else begin
            $display("[OK] prueba %0d: %0d ventanas validas (esperadas %0d)", num, got_cnt, exp_cnt);
        end
    end
endtask

// Revisa cada ventana en cuanto aparece o_valid
always @(posedge clk) begin
    if (o_valid === 1'b1) begin
        got_cnt = got_cnt + 1;
        if (prev_valid) begin
            errors = errors + 1;
            $display("[ERROR] t=%0t: o_valid dura mas de 1 ciclo", $time);
        end
        idx = n_in - 1;                    // píxel que acaba de entrar
        r = (idx / 128) % 128;
        c = idx % 128;
        if (!(r >= 2 && c >= 2)) begin
            errors = errors + 1;
            $display("[ERROR] t=%0t: o_valid antes de tener ventana completa (idx=%0d)", $time, idx);
        end else if (w33 !== mem[idx]     || w32 !== mem[idx-1]   || w31 !== mem[idx-2]   ||
                     w23 !== mem[idx-128] || w22 !== mem[idx-129] || w21 !== mem[idx-130] ||
                     w13 !== mem[idx-256] || w12 !== mem[idx-257] || w11 !== mem[idx-258]) begin
            errors = errors + 1;
            if (errors <= 10)
                $display("[ERROR] t=%0t: ventana incorrecta en idx=%0d", $time, idx);
        end
    end
    prev_valid = (o_valid === 1'b1);
end

initial begin
        $dumpfile("ondas_window.vcd");
        $dumpvars(0, tbwindow_gen);

    errors = 0; n_in = 0; exp_cnt = 0; got_cnt = 0; prev_valid = 0;
    clk = 0;
    rst  = 1;
    i_valid = 0;
    i_data = 0;
    #100 rst = 0;
    #100;

    test = 1;
    // prueba: rampa de 3 filas (llenado de la ventana)
    for(k=0; k<384 ; k=k+1)begin
        send_pixel(k[7:0], GAP);
    end
    fin_prueba(1);
    do_reset;

    //// SEGUNDO CASO PRUEBA CONSTANTE 0xAA
     test = 2;
    for(k=0; k<384 ; k=k+1)begin
        send_pixel(8'hAA, GAP);
    end
    fin_prueba(2);
    do_reset;

    /// TERCER CASO PRUEBA DE NEGRO

     test = 3;
    for(k=0; k<384 ; k=k+1)begin
        send_pixel(8'h00, GAP);
    end
    fin_prueba(3);
    do_reset;

    /// CUARTO CASO rst A MITAD

     test = 4;
    for(k=0; k<50 ; k=k+1)begin
        send_pixel(8'hAF, 10);          // llegan rápido y la imagen queda a medias
    end
    do_reset;                           // reset a mitad de la imagen
    for(k=0; k<384 ; k=k+1)begin
        send_pixel(k * 7 + 3, GAP);     // imagen nueva distinta (detecta datos viejos)
    end
    fin_prueba(4);

    //--------------------------------------------------------------------------
    // Resumen
    //--------------------------------------------------------------------------
    $display("---------------- RESUMEN tbwindow_gen ----------------");
    $display(" Errores: %0d", errors);
    if (errors == 0) $display(" RESULTADO: PASS");
    else             $display(" RESULTADO: FAIL");
    $finish;
end
endmodule
