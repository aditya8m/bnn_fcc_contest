module bnn_layer #(
    parameter INPUT_WIDTH = 64,
    parameter NEURON_PROCESSORS = 8,
    parameter NEURONS = 256,
    parameter INPUT_NEURONS = 784,
    parameter CONFIG_WIDTH = 64 // either 64 or 32 because thresholds are 32 bits each
)(
    input  logic clk,
    input  logic rst,

    input logic valid_input,
    input logic [INPUT_WIDTH-1:0] inputs,

    // RAM interfaces
    input logic valid_thresholds,
    input logic valid_weights,
    input logic [CONFIG_WIDTH-1:0] config_stream, // all thresholds and weights are stored in RAM before input starts

    // output stream
    output logic valid_output,
    output logic [CONFIG_WIDTH-1:0] layer_out,// output this the same way you got input

    output logic popcount //fix this
);

    // PARAMETERS
    localparam NEURONS_PER_PROC = NEURONS / NEURON_PROCESSORS;
    localparam WEIGHTS_PER_PROC = INPUT_NEURONS * NEURONS_PER_PROC;
    localparam WEIGHT_WORDS     = WEIGHTS_PER_PROC / CONFIG_WIDTH;
    localparam THRESHOLDS_PER_WORD = CONFIG_WIDTH / 32; //can't be less than 1.

    // weight and threshold RAMs
    logic [CONFIG_WIDTH-1:0] weight_rams [NEURON_PROCESSORS-1:0][WEIGHT_WORDS-1:0];
    logic [31:0] threshold_rams [NEURON_PROCESSORS-1:0][NEURONS_PER_PROC-1:0];

    logic [$clog2(WEIGHT_WORDS):0] weight_addr;
    logic [$clog2(NEURON_PROCESSORS):0] proc_sel;
    logic [$clog2(NEURONS):0] thresh_addr;

    //weights
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            weight_addr        <= '0;
            proc_sel           <= '0;
        end if (valid_weights) begin
            weight_rams[proc_sel][weight_addr] <= config_stream;

            if (weight_addr == WEIGHT_WORDS-1) begin
                weight_addr <= 0;
                proc_sel    <= proc_sel + 1;
            end else begin
                weight_addr <= weight_addr + 1;
            end
        end
    end

    //thresholds
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            thresh_addr        <= 0;
        end else if (valid_thresholds) begin
            for (int i = 0; i < THRESHOLDS_PER_WORD; i++) begin
                if ((thresh_addr + i) < NEURONS) begin
                    threshold_rams[(thresh_addr + i) / NEURONS_PER_PROC][(thresh_addr + i) % NEURONS_PER_PROC] <=
                        config_stream[32*i +: 32];
                end
            end
            thresh_addr <= thresh_addr + THRESHOLDS_PER_WORD;
        end
    end

    //neuron processors 
    localparam INPUT_CHUNKS = (INPUT_NEURONS + INPUT_WIDTH - 1) / INPUT_WIDTH; //$ceil(INPUT_NEURONS/INPUT_WIDTH)

    logic [$clog2(INPUT_CHUNKS)-1:0] chunk_idx;
    logic [$clog2(NEURONS_PER_PROC)-1:0] thresh_num;
    logic last;
    logic [$clog2(INPUT_NEURONS + 1)-1:0] popcounts [NEURONS-1:0];
    logic valid_np_out [NEURON_PROCESSORS-1:0];
    logic y_internal   [NEURON_PROCESSORS-1:0];
    logic [$clog2(INPUT_NEURONS + 1)-1:0] popcount_internal [NEURON_PROCESSORS-1:0];
    logic [NEURONS-1:0] y_output;

    //valid_in and last
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            chunk_idx <= 0;
        else if (valid_input) begin
            if (chunk_idx == INPUT_CHUNKS-1)
                chunk_idx <= 0;
            else
                chunk_idx <= chunk_idx + 1;
        end
    end

    assign last = (chunk_idx == INPUT_CHUNKS-1);

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            thresh_num <= '0;
        else if (last) begin
            if (thresh_num == NEURONS_PER_PROC-1)
                thresh_num <= '0; 
            else
                thresh_num <= thresh_num + 1;
        end
    end

    //generate neuron processors
    genvar i;
    generate
        for (i=0; i<NEURON_PROCESSORS; i=i+1) begin : neuron_procs
            logic [$clog2(WEIGHT_WORDS)-1:0] weight_addr_read;

            assign weight_addr_read = thresh_num * INPUT_CHUNKS + chunk_idx;

            neuron_processor #(
                .INPUT_WIDTH(INPUT_WIDTH),
                .NEURON_COUNT(INPUT_NEURONS)
            ) neuron_inst (
                .clk(clk),
                .rst(rst),
                .in(inputs),
                .weights(weight_rams[i][weight_addr_read]),      
                .threshold(threshold_rams[i][thresh_num]),
                .valid_in(valid_input),
                .last(last),
                .popcount(popcount_internal[i]),
                .valid_out(valid_np_out[i]),
                .y(y_internal[i])
            );
        end
    endgenerate

    //output location update is delayed by 3 cycles.

    logic [$clog2(NEURONS_PER_PROC)-1:0] thresh_num_d1, thresh_num_d2, thresh_num_d3;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            thresh_num_d1 <= 0;
            thresh_num_d2 <= 0;
            thresh_num_d3 <= 0;
        end else begin
            thresh_num_d1 <= thresh_num;
            thresh_num_d2 <= thresh_num_d1;
            thresh_num_d3 <= thresh_num_d2;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            int k;
            for (k = 0; k < NEURONS; k++) begin
                popcounts[k] <= '0;
                y_output[k] <= '0;
            end

        end else begin
            int j;
            for (j=0; j<NEURON_PROCESSORS; j=j+1) begin
                if (valid_np_out[j]) begin
                    y_output[j*NEURONS_PER_PROC + thresh_num_d3] <= y_internal[j];
                    popcounts [j*NEURONS_PER_PROC + thresh_num_d3] <= popcount_internal[j];
                end
            end
        end
    end

endmodule