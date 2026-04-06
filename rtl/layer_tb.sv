`timescale 1ns/1ps

module tb_bnn_layer;

    // Parameters
    localparam INPUT_WIDTH       = 64;
    localparam NEURON_PROCESSORS = 4;
    localparam NEURONS           = 16;
    localparam INPUT_NEURONS     = 64;
    localparam CONFIG_WIDTH      = 64; // change to 32 or 128 to test
    localparam WEIGHTS_PER_PROC  = INPUT_NEURONS * (NEURONS/NEURON_PROCESSORS);
    localparam WEIGHT_WORDS      = WEIGHTS_PER_PROC / CONFIG_WIDTH;

    // DUT Signals
    logic clk, rst;
    logic valid_input;
    logic [INPUT_WIDTH-1:0] inputs;

    logic valid_weights;
    logic valid_thresholds;
    logic [CONFIG_WIDTH-1:0] config_stream;

    logic valid_output;
    logic [CONFIG_WIDTH-1:0] layer_out;

    // Instantiate DUT
    bnn_layer #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .NEURON_PROCESSORS(NEURON_PROCESSORS),
        .NEURONS(NEURONS),
        .INPUT_NEURONS(INPUT_NEURONS),
        .CONFIG_WIDTH(CONFIG_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_input(valid_input),
        .inputs(inputs),
        .valid_weights(valid_weights),
        .valid_thresholds(valid_thresholds),
        .config_stream(config_stream),
        .valid_output(valid_output),
        .layer_out(layer_out),
        .popcount()
    );

    localparam INPUT_CHUNKS = (INPUT_NEURONS + INPUT_WIDTH - 1) / INPUT_WIDTH;

    // Clock generation
    always #5 clk = ~clk; // 100MHz clock

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        valid_input = 0;
        inputs = 0;
        valid_weights = 0;
        valid_thresholds = 0;
        config_stream = 0;

        #20;
        rst = 0;

        // ------------------------
        // Load Weights
        // ------------------------
        @(negedge clk);
        valid_weights = 1;
        config_stream = 64'hFFFFFFFFFFFFFFFF; // dummy weight word
        @(negedge clk);
        valid_weights = 1;

        // Feed a few weight words
        repeat (WEIGHT_WORDS*NEURON_PROCESSORS - 1) begin
            @(negedge clk);
            config_stream = 64'hFFFFFFFFFFFFFFFF;
        end

        // ------------------------
        // Load Thresholds
        // ------------------------
        @(negedge clk);
        valid_weights = 0;
        valid_thresholds = 1;
        config_stream = {32'd65, 32'd65}; // first 2 thresholds packed
        @(negedge clk);
        valid_thresholds = 1;

        // Feed remaining thresholds
        for (int i=1; i < NEURONS/ (CONFIG_WIDTH/32); i++) begin
            @(negedge clk);
            config_stream = {32'd65, 32'd65};
        end

        // Wait a few cycles
        repeat(5) @(negedge clk);

        valid_thresholds = 0;

        valid_input = 1;
        for (int c = 0; c < INPUT_CHUNKS * (NEURONS / NEURON_PROCESSORS); c++) begin //if only input chunks, then it'll only do 1 neuron per np
            inputs = 64'hFFFFFFFFFFFFFFFF; // random pattern per chunk
            @(negedge clk);
        end

        // Wait a few cycles for outputs to propagate
        repeat(100) @(negedge clk);

        $stop;
    end

endmodule