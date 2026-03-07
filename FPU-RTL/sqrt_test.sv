
module tb_fsqrt_ultrafast;

    reg clk, rst_n, start;
    reg [31:0] operand;
    wire [31:0] result;
    wire done, busy;
    wire [7:0] debug_exp_result;
    wire [47:0] debug_x, debug_operand_q, debug_temp, debug_y_times_x_sq;
    wire [3:0] debug_state;
    
    integer test_count, pass_count, fail_count;
    
    reg [127:0] state_name;
    always @(*) begin
        case (debug_state)
            0: state_name = "IDLE";
            1: state_name = "CHECK";
            2: state_name = "INIT";
            3: state_name = "ITER1";
            4: state_name = "ITER1B";
            5: state_name = "ITER2";
            6: state_name = "FINALIZE";
            7: state_name = "MULTIPLY";
            8: state_name = "ITER3";
            9: state_name = "ITER3B";
            10: state_name = "EXTRACT";
            11: state_name = "FINALIZE2";
            12: state_name = "FINAL_MULT";
            13: state_name = "FINAL_EXTRACT";
            14: state_name = "DONE_STATE";
            default: state_name = "UNKNOWN";
        endcase
    end
    
    fsqrt_ultrafast dut (
        .clk(clk), .rst_n(rst_n), .start(start), .operand(operand),
        .result(result), .done(done), .busy(busy),
        .debug_exp_result(debug_exp_result), .debug_x(debug_x),
        .debug_operand_q(debug_operand_q), .debug_temp(debug_temp),
        .debug_y_times_x_sq(debug_y_times_x_sq), .debug_state(debug_state)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    function [31:0] real_to_float;
        input real r;
        real abs_r;
        integer exp;
        integer exp_biased;
        real mant;
        reg [22:0] mant_bits;
        reg [7:0] exp_bits;
        reg sign;
        begin
            if (r == 0.0) begin
                real_to_float = 32'h00000000;
            end else begin
                sign = (r < 0.0) ? 1'b1 : 1'b0;
                abs_r = (r < 0.0) ? -r : r;
                exp = $rtoi($floor($ln(abs_r) / $ln(2.0)));
                mant = abs_r / (2.0 ** exp);
                while (mant >= 2.0) begin
                    mant = mant / 2.0;
                    exp = exp + 1;
                end
                while (mant < 1.0) begin
                    mant = mant * 2.0;
                    exp = exp - 1;
                end
                mant_bits = $rtoi((mant - 1.0) * (2.0 ** 23));
                exp_biased = exp + 127;
                exp_bits = exp_biased[7:0];
                real_to_float = {sign, exp_bits, mant_bits};
            end
        end
    endfunction
    
    function is_nan;
        input [31:0] f;
        begin
            is_nan = (f[30:23] == 8'hFF) && (f[22:0] != 23'h0);
        end
    endfunction
    
    function real float_to_real;
        input [31:0] f;
        reg sign;
        integer exp;
        real mant;
        begin
            sign = f[31];
            exp = f[30:23];
            mant = 1.0 + (f[22:0] / (2.0 ** 23));
            if (exp == 8'hFF) begin
                float_to_real = (f[22:0] == 0) ? 
                    (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
            end else if (exp == 0 && f[22:0] == 0) begin
                float_to_real = 0.0;
            end else begin
                float_to_real = (sign ? -1.0 : 1.0) * mant * (2.0 ** (exp - 127));
            end
        end
    endfunction
    
    function real calc_error;
        input [31:0] computed;
        input real expected;
        real computed_real;
        begin
            computed_real = float_to_real(computed);
            if (expected == 0.0) begin
                calc_error = computed_real;
            end else begin
                calc_error = (computed_real - expected) / expected;
            end
        end
    endfunction
    
    function real q24_24_to_real;
        input [47:0] val;
        begin
            q24_24_to_real = val / (2.0 ** 24);
        end
    endfunction
    
    task debug_state_dump;
        reg [47:0] next_val;
        begin
            $display("  [%0s] X=%h (%.6f), Temp=%h (%.6f), Y*X²=%h (%.6f)",
                state_name, debug_x, q24_24_to_real(debug_x),
                debug_temp, q24_24_to_real(debug_temp),
                debug_y_times_x_sq, q24_24_to_real(debug_y_times_x_sq));
            $display("         OperandQ=%h (%.6f), ExpResult=%d",
                debug_operand_q, q24_24_to_real(debug_operand_q), debug_exp_result);
            case (debug_state)
                4: begin
                    next_val = (debug_x * debug_x) >> 24;
                    $display("         -> Computing: temp = x²>>24 = %h (%.6f)", 
                        next_val, q24_24_to_real(next_val));
                end
                5: begin
                    next_val = (debug_operand_q * debug_temp) >> 24;
                    $display("         -> Computing: y*x² = %h (%.6f)",
                        next_val, q24_24_to_real(next_val));
                end
                6: begin
                    next_val = (48'd3 << 24) - debug_y_times_x_sq;
                    $display("         -> Computing: temp = 3 - y*x² = %h (%.6f)",
                        next_val, q24_24_to_real(next_val));
                end
                7: begin
                    next_val = (debug_x * debug_temp) >> 25;
                    $display("         -> Computing: x = (x*temp)>>25 = %h (%.6f)",
                        next_val, q24_24_to_real(next_val));
                end
            endcase
        end
    endtask
    
    task test_sqrt;
        input [31:0] test_val;
        input real expected;
        input string description;
        input enable_debug;
        real error, computed_val, abs_error;
        integer cycle_count;
        reg [3:0] prev_state;
        begin
            test_count = test_count + 1;
            
            if (enable_debug) begin
                $display("\n================================================");
                $display("=== DEBUG: %s ===", description);
                $display("Input: %h = %f", test_val, float_to_real(test_val));
                $display("Expected result: %f", expected);
                $display("================================================");
            end
            
            @(posedge clk);
            operand = test_val;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            
            cycle_count = 0;
            prev_state = 15;
            
            repeat(25) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                
                if (enable_debug && debug_state != prev_state) begin
                    $display("  Cycle %0d: State %0d->%0d (%0s)", 
                        cycle_count, prev_state, debug_state, state_name);
                    debug_state_dump();
                    prev_state = debug_state;
                end
                
                if (done) break;
            end
            
            if (!done) begin
                $display("[FAIL] Test %0d: %s - TIMEOUT", test_count, description);
                fail_count = fail_count + 1;
            end else begin
                computed_val = float_to_real(result);
                
                if (expected == 0.0) begin
                    if (result == 32'h00000000 || result == 32'h80000000) begin
                        $display("[PASS] Test %0d: %s", test_count, description);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] Test %0d: %s - Expected 0, got %h (%f)", 
                            test_count, description, result, computed_val);
                        fail_count = fail_count + 1;
                    end
                end else if ((result[30:23] == 8'hFF)) begin
                    $display("[PASS] Test %0d: %s", test_count, description);
                    pass_count = pass_count + 1;
                end else begin
                    error = calc_error(result, expected);
                    abs_error = (error < 0) ? -error : error;
                    
                    if (abs_error < 0.001) begin
                        $display("[PASS] Test %0d: %s (error: %.3f%%)", 
                            test_count, description, error*100);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("[FAIL] Test %0d: %s", test_count, description);
                        $display("       Computed=%f, Expected=%f, Error=%.3f%%", 
                            computed_val, expected, error*100);
                        fail_count = fail_count + 1;
                    end
                end
            end
            
            @(posedge clk);
        end
    endtask
    
    initial begin
        $display("\n========================================");
        $display("  FSQRT Ultra-Fast DEBUG Testbench");
        $display("========================================\n");
        
        clk = 0;
        rst_n = 0;
        start = 0;
        operand = 0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        #20 rst_n = 1;
        #20;
        
        $display("--- Special Cases ---");
        test_sqrt(32'h00000000, 0.0, "sqrt(+0)", 0);
        test_sqrt(32'h80000000, 0.0, "sqrt(-0)", 0);
        test_sqrt(32'h7F800000, 1.0/0.0, "sqrt(+Inf)", 0);
        test_sqrt(32'h7FC00000, 0.0/0.0, "sqrt(NaN)", 0);
        test_sqrt(32'hBF800000, 0.0/0.0, "sqrt(-1.0)", 0);
        
        $display("\n--- Perfect Squares ---");
        test_sqrt(real_to_float(1.0), 1.0, "sqrt(1.0)", 0);
        test_sqrt(real_to_float(4.0), 2.0, "sqrt(4.0)", 0);
        test_sqrt(real_to_float(9.0), 3.0, "sqrt(9.0)", 0);
        test_sqrt(real_to_float(16.0), 4.0, "sqrt(16.0)", 0);
        test_sqrt(real_to_float(25.0), 5.0, "sqrt(25.0)", 0);
        test_sqrt(real_to_float(100.0), 10.0, "sqrt(100.0)", 0);
        
        $display("\n--- Non-Perfect Squares ---");
        test_sqrt(real_to_float(2.0), $sqrt(2.0), "sqrt(2.0)", 0);
        test_sqrt(real_to_float(3.0), $sqrt(3.0), "sqrt(3.0)", 0);
        test_sqrt(real_to_float(5.0), $sqrt(5.0), "sqrt(5.0)", 0);
        test_sqrt(real_to_float(10.0), $sqrt(10.0), "sqrt(10.0)", 0);
        
        $display("\n--- Fractional Values ---");
        test_sqrt(real_to_float(0.25), 0.5, "sqrt(0.25)", 0);
        test_sqrt(real_to_float(0.5), $sqrt(0.5), "sqrt(0.5)", 0);
        test_sqrt(real_to_float(0.01), 0.1, "sqrt(0.01)", 0);
        
        $display("\n--- Large Values ---");
        test_sqrt(real_to_float(1000.0), $sqrt(1000.0), "sqrt(1000.0)", 0);
        test_sqrt(real_to_float(1000000.0), 1000.0, "sqrt(1000000.0)", 0);
        
        $display("\n--- Small Values ---");
        test_sqrt(real_to_float(0.001), $sqrt(0.001), "sqrt(0.001)", 0);
        test_sqrt(real_to_float(0.0001), 0.01, "sqrt(0.0001)", 0);
        
        #100;
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("Total: %0d, Passed: %0d, Failed: %0d", test_count, pass_count, fail_count);
        if (test_count > 0)
            $display("Pass Rate: %.1f%%", (pass_count * 100.0) / test_count);
        $display("========================================\n");
        
        $finish;
    end
    
    initial begin
        #100000;
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule