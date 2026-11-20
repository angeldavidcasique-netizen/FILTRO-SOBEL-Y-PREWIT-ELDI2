//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : top_module  (conexión de todos los bloques)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión final del código; se agregó el parámetro
//       CLKS_PER_BIT para poder simular rápido (ver "Correcciones").
//
// Flujo de datos
//   rx -> uart_rx -> window_gen -> sobel / prewit -> MUX(filter) -> saturación
//      -> uart_tx -> tx
//   filter = 0 -> Sobel      filter = 1 -> Prewitt   (SW0 de la Basys 3)
//
// Correcciones respecto a la versión anterior
//   - Parámetro CLKS_PER_BIT (868 por defecto = hardware real). Los testbench
//     lo bajan a 16 para que la imagen completa se simule en segundos.
//   - Importante: por cada imagen de 128x128 entran 16384 bytes pero salen
//     15876 (126x126): los píxeles del borde de la imagen no tienen ventana
//     3x3 completa. El script de Python debe leer 15876 bytes y rellenar el
//     marco de 1 píxel con ceros (np.pad) para volver a 128x128.
//==============================================================================
module top_module #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire  clk,
    input  wire  rst,
    input  wire   rx,
    output wire   tx,
    input  wire   filter

);
//CABLE UARTX A window_gen
wire  [7:0] rx_data;
wire rx_ready;

// CABLES DE window_gen
wire [7:0] w11, w12, w13;
wire  [7:0] w21, w22, w23;
wire  [7:0] w31, w32, w33;
wire win_valid;
wire busy;

// CABLES DE SALIDA
wire [11:0] sobel_pix;
wire [10:0] prewit_pix;
wire sobel_valid;
wire prewit_valid;


uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) U1 (
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .rx_data(rx_data),
    .rx_ready(rx_ready)
);
window_gen U2 (
    .clk(clk),
    .rst(rst),
    .i_data(rx_data),
    .i_valid(rx_ready),
    .o_valid(win_valid),
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
sobel U3(
    .clk(clk),
    .rst(rst),
    .i_valid(win_valid),
    .sobel_pix(sobel_pix),
    .o_valid(sobel_valid),
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
prewit U4(
    .clk(clk),
    .rst(rst),
    .i_valid(win_valid),
    .prewit_pix(prewit_pix),
    .o_valid(prewit_valid),
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

//Selección del FILTRO
wire [11:0] pix_12b   = (filter == 1'b0) ? sobel_pix : {1'b0, prewit_pix};
wire        pix_valid = (filter == 1'b0) ? sobel_valid : prewit_valid;

//Saturación 8bits
wire [7:0] pix_8b = (pix_12b > 12'd255) ? 8'hFF : pix_12b[7:0];



uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) U5 (
    .clk(clk),
    .rst(rst),
    .pixel(pix_8b),
    .o_valid(pix_valid),
    .pixel_out(tx),
    .busy(busy)

);
endmodule
