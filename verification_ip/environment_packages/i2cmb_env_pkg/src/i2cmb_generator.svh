// Generator helps in implementing the test flow using wb_transactions and i2c_transactions
// Pre-loads read responses into i2c_driver
// Drives the DUT via wb_driver using wb_transactions

//  run_probe_transfer()         bc_cp::captured, core_disabled_cp::enabled
//  run_zero_byte()              byte_count_cp::zero
//  run_two_byte_read()          read_ack_cp, byte_count_cp::multi(R)
//  i2c_write_multi()            byte_count_cp::multi(W)
//  CSR read after SET_BUS       ie_cp::ie_on, core_disabled_cp::enabled
//  run_random_phase()           code coverage - diverse stimulus per seed
//  run_fsmr_wait_test()         fsmr_fault_cp::garbage_state, wait_cmd_cp
//  run_bus1_test()              err_cp::err_set
//  run_core_disable_test()      core_reset_cp, regblock write suppression
//  run_wait_zero_test()         wait_zero_cp, zero-duration edge case
//  run_repeated_start()         s_rstart_a/b/c in mbit, mbyte s_bus_taken->s_start
//  run_cmdr_busy_write()    
//  run_disable_in_start_pending()
//  run_disable_in_bus_taken()
//  run_disable_in_write()    

// TEST BRANCHING via +TESTNAME plusarg (7 unique scenarios):
//   i2cmb_test_directed     
//   i2cmb_test_disable_fsm  
//   i2cmb_test_rstart   
//   i2cmb_test_multi_bus    
//   i2cmb_test_random_write -> core init + 20 WRITE-ONLY random transactions
//   i2cmb_test_random_read  -> core init + 20 READ-ONLY  random transactions
//   i2cmb_test_random_mixed -> core init + 20 MIXED      random transactions (W+R)

class i2cmb_generator extends ncsu_pkg::ncsu_component #(wb_pkg::wb_transaction);

  // Handles to agents set by environment after build
  wb_pkg::wb_driver   wb_drv;
  i2c_pkg::i2c_driver i2c_drv;
  i2cmb_scoreboard     scbd;

  // Slave address used in all I2C transfers
  localparam bit [6:0] SLAVE_ADDR = 7'h22;

  // IICMB register addresses
  localparam bit [1:0] CSR_ADDR  = 2'h0;
  localparam bit [1:0] DPR_ADDR  = 2'h1;
  localparam bit [1:0] CMDR_ADDR = 2'h2;
  localparam bit [1:0] FSMR_ADDR = 2'h3;

  // IICMB command bytes
  localparam bit [7:0] CMD_WAIT     = 8'h00;
  localparam bit [7:0] CMD_WRITE    = 8'h01;
  localparam bit [7:0] CMD_READ_ACK = 8'h02;
  localparam bit [7:0] CMD_READ_NAK = 8'h03;
  localparam bit [7:0] CMD_START    = 8'h04;
  localparam bit [7:0] CMD_STOP     = 8'h05;
  localparam bit [7:0] CMD_SET_BUS  = 8'h06;

  // Number of random transactions
  localparam int NUM_RAND_TRANS = 20;

  bit [6:0] plan_addr [NUM_RAND_TRANS];
  bit       plan_op   [NUM_RAND_TRANS];
  int       plan_bc   [NUM_RAND_TRANS];
  bit [7:0] plan_data [NUM_RAND_TRANS][4];

  // inheriting from the ncsu package
  function new(string name = "i2cmb_generator", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  // -----------------------------------------------------------------------
  // Task for writing a WB register
  // -----------------------------------------------------------------------
  task wb_write(input bit [1:0] addr, input bit [7:0] data);

    wb_pkg::wb_transaction t = new("wb_wr");
    t.addr = addr;
    t.data = data;
    t.we = 1'b1;
    wb_drv.bl_put(t);

  endtask

  // -----------------------------------------------------------------------
  // Task for reading a WB register
  // returns value in data
  // -----------------------------------------------------------------------
  task wb_read(input bit [1:0] addr, output bit [7:0] data);

    wb_pkg::wb_transaction t = new("wb_rd");
    t.addr = addr;
    t.data = 8'h00;
    t.we = 1'b0;
    wb_drv.bl_put(t);
    data = t.data;

  endtask

  // -----------------------------------------------------------------------
  // This task helps poll CMDR until DON bit (bit 7) is set
  // -----------------------------------------------------------------------
  task wait_don();

    bit [7:0] r;
    do wb_read(CMDR_ADDR, r);
    while (r[7:4] == 4'b0000);

  endtask

  // =======================================================================
  //   Enables the core (E=1, IE=1) and selects bus 0
  // =======================================================================
  task run_core_init();

    wb_write(CSR_ADDR,  8'hC0);   // E=1, IE=1
    wb_write(DPR_ADDR,  8'h00);   // selects bus 0
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();

  endtask

  // =======================================================================
  // DIRECTED I2C TRANSFER 
  // =======================================================================

  // -----------------------------------------------------------------------
  // I2C write: START -> addr+W -> data -> STOP
  // -----------------------------------------------------------------------
  task i2c_write_byte(input bit [6:0] saddr, input bit [7:0] data);

    wb_write(CMDR_ADDR, CMD_START); // CMDR = START
    wait_don();
    wb_write(DPR_ADDR,  {saddr, 1'b0}); // DPR = addr + W bit
    wb_write(CMDR_ADDR, CMD_WRITE); // CMDR = WRITE (transmit address)       
    wait_don();
    wb_write(DPR_ADDR,  data); // DPR = data byte
    wb_write(CMDR_ADDR, CMD_WRITE); // CMDR = WRITE (transmit data)      
    wait_don();
    wb_write(CMDR_ADDR, CMD_STOP); // CMDR = STOP        
    wait_don();

  endtask

  // -----------------------------------------------------------------------
  // I2C read: START -> addr+R -> READ_NAK -> read DPR -> STOP
  // -----------------------------------------------------------------------
  task i2c_read_byte(input bit [6:0] saddr, output bit [7:0] data);

    wb_write(CMDR_ADDR, CMD_START); // CMDR = START        
    wait_don();
    wb_write(DPR_ADDR,  {saddr, 1'b1}); // DPR = addr + R bit
    wb_write(CMDR_ADDR, CMD_WRITE); // CMDR = WRITE (transmit address)        
    wait_don();
    wb_write(CMDR_ADDR, CMD_READ_NAK); // CMDR = READ_NAK    
    wait_don();
    wb_read(DPR_ADDR, data); // DPR = received byte captured
    wb_write(CMDR_ADDR, CMD_STOP); // CMDR = STOP       
    wait_don();

  endtask

  // Zero-byte transfer
  // No data written -> hits zero_byte_cp
  task run_zero_byte();

    wb_write(CMDR_ADDR, CMD_START);       
    wait_don();
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);       
    wait_don();
    wb_write(CMDR_ADDR, CMD_STOP);        
    wait_don();  // 0 data bytes

  endtask

  // 2-byte read: READ_ACK for byte 0, READ_NAK for byte 1
  task run_two_byte_read();

    bit [7:0] b0, b1;
    wb_write(CMDR_ADDR, CMD_START);      
    wait_don();
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b1});
    wb_write(CMDR_ADDR, CMD_WRITE);        
    wait_don();
    wb_write(CMDR_ADDR, CMD_READ_ACK);     
    wait_don();  // hits read_ack_cp
    wb_read(DPR_ADDR,   b0);
    wb_write(CMDR_ADDR, CMD_READ_NAK);    
    wait_don();
    wb_read(DPR_ADDR,   b1);
    wb_write(CMDR_ADDR, CMD_STOP);        
    wait_don();

  endtask

  // -----------------------------------------------------------------------
  // N-byte write in one START-STOP transaction
  // Used for byte_count_cp::multi and large_packet bins
  // -----------------------------------------------------------------------
  task i2c_write_multi(input bit [6:0] saddr, input bit [7:0] data[], input int n);

    wb_write(CMDR_ADDR, CMD_START);       
    wait_don();
    wb_write(DPR_ADDR,  {saddr, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);       
    wait_don();
    for (int i = 0; i < n; i++)
    begin
      wb_write(DPR_ADDR,  data[i]);
      wb_write(CMDR_ADDR, CMD_WRITE);     
      wait_don();
    end
    wb_write(CMDR_ADDR, CMD_STOP);         
    wait_don();

  endtask

  task i2c_read_multi(input bit [6:0] saddr, input int n);

    bit [7:0] rv;
    wb_write(CMDR_ADDR, CMD_START);      
    wait_don();
    wb_write(DPR_ADDR,  {saddr, 1'b1});
    wb_write(CMDR_ADDR, CMD_WRITE);      
    wait_don();
    for (int i = 0; i < n - 1; i++) 
    begin
      wb_write(CMDR_ADDR, CMD_READ_ACK);   
      wait_don();
      wb_read(DPR_ADDR, rv);
    end
    wb_write(CMDR_ADDR, CMD_READ_NAK);    
    wait_don();
    wb_read(DPR_ADDR, rv);
    wb_write(CMDR_ADDR, CMD_STOP);        
    wait_don();

  endtask

  // =======================================================================
  // Probe transfer
  //   CSR read while bus captured -> bc_cp::captured, core_disabled_cp::enabled
  // =======================================================================
  task run_probe_transfer();

      bit [7:0] csr_val, fsmr_val;
      ncsu_info("i2cmb_generator", "--- Probe (CSR read while BC=1) ---", NCSU_NONE);

      wb_write(CMDR_ADDR, CMD_START);
      // READ FSMR immediately after CMD_START written, before wait_don():
      // mbyte is mid-START-generation -> FSMR[7:4] = s_start or s_start_pending
      wb_read(FSMR_ADDR, fsmr_val);   // hits byte_fsm_state_cp::s_start or s_start_pend
      wait_don();

      wb_read(CSR_ADDR, csr_val);     // existing CSR probe read (bc_cp::captured)

      // READ FSMR after wait_don() returns from CMD_START:
      // mbyte is now in s_bus_taken 
      wb_read(FSMR_ADDR, fsmr_val);   // hits byte_fsm_state_cp::s_bus_taken

      wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
      wb_write(CMDR_ADDR, CMD_WRITE);
      // READ FSMR immediately after CMD_WRITE written, before wait_don():
      // mbyte is mid-byte-clock -> FSMR[7:4] = s_write
      wb_read(FSMR_ADDR, fsmr_val);   // hits byte_fsm_state_cp::s_write
      wait_don();

      wb_write(DPR_ADDR,  8'hDE);
      wb_write(CMDR_ADDR, CMD_WRITE);
      wait_don();
      wb_write(CMDR_ADDR, CMD_STOP);
      wait_don();

  endtask

  // =======================================================================
  // WB FEC Coverage task
  // =======================================================================
  task run_wb_fec_coverage();

    ncsu_info("i2cmb_generator", "--- WB FEC: Independent stb/cyc stimulus (all 4 addrs, R+W) ---", NCSU_NONE);

    // Iterating over all 4 WB register addresses: CSR=0, DPR=1, CMDR=2, FSMR=3
    for (int a = 0; a < 4; a++) 
    begin
      bit [1:0] addr = bit'(a);

      // Write path (we=1): FEC stb_i and cyc_i terms
      wb_drv.cfg.wb_vi.master_cyc_only(addr, 1'b1);  // cyc=1, stb=0, we=1
      wb_drv.cfg.wb_vi.master_stb_only(addr, 1'b1);  // cyc=0, stb=1, we=1

      // Read path (we=0): FEC stb_i and cyc_i terms
      wb_drv.cfg.wb_vi.master_cyc_only(addr, 1'b0);  // cyc=1, stb=0, we=0
      wb_drv.cfg.wb_vi.master_stb_only(addr, 1'b0);  // cyc=0, stb=1, we=0
    end

  endtask

  // =======================================================================
  // FSMR garbage_state (item 1.5) + wait_cmd_cp (item 4.5)
  // =======================================================================
  task run_fsmr_wait_test();

    bit [7:0] fsmr_val;
    ncsu_info("i2cmb_generator", "--- CMD_WAIT(1ms) -> FSMR garbage_state ---", NCSU_NONE);
    wb_write(DPR_ADDR,  8'h01);
    wb_write(CMDR_ADDR, CMD_WAIT);
    wb_read(FSMR_ADDR, fsmr_val);
    wait_don();
    ncsu_info("i2cmb_generator", $sformatf("  FSMR during WAIT = 0x%02h  [7:4]=0x%0h", fsmr_val, fsmr_val[7:4]), NCSU_NONE);
 
  endtask

  // =======================================================================
  // Bus-1 test (err_cp item 2.6)
  // =======================================================================
  task run_bus1_test();

    bit [7:0] cmdr_val;
    ncsu_info("i2cmb_generator", "--- SET_BUS(1) for err_cp ---", NCSU_NONE);
    wb_write(DPR_ADDR,  8'h01);
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();
    wb_read(CMDR_ADDR, cmdr_val);
    ncsu_info("i2cmb_generator", $sformatf("  SET_BUS(1) CMDR=0x%02h DON=%0b ERR=%0b", cmdr_val, cmdr_val[7], cmdr_val[4]), NCSU_NONE);
    if (cmdr_val[4] == 1'b1)
    begin
      // ERR path: re-enable and return to bus 0
      wb_write(CSR_ADDR,  8'hC0);
      wb_write(DPR_ADDR,  8'h00);
      wb_write(CMDR_ADDR, CMD_SET_BUS);
      wait_don();
    end 
    else 
    begin
      // Done: transfer on bus 1, return to bus 0
      wb_write(CMDR_ADDR, CMD_START);
      wait_don();
      wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
      wb_write(CMDR_ADDR, CMD_WRITE);
      wait_don();
      wb_write(DPR_ADDR,  8'hB1);
      wb_write(CMDR_ADDR, CMD_WRITE);
      wait_don();
      wb_write(CMDR_ADDR, CMD_STOP);
      wait_don();
      wb_write(DPR_ADDR,  8'h00);
      wb_write(CMDR_ADDR, CMD_SET_BUS);
      wait_don();
    end

  endtask

  // =======================================================================
  // Core Disable / Re-enable test
  // =======================================================================
  task run_core_disable_test();

    bit [7:0] csr_val;
    ncsu_info("i2cmb_generator", "--- Core Disable/Re-enable (core_reset_cp) ---", NCSU_NONE);

    // Step 1: Disable core (E=0)
    wb_write(CSR_ADDR, 8'h00);

    // Step 2: Read CSR while E=0 -> core_disabled_cp::disabled
    wb_read(CSR_ADDR, csr_val);
    ncsu_info("i2cmb_generator", $sformatf("  CSR while disabled = 0x%02h  E=%0b", csr_val, csr_val[7]), NCSU_NONE);

    // Step 3: Write DPR while E=0
    wb_write(DPR_ADDR, 8'hFF);

    // Step 4: Re-enable (E=1, IE=1)
    wb_write(CSR_ADDR, 8'hC0);

    // Step 5: Verifying if DPR was suppressed
    wb_read(DPR_ADDR, csr_val);
    ncsu_info("i2cmb_generator", $sformatf("  DPR after re-enable = 0x%02h (expect 0x00 if suppressed)", csr_val), NCSU_NONE);

    // Step 6: Re-select bus 0
    wb_write(DPR_ADDR,  8'h00);
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();

    ncsu_info("i2cmb_generator", "  Core re-enabled, bus 0 selected", NCSU_NONE);

  endtask

  // =======================================================================
  // Zero-duration CMD_WAIT
  // =======================================================================
  task run_wait_zero_test();

    ncsu_info("i2cmb_generator", "--- CMD_WAIT(0ms) zero-duration edge case ---", NCSU_NONE);
    wb_write(DPR_ADDR,  8'h00);
    wb_write(CMDR_ADDR, CMD_WAIT);
    wait_don();
    ncsu_info("i2cmb_generator", "  CMD_WAIT(0) completed", NCSU_NONE);

  endtask

  // =======================================================================
  // 6a: run_random_write_phase
  //   20 WRITE-ONLY random transactions (op=0 forced)
  // =======================================================================
  task run_random_write_phase();

    int   roll;
    int i, j;
    ncsu_info("i2cmb_generator", $sformatf("--- Random WRITE phase: %0d write-only transactions ---", NUM_RAND_TRANS), NCSU_NONE);
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      plan_addr[i] = 7'($urandom_range(1, 127));
      plan_op[i]   = 1'b0;   // forced write
      roll = $urandom_range(0, 4);
      if      (roll == 0) plan_bc[i] = 0;
      else if (roll <= 2) plan_bc[i] = 1;
      else                plan_bc[i] = $urandom_range(2, 4);
      for (j = 0; j < plan_bc[i]; j++)
        plan_data[i][j] = 8'($urandom());
    end
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      ncsu_info("i2cmb_generator", $sformatf("  rand[%02d] addr=0x%02h op=WR bc=%0d", i, plan_addr[i], plan_bc[i]), NCSU_NONE);
      wb_write(CMDR_ADDR, CMD_START);
      wait_don();
      wb_write(DPR_ADDR,  {plan_addr[i], 1'b0});
      wb_write(CMDR_ADDR, CMD_WRITE);
      wait_don();
      for (j = 0; j < plan_bc[i]; j++)
      begin
        wb_write(DPR_ADDR,  plan_data[i][j]);
        wb_write(CMDR_ADDR, CMD_WRITE);
        wait_don();
      end
      wb_write(CMDR_ADDR, CMD_STOP);
      wait_don();
    end
    ncsu_info("i2cmb_generator", "  Random WRITE phase complete.", NCSU_NONE);

  endtask

  // =======================================================================
  // 6b: run_random_read_phase
  //   20 READ-ONLY random transactions (op=1 forced, bc>=1)
  // =======================================================================
  task run_random_read_phase();

    i2c_pkg::i2c_transaction preload_t;
    bit [7:0] ideal;
    int   roll;
    int i, j;
    ncsu_info("i2cmb_generator", $sformatf("--- Random READ phase: %0d read-only transactions ---", NUM_RAND_TRANS), NCSU_NONE);
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      plan_addr[i] = 7'($urandom_range(1, 127));
      plan_op[i]   = 1'b1;   // forced read
      roll = $urandom_range(0, 4);
      plan_bc[i]   = (roll <= 2) ? 1 : $urandom_range(2, 4);  // bc >= 1 for reads
      for (j = 0; j < plan_bc[i]; j++)
        plan_data[i][j] = 8'($urandom());
    end
    // Preload all read responses into i2c driver queue
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      preload_t       = new("rnd_rd");
      preload_t.op    = 1'b1;
      preload_t.data  = new[plan_bc[i]];
      for (j = 0; j < plan_bc[i]; j++)
        preload_t.data[j] = plan_data[i][j];
      i2c_drv.bl_put(preload_t);
    end
    // Executing all reads and print each one (unique per seed)
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      ncsu_info("i2cmb_generator", $sformatf("  rand[%02d] addr=0x%02h op=RD bc=%0d", i, plan_addr[i], plan_bc[i]), NCSU_NONE);
      if (plan_bc[i] == 1) i2c_read_byte(plan_addr[i], ideal);
      else                  i2c_read_multi(plan_addr[i], plan_bc[i]);
    end
    ncsu_info("i2cmb_generator", "  Random READ phase complete.", NCSU_NONE);

  endtask

  // =======================================================================
  // 6c: run_random_mixed_phase
  //   20 MIXED random transactions (writes AND reads)
  // =======================================================================
  task run_random_mixed_phase();

    i2c_pkg::i2c_transaction preload_t;
    int   roll;
    bit [7:0] ideal;
    int i, j;
    ncsu_info("i2cmb_generator", $sformatf("--- Random MIXED phase: %0d transactions (writes+reads) ---", NUM_RAND_TRANS), NCSU_NONE);
    // Plan all transactions
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      plan_addr[i] = 7'($urandom_range(1, 127));
      plan_op[i]   = bit'($urandom_range(0, 1));
      roll = $urandom_range(0, 4);
      if      (roll == 0) plan_bc[i] = 0;
      else if (roll <= 2) plan_bc[i] = 1;
      else                plan_bc[i] = $urandom_range(2, 4);
      if (plan_op[i] == 1'b1 && plan_bc[i] == 0)
        plan_bc[i] = 1;   // reads need at least 1 byte
      for (j = 0; j < plan_bc[i]; j++)
        plan_data[i][j] = 8'($urandom());
    end
    // Preload read responses
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      if (plan_op[i] == 1'b1)
      begin
        preload_t       = new("rnd_rd");
        preload_t.op    = 1'b1;
        preload_t.data  = new[plan_bc[i]];
        for (j = 0; j < plan_bc[i]; j++)
          preload_t.data[j] = plan_data[i][j];
        i2c_drv.bl_put(preload_t);
      end
    end
    // Execute all transactions and print each one (unique per seed)
    for (i = 0; i < NUM_RAND_TRANS; i++)
    begin
      ncsu_info("i2cmb_generator", $sformatf("  rand[%02d] addr=0x%02h op=%s bc=%0d", i, plan_addr[i], (plan_op[i] ? "RD" : "WR"), plan_bc[i]),
        NCSU_NONE);
      if (plan_op[i] == 1'b0)
      begin
        wb_write(CMDR_ADDR, CMD_START);
        wait_don();
        wb_write(DPR_ADDR,  {plan_addr[i], 1'b0});
        wb_write(CMDR_ADDR, CMD_WRITE);
        wait_don();
        for (j = 0; j < plan_bc[i]; j++)
        begin
          wb_write(DPR_ADDR,  plan_data[i][j]);
          wb_write(CMDR_ADDR, CMD_WRITE);
          wait_don();
        end
        wb_write(CMDR_ADDR, CMD_STOP);
        wait_don();
      end
      else
      begin
        if (plan_bc[i] == 1) i2c_read_byte(plan_addr[i], ideal);
        else                  i2c_read_multi(plan_addr[i], plan_bc[i]);
      end
    end
    ncsu_info("i2cmb_generator", "  Random MIXED phase complete.", NCSU_NONE);

  endtask

  // =======================================================================
  // Predictor FEC Coverage task
  // =======================================================================
  task run_predictor_fec_coverage();

    bit [7:0] ideal;
    ncsu_info("i2cmb_generator", "--- Predictor FEC: non-CMDR addr coverage in all FSM states ---", NCSU_NONE);

    // -------------------------------------------------------------------
    // Part A: FSMR write in GOT_START 
    //         FSMR write in COLLECT_WRITE
    // -------------------------------------------------------------------
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();  // IDLE -> GOT_START

    // FSMR write while predictor is in GOT_START:
    wb_write(FSMR_ADDR, 8'h00);                    // GOT_START, addr=3, we=1

    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});        // GOT_START 
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();  // GOT_START

    // FSMR write while predictor is in COLLECT_WRITE:
    wb_write(FSMR_ADDR, 8'h00);                    // COLLECT_WRITE, addr=3, we=1

    wb_write(DPR_ADDR,  8'hCC);                    
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();  
    wb_write(CMDR_ADDR, CMD_STOP); 
    wait_don();  

    // -------------------------------------------------------------------
    // Part B: FSMR write in COLLECT_READ 
    // -------------------------------------------------------------------
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();  // IDLE -> GOT_START
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b1});        // GOT_START
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();  // GOT_START

    // FSMR write while predictor is in COLLECT_READ:
    wb_write(FSMR_ADDR, 8'h00);                    // COLLECT_READ, addr=3, we=1

    wb_write(CMDR_ADDR, CMD_READ_NAK);
    wait_don(); // COLLECT_READ -> read 1 byte with NACK
    wb_read(DPR_ADDR,  ideal);                      // reads the returned byte
    wb_write(CMDR_ADDR, CMD_STOP);
    wait_don();  // COLLECT_READ -> IDLE

  endtask   

  // =======================================================================
  // PRELOAD for directed phases
  // =======================================================================
  task preload_directed_responses();

    i2c_pkg::i2c_transaction t;

    // -----------------------------------------------------------------------
    // ideal WRITE preload 
    // -----------------------------------------------------------------------
    t      = new("ideal_wr");
    t.op   = 1'b0;            // write 
    t.data = new[0];
    i2c_drv.bl_put(t);        

    // -----------------------------------------------------------------------
    // 1-byte read preload for run_predictor_fec_coverage() Part B
    // -----------------------------------------------------------------------
    t         = new("fec_pred_rd");
    t.op      = 1'b1;
    t.data    = new[1];
    t.data[0] = 8'hDD;
    i2c_drv.bl_put(t);

    // Phase B: 32 reads, data from 100 to 131
    for (int i = 0; i < 32; i++)
    begin
      t         = new("rd_b");
      t.op      = 1'b1;
      t.data    = new[1];
      t.data[0] = 8'd100 + i[7:0];
      i2c_drv.bl_put(t);
    end

    // Phase C: 64 transfers, reads from 63 down to 0 and writes from 64 to 127
    for (int i = 0; i < 64; i++) begin
      t         = new("rd_c");
      t.op      = 1'b1;
      t.data    = new[1];
      t.data[0] = 8'd63 - i[7:0];
      i2c_drv.bl_put(t);
    end

    t         = new("rd_2b");
    t.op      = 1'b1;
    t.data    = new[2];
    t.data[0] = 8'hF0;
    t.data[1] = 8'hF1;
    i2c_drv.bl_put(t);

  endtask

  // =======================================================================
  // DIRECTED PHASES
  // =======================================================================

  // -----------------------------------------------------------------------
  // Phase A: 32 consecutive writes
  // Hits: i2c_seq_cg::consec_write - 31 back-to-back write pairs
  // -----------------------------------------------------------------------
  task run_write_phase();

    $display("");
    ncsu_info("i2cmb_generator", "---------- Starting 32 WRITES (data 0-31) ----------", NCSU_NONE);
    for (int i = 0; i < 32; i++)
      i2c_write_byte(SLAVE_ADDR, i[7:0]);

  endtask

  // -----------------------------------------------------------------------
  // Phase B: 32 consecutive reads
  // Hits: i2c_seq_cg::consec_read - 31 back-to-back read pairs
  //       i2c_seq_cg::write_to_read - at A or B boundary
  // -----------------------------------------------------------------------
  task run_read_phase();

    bit [7:0] rv;
    $display("");
    ncsu_info("i2cmb_generator", "---------- Starting 32 READS (data 100-131) ----------", NCSU_NONE);
    for (int i = 0; i < 32; i++)
      i2c_read_byte(SLAVE_ADDR, rv);

  endtask

  // -----------------------------------------------------------------------
  // Phase C: 64 alternating write then read
  //   Writes: data 64-127    
  //   Reads: slave returns 63 down to 0
  //   Hits: i2c_seq_cg::read_to_write (R->W) - at B or C boundary and within C
  //         i2c_seq_cg::write_to_read (W->R) - within C
  // -----------------------------------------------------------------------
  task run_alternating_phase();

    bit [7:0] rv;
    $display("");
    ncsu_info("i2cmb_generator", "---------- Starting 64 ALTERNATING TRANSFERS ----------", NCSU_NONE);
    for (int i = 0; i < 64; i++) 
    begin
      i2c_write_byte(SLAVE_ADDR, 8'(64 + i));
      i2c_read_byte (SLAVE_ADDR, rv);
    end

  endtask

  // =======================================================================
  // run_repeated_start()
  // =======================================================================
  task run_repeated_start();

    localparam bit [6:0] RSTART_ADDR = 7'h44;
    ncsu_info("i2cmb_generator", "--- Repeated START (s_rstart_a/b/c in mbit) ---", NCSU_NONE);

    // ---- Segment 1: write address byte + one data byte --------------------
    wb_write(CMDR_ADDR, CMD_START); 
    wait_don();
    // predictor: IDLE -> GOT_START

    wb_write(DPR_ADDR,  {RSTART_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);     
    wait_don();
    // predictor: GOT_START -> COLLECT_WRITE

    wb_write(DPR_ADDR,  8'hAB);
    wb_write(CMDR_ADDR, CMD_WRITE);     
    wait_don();
    // predictor: COLLECT_WRITE stays

    // ---- Repeated START: issued while mbyte is in s_bus_taken -------------
    //   mbyte: s_bus_taken -> s_start
    //   mbit:  -> s_rstart_a -> s_rstart_b -> s_rstart_c
    wb_write(CMDR_ADDR, CMD_START);  
    wait_don();

    // ---- Segment 2: write address byte + one data byte --------------------
    // predictor: GOT_START
    wb_write(DPR_ADDR,  {RSTART_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);    
    wait_don();
    // predictor: COLLECT_WRITE

    wb_write(DPR_ADDR,  8'hCD);
    wb_write(CMDR_ADDR, CMD_WRITE);      
    wait_don();

    wb_write(CMDR_ADDR, CMD_STOP);      
    wait_don();
    // predictor: COLLECT_WRITE -> IDLE

    ncsu_info("i2cmb_generator", "  Repeated START complete", NCSU_NONE);

  endtask

  // =======================================================================
  // run_cmdr_busy_write()
  // =======================================================================
  task run_cmdr_busy_write();

    ncsu_info("i2cmb_generator", "--- CMDR write while DON=0 ---", NCSU_NONE);

    // Step 1: CMD_START
    wb_write(CMDR_ADDR, CMD_START);
    // predictor: IDLE -> GOT_START

    // Step 2: write CMD_WAIT to CMDR 
    wb_write(CMDR_ADDR, CMD_WAIT);  

    // Step 3: waits for CMD_START to finish 
    wait_don();

    // Step 4: completes the transaction cleanly so DUT + predictor stay in sync
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);     
    wait_don();
    // predictor: GOT_START -> COLLECT_WRITE

    wb_write(DPR_ADDR,  8'hBC);
    wb_write(CMDR_ADDR, CMD_WRITE);     
    wait_don();

    wb_write(CMDR_ADDR, CMD_STOP);        
    wait_don();
    // predictor: COLLECT_WRITE -> IDLE

    ncsu_info("i2cmb_generator", "  CMDR busy-write test complete", NCSU_NONE);

  endtask

  // =======================================================================
  // run_disable_in_start_pending()
  // =======================================================================
  task run_disable_in_start_pending();

    bit [7:0] ideal;
    ncsu_info("i2cmb_generator", "--- Disable in s_start_pending -> s_idle ---", NCSU_NONE);
    wb_write(CMDR_ADDR, CMD_START);
    wb_read(FSMR_ADDR, ideal);
    wb_read(FSMR_ADDR, ideal);
    wb_read(FSMR_ADDR, ideal);
    wb_write(CSR_ADDR,  8'h00);  // E=0 -> s_rst -> s_start_pending -> s_idle
    wb_write(CSR_ADDR,  8'hC0);
    wb_write(DPR_ADDR,  8'h00);
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();
    ncsu_info("i2cmb_generator", "  Disable-in-start_pending complete", NCSU_NONE);

  endtask

  // =======================================================================
  // run_disable_in_bus_taken()
  // =======================================================================
  task run_disable_in_bus_taken();

    ncsu_info("i2cmb_generator", "--- Disable in s_bus_taken -> s_idle ---", NCSU_NONE);
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();   // waits until CMD_START completes: mbyte is now in s_bus_taken
    wb_write(CSR_ADDR,  8'h00);       // s_rst -> mbyte: s_bus_taken -> s_idle
    wb_write(CSR_ADDR,  8'hC0);
    wb_write(DPR_ADDR,  8'h00);
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();
    ncsu_info("i2cmb_generator", "  Disable-in-bus_taken complete", NCSU_NONE);

  endtask

  // =======================================================================
  // run_disable_in_write()
  // =======================================================================
  task run_disable_in_write();

    ncsu_info("i2cmb_generator", "--- Disable in s_write -> s_idle ---", NCSU_NONE);
    // Setup: get into COLLECT_WRITE
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();  // s_idle -> s_start_pending -> s_bus_taken
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();  // s_bus_taken -> s_write -> s_bus_taken (addr)
    wb_write(DPR_ADDR,  8'hEE);
    wb_write(CMDR_ADDR, CMD_WRITE);   // mbyte: s_bus_taken -> s_write (data byte starts)
    wb_write(CSR_ADDR,  8'h00);
    wb_write(CSR_ADDR,  8'hC0);
    wb_write(DPR_ADDR,  8'h00);
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();
    ncsu_info("i2cmb_generator", "  Disable-in-write complete", NCSU_NONE);

  endtask

  // =======================================================================
  // run_rstart_from_got_start()
  // =======================================================================
  task run_rstart_from_got_start();

    ncsu_info("i2cmb_generator", "--- CMD_START in GOT_START ---", NCSU_NONE);
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();   // IDLE -> GOT_START
    // Second CMD_START before writing DPR address byte:
    // predictor sees CMD_START while in GOT_START
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();   // GOT_START -> GOT_START via rstart
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();
    wb_write(DPR_ADDR,  8'hA5);
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();
    wb_write(CMDR_ADDR, CMD_STOP);
    wait_don();
    ncsu_info("i2cmb_generator", "  rstart-from-GOT_START complete", NCSU_NONE);

  endtask

  // =======================================================================
  // run_rstart_from_collect_read()
  // =======================================================================
  task run_rstart_from_collect_read();

    ncsu_info("i2cmb_generator", "--- CMD_START in COLLECT_READ ---", NCSU_NONE);
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();   // IDLE -> GOT_START
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b1});         // read direction
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();   // GOT_START -> COLLECT_READ
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();   // COLLECT_READ -> rstart
    wb_write(DPR_ADDR,  {SLAVE_ADDR, 1'b0});
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();
    wb_write(DPR_ADDR,  8'hB6);
    wb_write(CMDR_ADDR, CMD_WRITE);
    wait_don();
    wb_write(CMDR_ADDR, CMD_STOP);
    wait_don();
    ncsu_info("i2cmb_generator", "  rstart-from-COLLECT_READ complete", NCSU_NONE);

  endtask

  // =======================================================================
  // DYNAMIC FSM INTERRUPT
  // Uses direct interface handles to synchronize with the I2C bus state
  // =======================================================================
  task run_dynamic_fsm_interrupt(int bit_number);
  
    ncsu_info("i2cmb_generator", $sformatf("--- Dynamic FSM Interrupt (Bit %0d) ---", bit_number), NCSU_NONE);
    
    if (scbd != null) scbd.suppress_warnings = 1;

    // 1. Initiating a write transfer
    wb_write(CMDR_ADDR, CMD_START);
    wait_don();
    wb_write(DPR_ADDR, 8'hAA); 
    wb_write(CMDR_ADDR, CMD_WRITE);

    // 2. Waiting for the specific I2C bit pulse
    repeat(bit_number) @(posedge i2c_drv.cfg.i2c_vi.scl);

    // 3. Waiting for SCL to fall (the middle/low phase of the bit)
    @(negedge i2c_drv.cfg.i2c_vi.scl);
    
    // 4. Synchronizing to the Wishbone clock 
    repeat(5) @(posedge wb_drv.cfg.wb_vi.clk_i); 

    // 5. Strike: Disable the core (CSR Register, Bit 7 = 0)
    wb_write(CSR_ADDR, 8'h00);

    // 6. Recovery: Re-enable for the next part of the test
    #1000ns;
    wb_write(CSR_ADDR, 8'hC0); 
    wb_write(CMDR_ADDR, CMD_SET_BUS);
    wait_don();

    if (scbd != null) scbd.suppress_warnings = 0;
	
  endtask

  // =======================================================================
  // TOP-LEVEL run()
  // =======================================================================
  virtual task run();

    string test_name;
    bit [7:0] ideal_data;
    bit [7:0] mdata[3];
    i2c_pkg::i2c_transaction t;

    // Reads the test name from the plusarg set by regress.sh
    if (!$value$plusargs("TESTNAME=%s", test_name))
      test_name = "i2cmb_test_directed";

    ncsu_info("i2cmb_generator", $sformatf("=== TEST: %s  seed=%0d ===", test_name, $get_initial_random_seed()), NCSU_NONE);

    // ===================================================================
    // i2cmb_test_directed  (seed 1)
    //   ALL directed changes (1-12, 16, 17) + Phase A (32W)/B (32R)/C (64alt)
    //   Fully deterministic
    //   Establishes complete directed coverage
    // ===================================================================
    if (test_name == "i2cmb_test_directed")
    begin
      preload_directed_responses();

      // Pre-enable reads (before core is on)
      wb_write(FSMR_ADDR, 8'hFF);
      wb_read(FSMR_ADDR,  ideal_data);
      wb_read(CSR_ADDR,   ideal_data);
      wb_read(DPR_ADDR,   ideal_data);
      wb_read(CMDR_ADDR,  ideal_data);
      run_wb_fec_coverage();

      run_core_init();               

      // Addition 5: CSR read after enable
      wb_read(CSR_ADDR, ideal_data);

      run_fsmr_wait_test();          
      run_wait_zero_test();          
      run_probe_transfer();          
      run_zero_byte();               
      run_bus1_test();               
      run_core_disable_test();       
      run_disable_in_start_pending(); 

      run_disable_in_bus_taken();    
      run_disable_in_write();        
      run_predictor_fec_coverage();  
      run_repeated_start();          
      run_cmdr_busy_write();         
     
      if (scbd != null) scbd.directed_phase_active = 1; // starts counting
      run_write_phase();             // Phase A: 32 writes
      run_read_phase();              // Phase B: 32 reads
      run_alternating_phase();       // Phase C: 64 alt
      if (scbd != null) scbd.directed_phase_active = 0; // stops counting

      run_two_byte_read();           

      mdata[0] = 8'hA1; mdata[1] = 8'hA2; mdata[2] = 8'hA3;
      i2c_write_multi(SLAVE_ADDR, mdata, 3);  

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_directed ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // i2cmb_test_disable_fsm  (seed 777)
    //   Core init + mid-transfer disable tests only 
    //   Tests mbyte state transitions to s_idle under core disable
    // ===================================================================
    if (test_name == "i2cmb_test_disable_fsm")
    begin
      run_core_init();               
      run_fsmr_wait_test();          
      run_wait_zero_test();          
      run_core_disable_test();       
      run_disable_in_start_pending(); 

      run_disable_in_bus_taken();    
      run_disable_in_write();        

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_disable_fsm ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // i2cmb_test_rstart  (seed 42)
    //   Core init + repeated START scenarios only
    //   Tests mbit s_rstart_a/b/c, mbyte s_bus_taken->s_start
    // ===================================================================
    if (test_name == "i2cmb_test_rstart")
    begin
      run_core_init();
      run_repeated_start();          

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_rstart ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // i2cmb_test_multi_bus  (seed 2025)
    //   Core init + directed transfers across multiple bus addresses
    //   Exercises:
    //     - Multi-byte write on bus 0 to diverse slave addresses
    //     - Single-byte read on bus 0
    //     - SET_BUS(1) error path (bus does not exist -> err_cp::err_set)
    //     - Recovery back to bus 0
    //   Coverage: diverse addr bins, op_cp, byte_count multi, err_cp
    // ===================================================================
    if (test_name == "i2cmb_test_multi_bus")
    begin
      bit [7:0] rv;
      bit [7:0] mb_data[3];

      // Preload reads the test will issue
      i2c_pkg::i2c_transaction mb_t;
      mb_t        = new("mb_rd1");
      mb_t.op     = 1'b1;
      mb_t.data   = new[1];
      mb_t.data[0] = 8'hBB;
      i2c_drv.bl_put(mb_t);

      mb_t        = new("mb_rd2");
      mb_t.op     = 1'b1;
      mb_t.data   = new[1];
      mb_t.data[0] = 8'hCC;
      i2c_drv.bl_put(mb_t);

      run_core_init();

      // 1. Multi-byte write to slave 0x11 (diverse addr, multi bc)
      mb_data[0] = 8'hA1; mb_data[1] = 8'hA2; mb_data[2] = 8'hA3;
      i2c_write_multi(7'h11, mb_data, 3);

      // 2. Single-byte write to slave 0x55
      i2c_write_byte(7'h55, 8'hFF);

      // 3. Single-byte read from slave 0x33
      i2c_read_byte(7'h33, rv);

      // 4. Multi-byte write to slave 0x7F (max addr)
      mb_data[0] = 8'h01; mb_data[1] = 8'h02;
      i2c_write_multi(7'h7F, mb_data, 2);

      // 5. Single-byte read from slave 0x44
      i2c_read_byte(7'h44, rv);

      // 6. SET_BUS(1) -> exercises err_cp::err_set
      run_bus1_test();

      // 7. Zero-byte write to slave 0x22 (hits zero_byte bin)
      run_zero_byte();

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_multi_bus ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // i2cmb_test_random_write  (seed 1234)
    //   Core init + 20 WRITE-ONLY random transactions
    //   No preloads needed (writes only)
    //   Log: every rand[00..19] shows op=WR with seed-unique addr/bc
    // ===================================================================
    if (test_name == "i2cmb_test_random_write")
    begin
      run_core_init();

      if (scbd != null) scbd.directed_phase_active = 1;               
      run_random_write_phase();
      if (scbd != null) scbd.directed_phase_active = 0;

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_random_write ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // i2cmb_test_random_read  (seed 5678)
    //   Core init + 20 READ-ONLY random transactions
    //   Preloads managed inline in run_random_read_phase()
    //   Log: every rand[00..19] shows op=RD with seed-unique addr/bc
    // ===================================================================
    if (test_name == "i2cmb_test_random_read")
    begin
      run_core_init();

      if (scbd != null) scbd.directed_phase_active = 1;               
      run_random_read_phase();
      if (scbd != null) scbd.directed_phase_active = 0;

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_random_read ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // i2cmb_test_random_mixed  (seed 9999)
    //   Core init + 20 MIXED random transactions (writes AND reads)
    //   Read preloads managed inline in run_random_mixed_phase()
    //   Log: rand[00..19] show mix of op=WR/op=RD, all seed-unique
    // ===================================================================
    if (test_name == "i2cmb_test_random_mixed")
    begin
      run_core_init();   

      if (scbd != null) scbd.directed_phase_active = 1;            
      run_random_mixed_phase();
      if (scbd != null) scbd.directed_phase_active = 0;

      ncsu_info("i2cmb_generator", "=== DONE: i2cmb_test_random_mixed ===", NCSU_NONE);
      return;
    end

    // ===================================================================
    // DEFAULT fallback
    //   Runs full directed + random_mixed so coverage is not lost
    // ===================================================================
    ncsu_info("i2cmb_generator", $sformatf("  Unknown TESTNAME='%s' - running full flow as fallback", test_name), NCSU_NONE);
    
    preload_directed_responses();
    
    wb_write(FSMR_ADDR, 8'hFF);

    wb_read(FSMR_ADDR,  ideal_data);
    wb_read(CSR_ADDR,   ideal_data);
    wb_read(DPR_ADDR,   ideal_data);
    wb_read(CMDR_ADDR,  ideal_data);

    run_wb_fec_coverage();
    run_core_init();

    wb_read(CSR_ADDR, ideal_data);

    run_fsmr_wait_test();
    run_wait_zero_test();
    run_probe_transfer();
    run_zero_byte();
    run_bus1_test();
    run_core_disable_test();

    run_disable_in_start_pending();
    run_disable_in_bus_taken();
    run_disable_in_write();

    run_rstart_from_got_start();
    run_rstart_from_collect_read();

    run_predictor_fec_coverage();
    run_repeated_start();
    run_cmdr_busy_write();

    if (scbd != null) scbd.directed_phase_active = 1;
    run_write_phase();
    run_read_phase();
    run_alternating_phase();
    if (scbd != null) scbd.directed_phase_active = 0;

    run_two_byte_read();

    mdata[0] = 8'hA1; mdata[1] = 8'hA2; mdata[2] = 8'hA3;
    i2c_write_multi(SLAVE_ADDR, mdata, 3);

    run_random_mixed_phase();
    ncsu_info("i2cmb_generator", "=== DONE: full coverage flow ===", NCSU_NONE);

  endtask

endclass
