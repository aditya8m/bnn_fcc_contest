`timescale 1 ns / 10 ps
// Module: binarize_tb
// Notes:

// Module TB
module binarize_tb #(
    parameter int PIXEL_NUM         = 784,
    parameter int PIXEL_DATA_WIDTH  = 8,
    parameter int OUTPUT_DATA_WIDTH = 784
    parameter int NUM_TESTS         = 5000;
    parameter bit LOG_MONITOR       = 1'b0,
    parameter int MIN_CYCLES_BETWEEN_TESTS = 0,
    parameter int MAX_CYCLES_BETWEEN_TESTS = 12
);

logic clk, rst, en;
logic   [PIXEL_DATA_WIDTH-1:0] IN_DATA [PIXEL_NUM-1:0];
logic   [OUTPUT_DATA_WIDTH-1:0]  OUT_DATA;
int passed, failed;
               
// Instantiate DUT
binarize #(
    .PIXEL_NUM        (PIXEL_NUM),
    .PIXEL_DATA_WIDTH (PIXEL_DATA_WIDTH),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) DUT (
    .*
);

function logic OUT_DATA_model(logic [PIXEL_DATA_WIDTH-1:0] IN_DATA [PIXEL_NUM-1:0]);
    logic   [OUTPUT_DATA_WIDTH-1:0]  OUTPUT;
    for(int i=0; i<PIXEL_NUM; i++) begin
        if(IN_DATA[i] >= 8'h80) begin
            OUTPUT[i] <= 1'b1;
        end
        else begin
            OUTPUT[i] <= 1'b0;
        end
    end

    return OUTPUT;
endfunction

initial begin : generate_clock
    clk <= 1'b0;
    forever #5 clk <= ~clk;
end

covergroup cg @(posedge clk);
    IN_DATA_en_cv : coverpoint IN_DATA iff(en){
        foreach (IN_DATA[i]) begin
            cp: coverpoint IN_DATA[i] {
                bins all_vals[] = {[0:(PIXEL_DATA_WIDTH-1)]};
            }
        end
        option.at_least = 1;
    }

    IN_DATA_no_en_cv : coverpoint IN_DATA iff(!en){
        foreach (IN_DATA[i]) begin
            cp: coverpoint IN_DATA[i] {
                bins all_vals[] = {[0:(PIXEL_DATA_WIDTH-1)]};
            }
        end
        option.at_least = 1;
    }
endgroup

cg cg_inst;

mailbox scoreboard_IN_DATA_mailbox = new;
mailbox scoreboard_OUT_DATA_mailbox = new;
mailbox scoreboard_en_mailbox = new;
mailbox driver_mailbox = new;

class binarize_item;
    rand bit [PIXEL_DATA_WIDTH-1:0]   IN_DATA [PIXEL_NUM-1:0];
    rand bit en;
endclass

// Initialize the DUT.
initial begin : initialization
    cg_inst = new;
    $timeformat(-9, 0, " ns");

    // Reset the design.
    rst  <= 1'b1;
    IN_DATA <= '0; // Should set all elements in array to 0
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
end

initial begin : generator
    binarize_item test;

    for (int i = 0; i < NUM_TESTS; i++) begin
        test = new();
        assert (test.randomize())
        else $fatal(1, "Failed to randomize.");

        driver_mailbox.put(test);
    end
end

initial begin : en_monitor
    forever begin
        @(posedge clk iff (en == 1'b0 || en == 1'b1));
        scoreboard_IN_DATA_mailbox.put(IN_DATA);
        scoreboard_OUT_DATA_mailbox.put(OUT_DATA);
        scoreboard_en_mailbox.put(en);
        if (LOG_MONITOR) $display("[%0t] EN monitor detected completion with OUT_DATA=%0h", $realtime, OUT_DATA);
    end
end

initial begin : driver
    fib_item item;
    int unsigned cycle_delay;

    @(posedge clk iff !rst);

    forever begin
        driver_mailbox.get(item);

        // Drive the test onto the DUT.
        IN_DATA <= item.IN_DATA;
        en <= item.en;
        @(posedge clk);

        // Wait a random amount of time in between tests.
        cycle_delay = $urandom_range(MIN_CYCLES_BETWEEN_TESTS, MAX_CYCLES_BETWEEN_TESTS - 1);
        repeat (cycle_delay) @(posedge clk);
    end
end

// Verify the results.
initial begin : scoreboard
    logic [PIXEL_DATA_WIDTH-1:0] IN_DATA [PIXEL_NUM-1:0];
    logic [OUTPUT_DATA_WIDTH-1:0]  actual_OUT_DATA, prev_OUT_DATA, expected_output;
    logic en;

    // Reset values
    passed = 0;
    failed = 0;
    prev_OUT_DATA = '0;

    for (int i = 0; i < NUM_TESTS; i++) begin
        scoreboard_IN_DATA_mailbox.get(IN_DATA);
        scoreboard_actual_OUT_DATA_mailbox.get(actual_OUT_DATA);
        scoreboard_en_mailbox.get(en);
        if(en) begin
            for(int i = 0; i < PIXEL_NUM; i++) begin
                expected_output = OUT_DATA_model(IN_DATA);
                if(actual_OUT_DATA == expected_output) begin
                    passed++;
                end else begin
                    failed++;
                    $display("Test failed (time %0t). Conditions: EN = %0d, IN_DATA = %0d, DUT OUT_DATA = %0d, Expected OUT_DATA = %0d.", $time, en, IN_DATA, actual_OUT_DATA, expected_output);
                end
            end
        end else begin
            if(actual_OUT_DATA == prev_OUT_DATA) begin
                passed++;
            end else begin
                failed++;
                $display("Test failed (time %0t). Conditions: EN = %0d, IN_DATA = %0d, DUT OUT_DATA = %0d, Expected OUT_DATA = %0d.", $time, en, IN_DATA, actual_OUT_DATA, prev_OUT_DATA);
            end
        end
        prev_OUT_DATA = actual_OUT_DATA;
    end

    $display("Tests completed: %0d passed, %0d failed", passed, failed);
    disable generate_clock;
end