`timescale 1 ns / 10 ps
// Module: binarize_tb
// Notes:

module binarize_tb #(
    parameter int PIXEL_NUM = 784,
    parameter int PIXEL_DATA_WIDTH = 8,
    parameter int OUTPUT_DATA_WIDTH = 784
);

// Instantiate DUT
binarize #(
    .PIXEL_NUM        (PIXEL_NUM),
    .PIXEL_DATA_WIDTH (PIXEL_DATA_WIDTH),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) DUT (
    .*
);