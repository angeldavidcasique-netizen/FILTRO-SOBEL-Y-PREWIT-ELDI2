//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : uart_tx  (transmisor UART, 115200 baudios, 8N1)
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
//   Cuando llega un pulso 'o_valid' toma el byte 'pixel' y lo serializa por
//   'pixel_out' (pin tx): 1 bit de inicio (0), 8 bits de datos (LSB primero)
//   y 1 bit de parada (1). 'busy' vale 1 mientras transmite.
//   FSM de 4 estados: IDLE(00) -> START(01) -> DATA(10) -> STOP(11).
//
// Correcciones respecto a la versión anterior
//   1) Cada bit dura exactamente 868 ciclos (cuenta 0..867). Antes duraba 869
//      y el transmisor quedaba más lento que la entrada: con 16384 píxeles se
//      iba atrasando y perdía bytes.
//   2) Los cambios en 'pixel_out' se hacen en el mismo ciclo en que cambia de
//      estado (antes había un ciclo de desfase entre contador y salida).
//   3) El bit de parada se acorta a 3/4 de bit (STOP_CLKS). Es una práctica
//      común: el receptor del PC muestrea el stop en la mitad del bit, así que
//      sigue siendo válido, y a cambio el TX SIEMPRE termina antes de que
//      llegue el siguiente píxel (nunca se pierde un byte por ir atrasado).
//   4) CLKS_PER_BIT es parámetro (868 en hardware real, 16 en simulación).
//==============================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 868            // 100 MHz / 115200 = 868.05
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       o_valid,    // BANDERA DEL FILTRO (pulso de 1 ciclo)
    input  wire [7:0] pixel,
    output reg        pixel_out,
    output reg        busy
);

    // Declaración de estados
    localparam IDLE  = 2'b00,
               START = 2'b01,
               DATA  = 2'b10,
               STOP  = 2'b11;

    localparam STOP_CLKS = (CLKS_PER_BIT * 3) / 4;   // 651 ciclos

    reg [9:0] baud_cnt;
    reg [7:0] tx_data;
    reg [2:0] bit_idx;
    reg [1:0] state;

    always @(posedge clk) begin
        if (rst) begin
            tx_data   <= 0;
            bit_idx   <= 0;
            baud_cnt  <= 0;
            busy      <= 0;
            pixel_out <= 1;
            state     <= IDLE;
        end else begin
            case (state)

                // Línea en reposo (1). Al llegar o_valid se guarda el píxel y
                // se baja la línea (bit de inicio)
                IDLE: begin
                    pixel_out <= 1;
                    if (o_valid == 1) begin
                        tx_data   <= pixel;
                        busy      <= 1;
                        baud_cnt  <= 0;
                        bit_idx   <= 0;
                        pixel_out <= 0;
                        state     <= START;
                    end
                end

                // Mantiene el 0 durante 868 ciclos y luego saca el bit 0
                START: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt  <= 0;
                        bit_idx   <= 0;
                        pixel_out <= tx_data[0];
                        state     <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // Cada 868 ciclos saca el siguiente bit; tras el bit 7 sube
                // la línea (bit de parada)
                DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        if (bit_idx == 7) begin
                            bit_idx   <= 0;
                            pixel_out <= 1;
                            state     <= STOP;
                        end else begin
                            bit_idx   <= bit_idx + 1;
                            pixel_out <= tx_data[bit_idx + 1];
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // Bit de parada (acortado a 3/4 de bit) y regreso a IDLE
                STOP: begin
                    pixel_out <= 1;
                    if (baud_cnt == STOP_CLKS - 1) begin
                        baud_cnt <= 0;
                        busy     <= 0;
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule
