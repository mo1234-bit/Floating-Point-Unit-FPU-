module goldschmidt_divider_tb;

  // Clock and reset
  reg clk;
  reg rst_n;
  
  // Inputs
  reg [31:0] input_a;
  reg input_a_stb;
  reg [31:0] input_b;
  reg input_b_stb;
  
  // Outputs - Fast Divider
  wire [31:0] output_z_fast;
  wire output_z_stb_fast;
  wire active_fast;
  
  // Outputs - Original Divider
  wire [31:0] output_z_orig;
  wire output_z_stb_orig;
  wire active_orig;
  
  // Test tracking
  integer test_count;
  integer pass_count;
  integer fail_count;
  integer fast_cycles;
  integer orig_cycles;
  integer cycle_count;
  
  // Instantiate fast Goldschmidt divider
  fast_divider fast_dut (
    .clk(clk),
    .rst_n(rst_n),
    .input_a(input_a),
    .input_a_stb(input_a_stb),
    .input_b(input_b),
    .input_b_stb(input_b_stb),
    .output_z(output_z_fast),
    .output_z_stb(output_z_stb_fast),
    .active(active_fast)
  );
  
  // Instantiate original divider for comparison
  divider orig_dut (
    .clk(clk),
    .rst_n(rst_n),
    .input_a(input_a),
    .input_a_stb(input_a_stb),
    .input_b(input_b),
    .input_b_stb(input_b_stb),
    .output_z(output_z_orig),
    .output_z_stb(output_z_stb_orig),
    .active(active_orig)
  );
  
  // Clock generation - 10ns period (100MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // Cycle counter
  always @(posedge clk) begin
    if (active_fast || active_orig)
      cycle_count <= cycle_count + 1;
  end
  
  // Task to convert float to hex for display
  task display_float;
    input [31:0] fp;
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;
    real value;
    begin
      sign = fp[31];
      exp = fp[30:23];
      mant = fp[22:0];
      
      if (exp == 8'd255 && mant != 0)
        $write("NaN");
      else if (exp == 8'd255 && mant == 0)
        $write("%sInf", sign ? "-" : "+");
      else if (exp == 0 && mant == 0)
        $write("%s0.0", sign ? "-" : "+");
      else begin
        value = (sign ? -1.0 : 1.0) * (1.0 + mant / (2.0**23)) * (2.0 ** (exp - 127));
        $write("%f", value);
      end
    end
  endtask
  
  // Task to perform division test
  task test_division;
    input [31:0] a;
    input [31:0] b;
    input string description;
    reg [31:0] result_fast;
    reg [31:0] result_orig;
    integer fast_start, fast_end;
    integer orig_start, orig_end;
    begin
      test_count = test_count + 1;
      
      $display("\n--- Test %0d: %s ---", test_count, description);
      $write("  A = "); display_float(a); 
      $write(" (0x%h)\n", a);
      $write("  B = "); display_float(b); 
      $write(" (0x%h)\n", b);
      
      // Test fast divider
      @(posedge clk);
      input_a <= a;
      input_b <= b;
      input_a_stb <= 1;
      input_b_stb <= 1;
      cycle_count <= 0;
      
      @(posedge clk);
      input_a_stb <= 0;
      input_b_stb <= 0;
      
      fast_start = cycle_count;
      wait(output_z_stb_fast);
      @(posedge clk);
      fast_end = cycle_count;
      result_fast = output_z_fast;
      
      // Wait for original divider
      wait(output_z_stb_orig);
      @(posedge clk);
      orig_end = cycle_count;
      result_orig = output_z_orig;
      
      // Display results
      $write("  Fast Result = "); display_float(result_fast);
      $write(" (0x%h) in %0d cycles\n", result_fast, fast_end - fast_start);
      
      $write("  Orig Result = "); display_float(result_orig);
      $write(" (0x%h) in %0d cycles\n", result_orig, orig_end - fast_start);
      
      // Compare results (allow small differences due to rounding)
      if (result_fast == result_orig || 
          ((result_fast[30:23] == result_orig[30:23]) && 
           (result_fast[31] == result_orig[31]) &&
           ((result_fast[22:0] - result_orig[22:0]) < 2 || 
            (result_orig[22:0] - result_fast[22:0]) < 2))) begin
        $display("  ✓ PASS - Results match!");
        pass_count = pass_count + 1;
      end else begin
        $display("  ✗ FAIL - Results differ!");
        fail_count = fail_count + 1;
      end
      
      fast_cycles = fast_cycles + (fast_end - fast_start);
      orig_cycles = orig_cycles + (orig_end - fast_start);
      
      // Wait a few cycles before next test
      repeat(5) @(posedge clk);
    end
  endtask
  
  // Function to create IEEE 754 float
  function [31:0] make_float;
    input sign;
    input [7:0] exp;
    input [22:0] mant;
    begin
      make_float = {sign, exp, mant};
    end
  endfunction
  
  // Main test sequence
  initial begin
    $display("========================================");
    $display("Goldschmidt Fast Divider Test Bench");
    $display("========================================");
    
    // Initialize
    rst_n = 0;
    input_a = 0;
    input_b = 0;
    input_a_stb = 0;
    input_b_stb = 0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    fast_cycles = 0;
    orig_cycles = 0;
    cycle_count = 0;
    
    // Reset
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);
    
    // Test 1: Simple division
    test_division(32'h40800000, 32'h40000000, "4.0 / 2.0 = 2.0");
    
    // Test 2: Division resulting in fraction
    test_division(32'h3F800000, 32'h40000000, "1.0 / 2.0 = 0.5");
    
    // Test 3: Division by 1
    test_division(32'h42480000, 32'h3F800000, "50.0 / 1.0 = 50.0");
    
    // Test 4: Large / Small
    test_division(32'h447A0000, 32'h3C23D70A, "1000.0 / 0.01 = 100000.0");
    
    // Test 5: Small / Large
    test_division(32'h3C23D70A, 32'h447A0000, "0.01 / 1000.0 = 0.00001");
    
    // Test 6: Negative numbers
    test_division(32'hC0800000, 32'h40000000, "-4.0 / 2.0 = -2.0");
    
    // Test 7: Both negative
    test_division(32'hC0800000, 32'hC0000000, "-4.0 / -2.0 = 2.0");
    
    // Test 8: Division by zero -> Infinity
    test_division(32'h3F800000, 32'h00000000, "1.0 / 0.0 = Inf");
    
    // Test 9: Zero divided by number
    test_division(32'h00000000, 32'h40000000, "0.0 / 2.0 = 0.0");
    
    // Test 10: Zero divided by zero -> NaN
    test_division(32'h00000000, 32'h00000000, "0.0 / 0.0 = NaN");
    
    // Test 11: Infinity / number
    test_division(32'h7F800000, 32'h40000000, "Inf / 2.0 = Inf");
    
    // Test 12: Number / Infinity
    test_division(32'h40000000, 32'h7F800000, "2.0 / Inf = 0.0");
    
    // Test 13: Infinity / Infinity -> NaN
    test_division(32'h7F800000, 32'h7F800000, "Inf / Inf = NaN");
    
    // Test 14: Very close numbers
    test_division(32'h3F800001, 32'h3F800000, "1.0000001 / 1.0");
    
    // Test 15: Pi / E (transcendental test)
    test_division(32'h40490FDB, 32'h402DF854, "3.14159 / 2.71828");
    
    // Test 16: Random practical values
    test_division(32'h42C80000, 32'h41200000, "100.0 / 10.0 = 10.0");
    
    // Test 17: Denormalized numbers
    test_division(32'h00800000, 32'h3F800000, "Denorm / 1.0");
    
    // Test 18: Near overflow result
    test_division(32'h7F000000, 32'h00800000, "Large / Small");

    // Test 19: +0 / -number = -0
test_division(32'h00000000, 32'hC0000000, "+0.0 / -2.0 = -0.0");

// Test 20: -0 / +number = -0
test_division(32'h80000000, 32'h40000000, "-0.0 / 2.0 = -0.0");

// Test 21: -0 / -number = +0
test_division(32'h80000000, 32'hC0000000, "-0.0 / -2.0 = +0.0");

// Test 22: Quiet NaN / number
test_division(32'h7FC00000, 32'h40000000, "NaN / 2.0 = NaN");

// Test 23: number / Quiet NaN
test_division(32'h40000000, 32'h7FC00000, "2.0 / NaN = NaN");

// Test 24: Signaling NaN (if supported)
test_division(32'h7FA00000, 32'h3F800000, "sNaN / 1.0 = NaN");

// Test 25: Overflow to Infinity
test_division(32'h7F7FFFFF, 32'h00800000, "Max normal / min normal = Inf");

// Test 26: Underflow to zero
test_division(32'h00800000, 32'h7F7FFFFF, "Min normal / max normal = 0.0");

// Test 27: Subnormal result
test_division(32'h00800000, 32'h40000000, "Min normal / 2.0 = subnormal");

// Test 28: Rounding up
test_division(32'h3F800000, 32'h3F000001, "1.0 / 0.50000006");

// Test 29: Rounding down
test_division(32'h3F800000, 32'h3F000000, "1.0 / 0.5 = 2.0");

// Test 30: Half-ULP boundary
test_division(32'h3F800001, 32'h3F7FFFFF, "ULP boundary divide");

// Test 31: Divide by power of two
test_division(32'h41200000, 32'h40000000, "10.0 / 2.0 = 5.0");

// Test 32: Power of two / power of two
test_division(32'h40000000, 32'h40800000, "2.0 / 4.0 = 0.5");

// Test 33: Negative power of two
test_division(32'hC1000000, 32'h40000000, "-8.0 / 2.0 = -4.0");

// Test 34: x / x = 1.0
test_division(32'h41200000, 32'h41200000, "10.0 / 10.0 = 1.0");

// Test 35: -x / x = -1.0
test_division(32'hC1200000, 32'h41200000, "-10.0 / 10.0 = -1.0");

// Test 36: x / -x = -1.0
test_division(32'h41200000, 32'hC1200000, "10.0 / -10.0 = -1.0");

// Test 37: Long mantissa division
test_division(32'h3F7FFFFF, 32'h3F000000, "0.99999994 / 0.5");

// Test 38: Repeating fraction
test_division(32'h3F800000, 32'h40400000, "1.0 / 3.0");

// Test 39: Tiny / tiny
test_division(32'h00000001, 32'h00000002, "Tiny / tiny");


    test_random_divisions(1000);
    // Wait for completion
    repeat(10) @(posedge clk);
    
    // Summary
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total Tests:  %0d", test_count);
    $display("Passed:       %0d", pass_count);
    $display("Failed:       %0d", fail_count);
    $display("Pass Rate:    %0d%%", (pass_count * 100) / test_count);
    $display("");
    $display("Performance Comparison:");
    $display("Fast Divider Avg: %0d cycles", fast_cycles / test_count);
    $display("Orig Divider Avg: %0d cycles", orig_cycles / test_count);
    $display("Speedup:          %.2fx", real'(orig_cycles) / real'(fast_cycles));
    $display("========================================");
    
    $finish;
  end
  
  // Timeout watchdog
  initial begin
    #10000000;
    $display("\nERROR: Simulation timeout!");
    $finish;
  end
  
  // Optional: Waveform dump
  initial begin
    $dumpfile("goldschmidt_divider_tb.vcd");
    $dumpvars(0, goldschmidt_divider_tb);
  end
// Randomized test task
// Task to test random floating-point numbers
task test_random_divisions;
  input integer num_tests;
  integer i;
  reg [31:0] a, b;
  string desc;

begin
  for (i = 0; i < num_tests; i = i + 1) begin
    // Generate random floats
    a = random_float_safe();
    b = random_float_safe_nonzero();  // avoid zero in denominator

    desc = $sformatf("Random Test %0d: ", i+1);

    test_division(a, b, desc);
  end
end
endtask

// Function: random float (safe)
function [31:0] random_float_safe;
  reg sign;
  reg [7:0] exp;
  reg [22:0] mant;
begin
  sign = $urandom_range(0,1);
  exp  = $urandom_range(1,254);     // avoid zero and Inf/NaN
  mant = $urandom_range(0, 2**23-1);
  random_float_safe = {sign, exp, mant};
end
endfunction

// Function: random float for denominator (avoid zero)
function [31:0] random_float_safe_nonzero;
  reg [31:0] val;
begin
  val = random_float_safe();
  if (val[30:0] == 0) val[22] = 1; // make sure not exactly zero
  random_float_safe_nonzero = val;
end
endfunction


endmodule