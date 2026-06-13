// Scoreboard helps in receiving the actual i2c_transactions from i2c_monitor (nb_put), and gets predicted transactions from the shared mailbox (get())
// Helps in comparing the actual vs expected and prints PASS/FAIL for every transfer
class i2cmb_scoreboard extends ncsu_pkg::ncsu_component #(i2c_pkg::i2c_transaction);

  // Shared mailbox: predictor put()s predictions, and get() them here
  // Assigned by environment before run()
  mailbox #(i2c_pkg::i2c_transaction) expected_mb;

  int num_pass_count;    // total transfers that matched (including post-Phase-C)
  int num_fail_count;    // total transfers that failed
  int num_directed_count; // only Phase A+B+C (first 192) - used for summary display

  bit directed_phase_active;
  bit suppress_warnings;

  function new(string name = "i2cmb_scoreboard", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
    num_pass_count     = 0;
    num_fail_count     = 0;
    num_directed_count = 0;
    directed_phase_active = 0;
    suppress_warnings     = 0;
  endfunction

  // This is called by the i2c_monitor for every actual I2C transfer seen on the bus
  // Fetches the next prediction from the mailbox, then starts comparison
  virtual function void nb_put(input i2c_pkg::i2c_transaction trans);
    i2c_pkg::i2c_transaction actual   = trans;
    i2c_pkg::i2c_transaction expected;

    // Tries to get a prediction from the mailbox 
    // If no prediction is available, then the DUT sent an unexpected transfer
    if (!expected_mb.try_get(expected)) 
    begin
      if (!suppress_warnings)
      begin
        ncsu_info("i2cmb_scoreboard", "WARNING: actual I2C transfer received with no prediction available.", NCSU_NONE);
      end
      return;
    end

    // --- Address check ---
    if (actual.addr !== expected.addr) 
    begin
      ncsu_info("i2cmb_scoreboard", $sformatf("FAIL: addr mismatch. Expected=0x%0h  Actual=0x%0h", expected.addr, actual.addr), NCSU_NONE);
      num_fail_count++;
      return;
    end

    // --- Operation check ---
    // if it's read vs write
    if (actual.op !== expected.op) 
    begin
      ncsu_info("i2cmb_scoreboard", $sformatf("FAIL: op mismatch. Expected=%s  Actual=%s", (expected.op ? "READ":"WRITE"), (actual.op ? "READ":"WRITE")), NCSU_NONE);
      num_fail_count++;
      return;
    end

    // --- Data check for size---
    if (actual.data.size() !== expected.data.size()) 
    begin
      ncsu_info("i2cmb_scoreboard", $sformatf("FAIL [%s]: size mismatch. Expected=%0d  Actual=%0d", (actual.op ? "READ":"WRITE"), expected.data.size(), actual.data.size()), NCSU_NONE);
      num_fail_count++;
      return;
    end

    // --- Byte-by-byte data check ---
    foreach (actual.data[i]) 
    begin
      if (actual.data[i] !== expected.data[i]) 
      begin
        ncsu_info("i2cmb_scoreboard", $sformatf("FAIL [%s]: data[%0d] mismatch. Expected=%0d  Actual=%0d", (actual.op ? "READ":"WRITE"), i, expected.data[i], actual.data[i]), NCSU_NONE);
        num_fail_count++;
        return;
      end
    end

    // All checks passed
    // Prints PASS lines only for first 192 (Phase A + B + C)
    // num_directed_count tracks those 192 for the summary display
    // num_pass_count tracks all transactions for internal use
    if (directed_phase_active)
    begin
      string data_str;
      if (actual.data.size() == 0) 
      begin
        data_str = "data=<zero-byte>";
      end 
      else if (actual.data.size() == 1) 
      begin
        data_str = $sformatf("data=0x%0h(%0d)", actual.data[0], actual.data[0]);
      end 
      else 
      begin
        // Multi-byte: shows all bytes as [b0 b1 b2 ...]
        data_str = "data=[";
        foreach (actual.data[i]) 
        begin
          data_str = {data_str, $sformatf("0x%02h", actual.data[i])};
          if (i < actual.data.size() - 1)
            data_str = {data_str, " "};
        end
        data_str = {data_str, "]"};
      end

      ncsu_info("i2cmb_scoreboard", $sformatf("PASS [%s]: addr=0x%0h  %s", (actual.op ? "READ " : "WRITE"), actual.addr, data_str), NCSU_NONE);

      num_directed_count++;
    end

    num_pass_count++;

  endfunction

  // Called at the end of the test
  // prints final pass/fail summary to transcript
  function void report();
    if (num_directed_count > 0 || num_fail_count > 0)
    begin
      ncsu_info("i2cmb_scoreboard", "============================================================", NCSU_NONE);
      ncsu_info("i2cmb_scoreboard", $sformatf("SUMMARY: PASS=%0d  FAIL=%0d  TOTAL=%0d", num_directed_count, num_fail_count, (num_directed_count + num_fail_count)), NCSU_NONE);
      ncsu_info("i2cmb_scoreboard", "============================================================", NCSU_NONE);
    end
  endfunction

endclass
