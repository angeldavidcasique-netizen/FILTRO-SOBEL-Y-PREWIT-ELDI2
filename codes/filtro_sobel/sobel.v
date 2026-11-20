//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : sobel  (filtro de detección de bordes Sobel)
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
//   Pipeline de 2 etapas (latencia de 2 ciclos desde i_valid hasta o_valid):
//     Etapa 1: Gx = (w13 + 2*w23 + w33) - (w11 + 2*w21 + w31)
//              Gy = (w31 + 2*w32 + w33) - (w11 + 2*w12 + w13)
//     Etapa 2: sobel_pix = |Gx| + |Gy|     (máximo 2040 -> cabe en 12 bits)
//   Aviso de ancho: las operaciones se evalúan en 32 bits sin signo y se
//   truncan a 12 bits al guardar; como el rango real es [-1020, 1020], el
//   patrón de 12 bits queda en complemento a dos y 'gx < 0' (bit 11) funciona.
//==============================================================================
module sobel(
input  wire       clk,
input  wire       rst,
input  wire       i_valid,   // Bandera que viene de window_gen
input wire  [7:0] w11, w12, w13,
input wire  [7:0] w21, w22, w23,
input wire  [7:0] w31, w32, w33,

output reg [11:0] sobel_pix,
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
        sobel_pix <= 0;
        end else begin
        d_valid <= i_valid;
        o_valid <= d_valid;

        if (i_valid == 1) begin

        // MATRIZ APLICADA
        gx <= (w13 + (w23 * 2) + w33) - (w11 + (w21 * 2) + w31);
        gy <=  (w31 + (w32 * 2) + w33) - (w11 + (w12 * 2) + w13);
 end

        // CALCULO DEL GRADIANTE
        if(d_valid == 1)begin
        sobel_pix <= ((gx < 0) ? - gx : gx) + ((gy < 0) ? - gy : gy);
        end
end
end
endmodule
