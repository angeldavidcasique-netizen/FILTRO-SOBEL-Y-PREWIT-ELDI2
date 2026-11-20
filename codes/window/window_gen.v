//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : window_gen  (generador de ventana 3x3 con 2 line buffers)
// Autor    : Ángel Casique
//
// DECLARACIÓN DE USO DE IA
//   Este código fue diseñado, escrito e instanciado por el autor (Ángel
//   Casique). La IA se usó únicamente como apoyo de corrección:
//     - Gemini (Google): fue revisando el código que el autor iba escribiendo
//       y le sugería correcciones (dinámica de "toma y dame").
//     - Claude (Anthropic): revisión final del código y corrección de errores
//       sobre el trabajo del autor (ver "Correcciones" más abajo).
//
// Descripción
//   Cada vez que llega un píxel (i_valid = 1) se desplaza la ventana 3x3:
//        w11 w12 w13      <- fila r-2   (sale de line_buf_2)
//        w21 w22 w23      <- fila r-1   (sale de line_buf_1)
//        w31 w32 w33      <- fila r     (píxel actual: w33 = i_data)
//   o_valid se activa SOLO cuando la ventana ya está completa: hay al menos
//   2 filas y 2 columnas recibidas (row_cnt >= 2 y col_cnt >= 2).
//   Resultado: 126 x 126 = 15876 ventanas válidas por imagen (el centro de
//   cada ventana recorre el interior de la imagen, filas/columnas 1..126).
//
// Correcciones respecto a la versión anterior
//   1) o_valid ahora es un PULSO de 1 ciclo por ventana. Antes solo se
//      actualizaba cuando llegaba un píxel, así que se quedaba en 1 durante
//      ~868*10 ciclos y los filtros/UART_TX procesaban la misma ventana
//      muchas veces.
//   2) Se quitó el bucle for de reset sobre las memorias. Una RAM no tiene
//      reset: Vivado lo implementaba con 2048 flip-flops y multiplexores
//      enormes. En su lugar se inicializan en un bloque 'initial' (Vivado lo
//      acepta como valor inicial de la RAM y en simulación elimina las X).
//==============================================================================
module window_gen (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] i_data,
    input  wire       i_valid,   // Bandera que viene de rx_ready
    output reg  [7:0] w11, w12, w13,
    output reg  [7:0] w21, w22, w23,
    output reg  [7:0] w31, w32, w33,
    output reg        o_valid
);

// MEMORIAS INTERNAS (una fila de 128 píxeles cada una)
reg [7:0] line_buf_1 [0:127];
reg [7:0] line_buf_2 [0:127];
reg [6:0] col_cnt;
reg [6:0] row_cnt;
integer k;

// Valor inicial de las memorias (sin esto aparecen X en la simulación)
initial begin
    for (k = 0; k < 128; k = k + 1) begin
        line_buf_1[k] = 8'd0;
        line_buf_2[k] = 8'd0;
    end
end

always @(posedge clk) begin
    if (rst) begin
        col_cnt <= 0;
        row_cnt <= 0;
        o_valid <= 0;

        w11 <= 0; w12 <= 0; w13 <= 0;
        w21 <= 0; w22 <= 0; w23 <= 0;
        w31 <= 0; w32 <= 0; w33 <= 0;
    end else begin
        // Por defecto o_valid = 0: solo vale 1 un ciclo cuando la ventana está completa
        o_valid <= 0;

        if (i_valid == 1) begin

            // Lógica de contadores espaciales
            if (col_cnt == 127) begin
                col_cnt <= 0;
                row_cnt <= row_cnt + 1;
            end else begin
                col_cnt <= col_cnt + 1;
            end

            // Line buffers: line_buf_1 guarda la fila anterior,
            // line_buf_2 guarda la fila de hace dos
            line_buf_1 [col_cnt] <= i_data;
            line_buf_2 [col_cnt] <= line_buf_1 [col_cnt];

            /// MOVIMIENTO DE LA VENTANA
            w33 <= i_data;
            w32 <= w33;
            w31 <= w32;

            w23 <= line_buf_1 [col_cnt];
            w22 <= w23;
            w21 <= w22;

            w13 <= line_buf_2 [col_cnt];
            w12 <= w13;
            w11 <= w12;

            // Ventana completa: ya hay 2 filas y 2 columnas
            if (row_cnt >= 2 && col_cnt >= 2) begin
                o_valid <= 1;
            end
        end
    end
end
endmodule
