//==============================================================================
// Proyecto : Procesador de imágenes 128x128 con detección de bordes
//            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
// Módulo   : uart_rx  (receptor UART, 115200 baudios, 8N1)
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
//   Convierte la señal serial 'rx' en un byte paralelo 'rx_data'. Entrega
//   'rx_ready' = 1 durante UN SOLO ciclo de reloj cuando el byte está listo.
//   FSM de 4 estados: IDLE(00) -> START(01) -> DATA(10) -> STOP(11).
//
// Correcciones respecto a la versión anterior
//   1) rx_ready ahora es un PULSO de 1 ciclo (antes, con bytes seguidos, se
//      quedaba en 1 durante todo el byte siguiente y window_gen desplazaba la
//      ventana en cada ciclo de reloj).
//   2) Cada bit de datos se muestrea en el CENTRO del bit (al final de una
//      cuenta completa de 868 ciclos contada desde el centro del bit START).
//      Antes se muestreaba justo en el FLANCO entre dos bits.
//   3) Sincronizador de 2 flip-flops en 'rx' (entrada asíncrona al reloj).
//   4) Cuenta exacta: 868 ciclos por bit (0..867) y 434 para medio bit.
//      Antes se contaba 0..868 = 869 ciclos.
//   5) CLKS_PER_BIT es parámetro: 868 en hardware real (100 MHz / 115200);
//      en simulación se baja (p. ej. 16) para que el testbench sea rápido.
//==============================================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 868            // 100 MHz / 115200 = 868.05
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_ready
);

    // Declaración de estados
    localparam IDLE  = 2'b00,
               START = 2'b01,
               DATA  = 2'b10,
               STOP  = 2'b11;

    localparam HALF_BIT = CLKS_PER_BIT / 2;   // 434

    // Registros internos
    reg [9:0] baud_cnt;
    reg [2:0] bit_idx;
    reg [1:0] state;
    reg       rx_s1, rx_s2;                   // sincronizador de 2 FF

    always @(posedge clk) begin
        if (rst) begin
            baud_cnt <= 0;
            bit_idx  <= 0;
            rx_ready <= 0;
            rx_data  <= 0;
            rx_s1    <= 1;
            rx_s2    <= 1;
            state    <= IDLE;
        end else begin
            // Sincronización de la entrada asíncrona
            rx_s1 <= rx;
            rx_s2 <= rx_s1;

            // Por defecto rx_ready vale 0: solo se pone en 1 un ciclo en STOP
            rx_ready <= 0;

            case (state)

                // Espera el flanco de bajada (bit de inicio)
                IDLE: begin
                    if (rx_s2 == 0) begin
                        state    <= START;
                        baud_cnt <= 0;
                    end
                end

                // Espera medio bit y confirma que sigue en 0 (centro del START)
                START: begin
                    if (baud_cnt == HALF_BIT - 1) begin
                        baud_cnt <= 0;
                        if (rx_s2 == 0) begin
                            state   <= DATA;
                            bit_idx <= 0;
                        end else begin
                            state   <= IDLE;      // falso arranque (ruido)
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // Cada 868 ciclos estamos en el CENTRO de un bit: se muestrea
                DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt         <= 0;
                        rx_data[bit_idx] <= rx_s2;
                        if (bit_idx == 7) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // Un bit después estamos en el centro del bit de parada:
                // el byte ya es válido y se avisa con un pulso
                STOP: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        rx_ready <= 1;
                        baud_cnt <= 0;
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule
