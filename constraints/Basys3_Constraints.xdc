## ============================================================================
## Proyecto : Procesador de imágenes 128x128 con detección de bordes
##            (Sobel / Prewitt) en FPGA Basys 3 (xc7a35tcpg236-1)
## Archivo  : Basys3_Constraints.xdc  (asignación de pines)
## Autor    : Ángel Casique
## ============================================================================

## Reloj de 100 MHz
set_property PACKAGE_PIN W5 [get_ports clk]
	set_property IOSTANDARD LVCMOS33 [get_ports clk]
	create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Reset: botón central (btnC)
set_property PACKAGE_PIN U18 [get_ports rst]
	set_property IOSTANDARD LVCMOS33 [get_ports rst]

## Selección de filtro: SW0 (0 = Sobel, 1 = Prewitt)
set_property PACKAGE_PIN V17 [get_ports filter]
	set_property IOSTANDARD LVCMOS33 [get_ports filter]

## USB-UART: PC -> FPGA
set_property PACKAGE_PIN B18 [get_ports rx]
	set_property IOSTANDARD LVCMOS33 [get_ports rx]

## USB-UART: FPGA -> PC
set_property PACKAGE_PIN A18 [get_ports tx]
	set_property IOSTANDARD LVCMOS33 [get_ports tx]
