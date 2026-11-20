//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : prewit  (filtro de detección de bordes Prewitt)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión final del código; en este módulo no fue
//       necesario cambiar la lógica, solo se agregaron comentarios.
//
// Descripción
//   Igual que Sobel pero con coeficientes 1 (sin el factor 2):
//     Etapa 1: Gx = (w13 + w23 + w33) - (w11 + w21 + w31)
//              Gy = (w31 + w32 + w33) - (w11 + w12 + w13)
//     Etapa 2: prewit_pix = |Gx| + |Gy|    (máximo 1530 -> cabe en 11 bits)
//   Latencia de 2 ciclos desde i_valid hasta o_valid (igual que Sobel, por
//   eso el MUX del top puede conmutar entre ambos sin desalinear la bandera).
//==============================================================================
module prewit(
input  wire       clk,
input  wire       rst,
input  wire       i_valid,   // Bandera que viene de window_gen
input wire  [7:0] w11, w12, w13,
input wire  [7:0] w21, w22, w23,
input wire  [7:0] w31, w32, w33,

output reg [10:0] prewit_pix,
output reg o_valid
);

reg signed [11:0] gx;
reg signed [11:0] gy;
reg d_valid;

always @(posedge clk) begin
    if (rst) begin
        gx <=0;
        gy <=0;
        o_valid <= 0;
        d_valid <=0;
        prewit_pix <= 0;
        end else begin
        d_valid <= i_valid;
        o_valid <= d_valid;

        if (i_valid == 1) begin

        // MATRIZ APLICADA
        gx <= (w13 + w23 + w33) - (w11 + w21 + w31);
        gy <=  (w31 + w32  + w33) - (w11 + w12+ w13);
 end

        // CALCULO DEL GRADIANTE
        if(d_valid == 1)begin
        prewit_pix <= ((gx < 0) ? - gx : gx) + ((gy < 0) ? - gy : gy);
        end
end
end
endmodule
