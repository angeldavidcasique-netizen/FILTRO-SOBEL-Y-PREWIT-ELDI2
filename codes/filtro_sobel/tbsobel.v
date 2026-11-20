//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Testbench: tbsobel  (prueba unitaria del módulo sobel)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión del testbench, sincronización con el reloj
//       y adición de verificaciones automáticas PASS/FAIL con resultados
//       esperados calculados a mano.
//
// CASOS CRÍTICOS EVALUADOS (el módulo NO satura: la saturación a 255 se hace
// en top_module, por eso aquí se esperan valores mayores que 255)
//   1) Columna vertical negra/blanca (izq. 0, der. 255): |Gx| = 1020, Gy = 0.
//   2) i_valid = 0: aunque cambie la ventana, NO debe haber salida.
//   3) Línea horizontal negra/blanca (arriba 0, abajo 255): |Gy| = 1020.
//   4) Valor absoluto: columna izquierda en 100 y derecha en 0 -> Gx = -400,
//      la salida debe ser +400.
//   5) Zona plana (todo 128): gradiente 0.
//   6) Píxel aislado en la esquina w33 = 255: |Gx| + |Gy| = 255 + 255 = 510.
//   7) Signos distintos: w13 = 255 -> Gx = +255 y Gy = -255; salida 510.
//   8) Máximo práctico: Gx = 1020 y Gy = 510 -> 1530.
//   9) Reset en plena tubería: la salida se limpia y no sale o_valid.
//   Además: latencia de exactamente 2 ciclos entre i_valid y o_valid.
//==============================================================================
`timescale 1ns / 1ps

module tbsobel;

reg   clk;
reg   rst;
reg i_valid;
reg  [7:0] w11, w12, w13;
reg  [7:0] w21, w22, w23;
reg  [7:0] w31, w32, w33;
wire o_valid;
wire [11:0] sobel_pix;

sobel UUT (
    .clk(clk),
    .rst(rst),
    .i_valid(i_valid),
    .sobel_pix(sobel_pix),
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
integer test;

//------------------------------------------------------------------------------
// Monitor: cuenta salidas y mide la latencia i_valid -> o_valid
//------------------------------------------------------------------------------
integer errors, cyc, t_in, lat, got_cnt, got_val;

always @(posedge clk) begin
    if (i_valid === 1'b1) t_in = cyc;
    if (o_valid === 1'b1) begin
        got_cnt = got_cnt + 1;
        got_val = sobel_pix;
        lat     = cyc - t_in;
    end
    cyc = cyc + 1;
end

// Presenta la ventana actual con i_valid = v durante 1 ciclo y revisa el resultado
task run_case(input v, input integer expv);
    begin
        got_cnt = 0;
        @(negedge clk); i_valid = v;
        @(negedge clk); i_valid = 0;
        repeat (6) @(negedge clk);
        if (v) begin
            if (got_cnt !== 1) begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: pulsos o_valid = %0d (esperado 1)", test, got_cnt);
            end else if (got_val !== expv) begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: sobel_pix = %0d, esperado %0d", test, got_val, expv);
            end else if (lat !== 2) begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: latencia = %0d ciclos (esperado 2)", test, lat);
            end else begin
                $display("[OK] prueba %0d: sobel_pix = %0d (latencia %0d)", test, got_val, lat);
            end
        end else begin
            if (got_cnt !== 0) begin
                errors = errors + 1;
                $display("[ERROR] prueba %0d: con i_valid = 0 no debia haber salida", test);
            end else begin
                $display("[OK] prueba %0d: sin i_valid no hay salida", test);
            end
        end
    end
endtask

initial begin
        $dumpfile("ondas_sobel.vcd");
        $dumpvars(0, tbsobel);

    errors = 0; cyc = 0; t_in = 0; lat = 0; got_cnt = 0; got_val = 0; test = 0;
    clk = 0;
    rst  = 1;
    i_valid = 0;
    w11 = 0;
    w12 = 0;
    w13 = 0;
    w21 = 0;
    w22 = 0;
    w23 = 0;
    w31 = 0;
    w32 = 0;
    w33 = 0;

    #100 rst = 0;
    #100;

    //PRUEBA 1: FILTRO COLUMNA NEGRA Y BLANCA VERTICAL
    test = 1;
    w11 = 0; w12 = 0; w13 = 255;
    w21 = 0; w22 = 0; w23 = 255;
    w31 = 0; w32 = 0; w33 = 255;
    run_case(1, 1020);

    /// PRUEBA 2: i_valid = 0 (la ventana cambia pero no debe procesarse)
    test = 2;
    w11 = 10; w12 = 20; w13 = 250;
    w21 = 30; w22 = 40; w23 = 5;
    w31 = 60; w32 = 70; w33 = 80;
    run_case(0, 0);

    //PRUEBA 3: FILTRO LINEA NEGRA Y BLANCA HORIZONTAL
    test = 3;
    w11 = 0; w12 = 0; w13 = 0;
    w21 = 0; w22 = 0; w23 = 0;
    w31 = 255; w32 = 255; w33 = 255;
    run_case(1, 1020);

    //PRUEBA 4: DEL VALOR ABSOLUTO (Gx negativo)
    test = 4;
    w11 = 100; w12 = 0; w13 = 0;
    w21 = 100; w22 = 0; w23 = 0;
    w31 = 100; w32 = 0; w33 = 0;
    run_case(1, 400);

    //PRUEBA 5: ZONA PLANA
    test = 5;
    w11 = 128; w12 = 128; w13 = 128;
    w21 = 128; w22 = 128; w23 = 128;
    w31 = 128; w32 = 128; w33 = 128;
    run_case(1, 0);

    //PRUEBA 6: PIXEL AISLADO EN LA ESQUINA w33
    test = 6;
    w11 = 0; w12 = 0; w13 = 0;
    w21 = 0; w22 = 0; w23 = 0;
    w31 = 0; w32 = 0; w33 = 255;
    run_case(1, 510);

    //PRUEBA 7: SIGNOS DISTINTOS (Gx = +255, Gy = -255)
    test = 7;
    w11 = 0; w12 = 0; w13 = 255;
    w21 = 0; w22 = 0; w23 = 0;
    w31 = 0; w32 = 0; w33 = 0;
    run_case(1, 510);

    //PRUEBA 8: MAXIMO PRACTICO (Gx = 1020, Gy = 510)
    test = 8;
    w11 = 0; w12 = 0;   w13 = 255;
    w21 = 0; w22 = 0;   w23 = 255;
    w31 = 0; w32 = 255; w33 = 255;
    run_case(1, 1530);

    //PRUEBA 9: RESET EN PLENA TUBERIA
    test = 9;
    got_cnt = 0;
    w11 = 0; w12 = 0; w13 = 255;
    w21 = 0; w22 = 0; w23 = 255;
    w31 = 0; w32 = 0; w33 = 255;
    @(negedge clk); i_valid = 1;
    @(negedge clk); i_valid = 0; rst = 1;       // el reset llega un ciclo despues
    @(negedge clk); rst = 0;
    repeat (6) @(negedge clk);
    if (got_cnt !== 0 || sobel_pix !== 12'd0) begin
        errors = errors + 1;
        $display("[ERROR] prueba 9: despues del reset no debia haber salida (pulsos=%0d, pix=%0d)", got_cnt, sobel_pix);
    end else begin
        $display("[OK] prueba 9: el reset limpio la tuberia");
    end

    //--------------------------------------------------------------------------
    // Resumen
    //--------------------------------------------------------------------------
    $display("---------------- RESUMEN tbsobel ----------------");
    $display(" Errores: %0d", errors);
    if (errors == 0) $display(" RESULTADO: PASS");
    else             $display(" RESULTADO: FAIL");
    $finish;
end
endmodule
