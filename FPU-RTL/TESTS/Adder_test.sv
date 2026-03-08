
`timescale 1ns/1ps

module tb_adder_fast;

    // ========================================
    // DUT Signals
    // ========================================
    reg clk, rst_n;
    reg [31:0] input_a, input_b;
    reg input_a_stb, input_b_stb;
    wire [31:0] output_z;
    wire output_z_stb;
    wire active;
    
    // ========================================
    // Test Tracking
    // ========================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer cycle_count;
    
    // ========================================
    // Instantiate DUT
    // ========================================
    adder_fast_norm dut (
        .clk(clk),
        .rst_n(rst_n),
        .input_a(input_a),
        .input_b(input_b),
        .input_a_stb(input_a_stb),
        .input_b_stb(input_b_stb),
        .output_z(output_z),
        .output_z_stb(output_z_stb),
        .active(active)
    );
    
    // ========================================
    // Clock Generation: 100 MHz
    // ========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period
    end
    
    // ========================================
    // Cycle Counter
    // ========================================
    always @(posedge clk) begin
        if (rst_n) cycle_count = cycle_count + 1;
    end
    
    // ========================================
    // Timeout Watchdog
    // ========================================
    initial begin
        #100000;  // 100us timeout
        $display("\n*** ERROR: Simulation timeout! ***");
        $display("Test may be stuck in infinite loop");
        $finish;
    end
    
    // ========================================
    // IEEE-754 Helper Functions
    // ========================================
    
    // Convert 32-bit hex to float representation string
    function [255:0] hex_to_float_str;
        input [31:0] hex_val;
        reg sign;
        reg [7:0] exp;
        reg [22:0] mant;
        begin
            sign = hex_val[31];
            exp = hex_val[30:23];
            mant = hex_val[22:0];
            
            if (exp == 8'hFF && mant != 0) begin
                hex_to_float_str = "NaN";
            end
            else if (exp == 8'hFF && mant == 0) begin
                if (sign) hex_to_float_str = "-Inf";
                else hex_to_float_str = "+Inf";
            end
            else if (exp == 0 && mant == 0) begin
                if (sign) hex_to_float_str = "-0.0";
                else hex_to_float_str = "+0.0";
            end
            else begin
                hex_to_float_str = "Normal";
            end
        end
    endfunction
    
    // Check if two floats are "close enough" (within 1-2 ULP)
    function is_close;
        input [31:0] a, b;
        reg [31:0] diff;
        begin
            // Exact match
            if (a == b) begin
                is_close = 1;
            end
            // Both NaN
            else if ((a[30:23] == 8'hFF && a[22:0] != 0) &&
                     (b[30:23] == 8'hFF && b[22:0] != 0)) begin
                is_close = 1;
            end
            // Same sign and exponent, mantissa within 2 ULP
            else if (a[31] == b[31] && a[30:23] == b[30:23]) begin
                diff = (a[22:0] > b[22:0]) ? 
                       (a[22:0] - b[22:0]) : (b[22:0] - a[22:0]);
                is_close = (diff <= 2);
            end
            else begin
                is_close = 0;
            end
        end
    endfunction
    
    // ========================================
    // Main Test Task
    // ========================================
    task test_fadd;
        input [31:0] a, b, expected;
        input [255:0] test_name;
        reg [31:0] result;
        integer start_cycle;
        integer latency;
        begin
            test_count = test_count + 1;
            
            $display("\n--- Test %0d: %s ---", test_count, test_name);
            $display("  A        = 0x%08h (%s)", a, hex_to_float_str(a));
            $display("  B        = 0x%08h (%s)", b, hex_to_float_str(b));
            $display("  Expected = 0x%08h (%s)", expected, hex_to_float_str(expected));
            
            // Start operation
            @(posedge clk);
            start_cycle = cycle_count;
            input_a = a;
            input_b = b;
            input_a_stb = 1;
            input_b_stb = 1;
            
            @(posedge clk);
            input_a_stb = 0;
            input_b_stb = 0;
            
            // Wait for completion
            fork
                begin
                    wait(output_z_stb);
                end
                begin
                    #10000;  // 10us per test timeout
                    $display("  *** Test timeout! ***");
                end
            join_any
            disable fork;
            
            if (output_z_stb) begin
                result = output_z;
                latency = cycle_count - start_cycle;
                
                $display("  Result   = 0x%08h (%s)", result, hex_to_float_str(result));
                $display("  Latency  = %0d cycles", latency);
                
                if (is_close(result, expected)) begin
                    $display("  ✓ PASS");
                    pass_count = pass_count + 1;
                end
                else begin
                    $display("  ✗ FAIL - Mismatch!");
                    $display("    Got:      0x%08h", result);
                    $display("    Expected: 0x%08h", expected);
                    fail_count = fail_count + 1;
                end
            end
            else begin
                $display("  ✗ FAIL - Timeout");
                fail_count = fail_count + 1;
            end
            
            // Wait before next test
            repeat(5) @(posedge clk);
        end
    endtask
    
    // ========================================
    // Main Test Sequence
    // ========================================
    initial begin
        $dumpfile("adder_fast_tb.vcd");
        $dumpvars(0, tb_adder_fast);
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        input_a = 0;
        input_b = 0;
        input_a_stb = 0;
        input_b_stb = 0;
        
        $display("========================================");
        $display("  Fast FP Adder Testbench");
        $display("========================================");
        
        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // ====================================
        // CATEGORY 1: Basic Addition
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 1: Basic Addition       ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h40200000, 32'h3FC00000, 32'h40800000, 
                  "2.5 + 1.5 = 4.0");
        
        test_fadd(32'h3F800000, 32'h3F800000, 32'h40000000, 
                  "1.0 + 1.0 = 2.0");
        
        test_fadd(32'h40000000, 32'h40400000, 32'h40A00000, 
                  "2.0 + 3.0 = 5.0");
        
        test_fadd(32'h41200000, 32'h42C80000, 32'h42DC0000, 
                  "10.0 + 100.0 = 110.0");
        
        // ====================================
        // CATEGORY 2: Subtraction
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 2: Subtraction          ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h40800000, 32'hBFC00000, 32'h40200000, 
                  "4.0 + (-1.5) = 2.5");
        
        test_fadd(32'h40000000, 32'hBF800000, 32'h3F800000, 
                  "2.0 + (-1.0) = 1.0");
        
        test_fadd(32'h3F800000, 32'hBF800000, 32'h00000000, 
                  "1.0 + (-1.0) = 0.0");
        
        // ====================================
        // CATEGORY 3: Alignment Stress Test
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 3: Large Exp Difference ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h42C80000, 32'h3A83126F, 32'h42C80083, 
                  "100.0 + 0.001 ≈ 100.0");
        
        test_fadd(32'h447A0000, 32'h3C23D70A, 32'h447A00A4, 
                  "1000.0 + 0.01 ≈ 1000.0");
        
        test_fadd(32'h461C4000, 32'h3F800000, 32'h461c4400, 
                  "10000.0 + 1.0 ≈ 10000.0");
        
        // ====================================
        // CATEGORY 4: Cancellation (Normalization Test)
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 4: Cancellation         ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h3F800000, 32'hBF7FFFFF, 32'h33800000, 
                  "1.0 + (-0.999999) ≈ 0.000001");
        
        test_fadd(32'h40000000, 32'hBFFFFFFF, 32'h34000000, 
                  "2.0 + (-1.999999) ≈ 0.000001");
        
        // ====================================
        // CATEGORY 5: Special Values - Zero
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 5: Zero Cases           ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h00000000, 32'h00000000, 32'h00000000, 
                  "+0.0 + +0.0 = +0.0");
        
        test_fadd(32'h00000000, 32'h3F800000, 32'h3F800000, 
                  "+0.0 + 1.0 = 1.0");
        
        test_fadd(32'h3F800000, 32'h00000000, 32'h3F800000, 
                  "1.0 + +0.0 = 1.0");
        
        test_fadd(32'h00000000, 32'h80000000, 32'h00000000, 
                  "+0.0 + -0.0 = +0.0");
        
        // ====================================
        // CATEGORY 6: Special Values - Infinity
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 6: Infinity Cases       ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h7F800000, 32'h3F800000, 32'h7F800000, 
                  "+Inf + 1.0 = +Inf");
        
        test_fadd(32'h3F800000, 32'h7F800000, 32'h7F800000, 
                  "1.0 + +Inf = +Inf");
        
        test_fadd(32'h7F800000, 32'h7F800000, 32'h7F800000, 
                  "+Inf + +Inf = +Inf");
        
        test_fadd(32'hFF800000, 32'hFF800000, 32'hFF800000, 
                  "-Inf + -Inf = -Inf");
        
        test_fadd(32'h7F800000, 32'hFF800000, 32'h7FC00000, 
                  "+Inf + -Inf = NaN");
        
        test_fadd(32'hFF800000, 32'h7F800000, 32'h7FC00000, 
                  "-Inf + +Inf = NaN");
        
        // ====================================
        // CATEGORY 7: Special Values - NaN
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 7: NaN Cases            ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h7FC00000, 32'h3F800000, 32'h7FC00000, 
                  "NaN + 1.0 = NaN");
        
        test_fadd(32'h3F800000, 32'h7FC00000, 32'h7FC00000, 
                  "1.0 + NaN = NaN");
        
        test_fadd(32'h7FC00000, 32'h7FC00000, 32'h7FC00000, 
                  "NaN + NaN = NaN");
        
        // ====================================
        // CATEGORY 8: Rounding
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 8: Rounding Tests       ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h3F7FFFFF, 32'h33800000, 32'h3F800000, 
                  "0.99999994 + small ≈ 1.0 (round up)");
        
        test_fadd(32'h3F800000, 32'h33000000, 32'h3F800000, 
                  "1.0 + tiny ≈ 1.0 (round to even)");
        
        // ====================================
        // CATEGORY 9: Denormal Numbers
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 9: Denormal Numbers     ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h00000001, 32'h00000001, 32'h00000002, 
                  "Tiny + Tiny = 2*Tiny");
        
        test_fadd(32'h007FFFFF, 32'h00000001, 32'h00800000, 
                  "Max_Denorm + 1 = Min_Normal");
        
        // ====================================
        // CATEGORY 10: Stress Test
        // ====================================
        $display("\n╔════════════════════════════════════╗");
        $display("║  CATEGORY 10: Random Stress       ║");
        $display("╚════════════════════════════════════╝");
        
        test_fadd(32'h40490FDB, 32'h3FC90FDB, 32'h4096cbe4, 
                  "π + π/2 ≈ 1.5π");
        
        test_fadd(32'h402DF854, 32'h3F1DE9E7, 32'h405572ce, 
                  "e + ln(2) ≈ 3.3");
        
        // ====================================
        // Print Summary
        // ====================================
        repeat(10) @(posedge clk);
        
        $display("\n========================================");
        $display("  TEST SUMMARY");
        $display("========================================");
        $display("  Total Tests:  %0d", test_count);
        $display("  Passed:       %0d", pass_count);
        $display("  Failed:       %0d", fail_count);
        $display("  Pass Rate:    %0.1f%%", 
                 100.0 * pass_count / test_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("\n  ✓✓✓ ALL TESTS PASSED! ✓✓✓\n");
        end
        else begin
            $display("\n  ✗✗✗ SOME TESTS FAILED ✗✗✗\n");
        end
        
        $finish;
    end
    
    // ========================================
    // Waveform Monitoring
    // ========================================
    always @(posedge clk) begin
        if (output_z_stb) begin
            $display("  [%0t] Operation complete: 0x%08h", $time, output_z);
        end
    end
    
    // ========================================
    // State Monitoring (for debugging)
    // ========================================
    always @(dut.state) begin
        case (dut.state)
            3'd0: $display("  [State] IDLE");
            3'd1: $display("  [State] UNPACK");
            3'd2: $display("  [State] SPECIAL");
            3'd3: $display("  [State] ALIGN");
            3'd4: $display("  [State] ADD");
            3'd5: $display("  [State] NORMALIZE");
            3'd6: $display("  [State] ROUND");
            3'd7: $display("  [State] PACK");
        endcase
    end

endmodule