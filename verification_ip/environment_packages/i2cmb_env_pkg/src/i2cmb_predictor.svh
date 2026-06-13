// Predictor watches WB transactions and predicts I2C transfers for the scoreboard.
// All WB-side covergroups defined and sampled here.

class i2cmb_predictor extends ncsu_pkg::ncsu_component #(wb_pkg::wb_transaction);

  // IICMB register addresses
  localparam CSR_ADDR  = 2'h0;
  localparam DPR_ADDR  = 2'h1;
  localparam CMDR_ADDR = 2'h2;
  localparam FSMR_ADDR = 2'h3;

  // IICMB command codes
  localparam CMD_WAIT     = 8'h00;
  localparam CMD_WRITE    = 8'h01;
  localparam CMD_READ_ACK = 8'h02;
  localparam CMD_READ_NAK = 8'h03;
  localparam CMD_START    = 8'h04;
  localparam CMD_STOP     = 8'h05;
  localparam CMD_SET_BUS  = 8'h06;

  // State machine
  typedef enum {
		IDLE,
		GOT_START, 
		COLLECT_WRITE, 
		COLLECT_READ
		} pred_state_t;

  pred_state_t state;

  // Building accumulators for the transaction
  bit [6:0] cur_addr;
  bit       cur_op;
  bit [7:0] cur_dpr;
  bit [7:0] write_bytes[$];
  bit [7:0] read_bytes[$];

  // Shared mailbox: predictor put()s, scoreboard get()s
  // It's created in the environment and assigned before run()
  mailbox #(i2c_pkg::i2c_transaction) expected_mb;

  // Sequence completion flags
  bit write_seq_done;
  bit read_nak_done;
  bit read_ack_done;
  bit wait_cmd_done;      
  bit wait_zero_done;     
  bit core_reset_done;    

  // -----------------------------------------------------------------------
  // task helper variables
  // -----------------------------------------------------------------------
  // i2cmb_ctrl_cg variables
  bit ctrl_don;
  bit ctrl_nak;
  bit ctrl_err;           
  bit ctrl_bc;
  bit ctrl_e;
  bit ctrl_ie;            
  bit ctrl_from_cmdr;
  bit ctrl_from_csr;

  // IRQ inference (5.3)
  bit irq_enabled;
  bit irq_was_generated;

  // DPR tracking for CMD_WAIT zero-duration detection
  bit [7:0] last_dpr;

  bit [3:0] fsmr_state_val;   // holds FSMR[7:4] from most recent FSMR read

  bit start_completed;        
  bit emit_on_recovery_setbus; 
  bit recovery_from_cw;       
  bit [6:0] recovery_addr;    

  // =========================================================================
  // COVERGROUP 1: WB Register Access
  // Test plan:
  //   1.1  wb_reg_access_cg                (CoverGroup)
  //   1.2  wb_reg_access_cg::reg_addr_cp   (Coverpoint)
  //   1.3  wb_reg_access_cg::rw_cp         (Coverpoint)
  //   1.4  wb_reg_access_cg::reg_x_rw      (Cross)
  //   1.5  wb_reg_access_cg::fsmr_fault_cp (Coverpoint)
  // =========================================================================
  covergroup wb_reg_access_cg with function sample(bit [1:0] addr, bit we, bit [7:0] data);
    option.per_instance = 1;
    option.name = "wb_reg_access_cg";

    reg_addr_cp: coverpoint addr
    {
      bins CSR_reg  = {2'h0};
      bins DPR_reg  = {2'h1};
      bins CMDR_reg = {2'h2};
      bins FSMR_reg = {2'h3};
    }

    // Read (WE=0) or write (WE=1)
    rw_cp: coverpoint we
    {
      bins read_access  = {1'b0};
      bins write_access = {1'b1};
    }

    // All 8 (register direction) combinations
    reg_x_rw: cross reg_addr_cp, rw_cp;

    // FSMR[7:4] = byte-level FSM state
    fsmr_fault_cp: coverpoint data[7:4]
                   iff (addr == FSMR_ADDR && !we)
    {
      bins valid_state   = {[4'h0 : 4'h5]};
      bins garbage_state = {[4'h6 : 4'hF]};
    }
  endgroup

  // =======================================================================
  // COVERGROUP 2: CMDR Command Codes
  // =======================================================================
  /*covergroup cmdr_cmd_cg with function sample(bit [2:0] cmd);
    option.per_instance = 1;
    option.name = "cmdr_cmd_cg";

    cmd_cp: coverpoint cmd
    {
      bins CMD_WAIT_bin     = {3'b000};
      bins CMD_WRITE_bin    = {3'b001};
      bins CMD_READ_ACK_bin = {3'b010};
      bins CMD_READ_NAK_bin = {3'b011};
      bins CMD_START_bin    = {3'b100};
      bins CMD_STOP_bin     = {3'b101};
      bins CMD_SET_BUS_bin  = {3'b110};
    }
  endgroup*/

  // =========================================================================
  // COVERGROUP 3: CSR and CMDR Control  (items 2.1 - 2.7)
  // Test plan:
  //   2.1  i2cmb_ctrl_cg                   (CoverGroup)
  //   2.2  i2cmb_ctrl_cg::don_cp           (Coverpoint)
  //   2.3  i2cmb_ctrl_cg::nak_cp           (Coverpoint)
  //   2.4  i2cmb_ctrl_cg::bc_cp            (Coverpoint)
  //   2.5  i2cmb_ctrl_cg::core_disabled_cp (Coverpoint)
  //   2.6  i2cmb_ctrl_cg::err_cp           (Coverpoint)
  //   2.7  i2cmb_ctrl_cg::ie_cp            (Coverpoint)
  // =========================================================================
  covergroup i2cmb_ctrl_cg;
    option.per_instance = 1;
    option.name = "i2cmb_ctrl_cg";

    // DON (CMDR[7]): command-completion handshake
    // done_clear (DON=0) proves the DUT was busy during polling
    // done_set   (DON=1) proves the command completed correctly
    don_cp: coverpoint ctrl_don
            iff (ctrl_from_cmdr)
    {
      bins done_set   = {1'b1};
      bins done_clear = {1'b0};
    }

    // NAK (CMDR[6]): slave acknowledge status
    // Executes only on CMDR reads
    nak_cp: coverpoint ctrl_nak
            iff (ctrl_from_cmdr && !ctrl_nak)
    {
      bins         nak_clear = {1'b0};
      //ignore_bins  nak_never = {1'b1};
    }

    // ERR bit - set by SET_BUS with invalid ID -> exercises mbyte Error state
    err_cp: coverpoint ctrl_err
            iff (ctrl_from_cmdr)
    {
      bins err_clear = {1'b0};
      bins err_set   = {1'b1};
    }

    // BC (CSR[4]): Bus Captured 
    // Executes only on CSR reads
    bc_cp: coverpoint ctrl_bc
           iff (ctrl_from_csr)
    {
      bins not_captured = {1'b0};
      bins captured     = {1'b1};
    }

    // E (CSR[7]): Core Enable bit
    // Executes only on CSR reads
    core_disabled_cp: coverpoint ctrl_e
                      iff (ctrl_from_csr)
    {
      bins disabled = {1'b0};
      bins enabled  = {1'b1};
    }

    // IE bit (CSR[6]) - ie_off before enable, ie_on after enable
    ie_cp: coverpoint ctrl_ie
           iff (ctrl_from_csr)
    {
      bins ie_off = {1'b0};
      bins ie_on  = {1'b1};
    }
  endgroup

  // =========================================================================
  // COVERGROUP 4: Command Sequences  (items 4.1 - 4.7)
  // Test plan:
  //   4.1  cmd_seq_cg                  (CoverGroup)
  //   4.2  cmd_seq_cg::write_seq_cp    (Coverpoint)
  //   4.3  cmd_seq_cg::read_nak_cp     (Coverpoint)
  //   4.4  cmd_seq_cg::read_ack_cp     (Coverpoint)
  //   4.5  cmd_seq_cg::wait_cmd_cp     (Coverpoint)
  //   4.6  cmd_seq_cg::core_reset_cp   (Coverpoint)
  //   4.7  cmd_seq_cg::wait_zero_cp    (Coverpoint)
  // =========================================================================
  covergroup cmd_seq_cg;
    option.per_instance = 1;
    option.name = "cmd_seq_cg";

    write_seq_cp: coverpoint write_seq_done iff (write_seq_done)
    {
      bins        write_complete = {1'b1};
      //ignore_bins seq_not_done   = {1'b0};
    }

    read_nak_cp: coverpoint read_nak_done iff (read_nak_done)
    {
      bins        read_nak_complete = {1'b1};
      //ignore_bins nak_not_done      = {1'b0};
    }

    read_ack_cp: coverpoint read_ack_done iff (read_ack_done)
    {
      bins        read_ack_complete = {1'b1};
      //ignore_bins ack_not_done      = {1'b0};
    }

    // CMD_WAIT issued 
    wait_cmd_cp: coverpoint wait_cmd_done iff (wait_cmd_done)
    {
      bins        wait_complete = {1'b1};
      //ignore_bins wait_not_done = {1'b0};
    }

    // Core disable/re-enable observed mid-test
    core_reset_cp: coverpoint core_reset_done iff (core_reset_done)
    {
      bins        core_reset_seen = {1'b1};
      //ignore_bins not_yet         = {1'b0};
    }

    // CMD_WAIT with DPR=0 
    wait_zero_cp: coverpoint wait_zero_done iff (wait_zero_done)
    {
      bins        wait_zero_complete = {1'b1};
      //ignore_bins zero_not_done      = {1'b0};
    }
  endgroup

  // =========================================================================
  // COVERGROUP 5: IRQ Behavior
  // Test plan:
  //   3.1 irq_behavior_cg              (CoverGroup)
  //   3.2 irq_behavior_cg::irq_gen_cp  (Coverpoint)
  // =========================================================================
  covergroup irq_behavior_cg;
    option.per_instance = 1;
    option.name = "irq_behavior_cg";

    irq_gen_cp: coverpoint irq_was_generated
    {
      bins        irq_generated = {1'b1};
      ignore_bins not_yet       = {1'b0};
    }
  endgroup

  // =========================================================================
  // COVERGROUP 6: Byte FSM State Coverage
  // Testplan:
  //   6.1 byte_fsm_cg                     (CoverGroup)
  //   6.2 byte_fsm_cg::byte_fsm_state_cp  (Coverpoint)_
  //   Tracks all 6 valid mbyte FSM states via FSMR[7:4] reads
  //   Generator calls wb_read(FSMR_ADDR) at 4 strategic moments:
  //     1. Before CMD_SET_BUS in run_core_init()      -> captures s_idle     
  //     2. After  CMD_START written, before wait_don  -> captures s_start     
  //     3. After  wait_don() returns from CMD_START   -> captures s_bus_taken 
  //     4. After  CMD_WRITE written, before wait_don  -> captures s_write     
  // =========================================================================
  covergroup byte_fsm_cg;
    option.per_instance = 1;
    option.name = "byte_fsm_cg";

    byte_fsm_state_cp: coverpoint fsmr_state_val
    {
      bins s_idle         = {4'h0};  // core idle, no transfer in progress
      bins s_start_pend   = {4'h1};  // waiting for I2C bus to become free
      bins s_start        = {4'h3};  // generating START waveform on bus
      bins s_bus_taken    = {4'h5};  // bus captured / byte being written
    }
  endgroup

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "i2cmb_predictor", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
    state             = IDLE;
    write_seq_done    = 1'b0;
    read_nak_done     = 1'b0;
    read_ack_done     = 1'b0;
    wait_cmd_done     = 1'b0;
    wait_zero_done    = 1'b0;
    core_reset_done   = 1'b0;
    irq_enabled       = 1'b0;
    irq_was_generated = 1'b0;
    last_dpr          = 8'h00;
    fsmr_state_val   = 4'h0;
    start_completed        = 1'b0;
    emit_on_recovery_setbus = 1'b0;
    recovery_from_cw       = 1'b0;
    recovery_addr          = 7'h0;

    // Instantiating all covergroups
    wb_reg_access_cg = new();
    //cmdr_cmd_cg      = new();
    i2cmb_ctrl_cg    = new();
    cmd_seq_cg       = new();
    irq_behavior_cg  = new();
    byte_fsm_cg      = new();
  endfunction

  // -----------------------------------------------------------------------
  // nb_put: called by wb_monitor for every WB transaction
  // -----------------------------------------------------------------------
  virtual function void nb_put(input wb_pkg::wb_transaction trans);

    // CG1: sample every WB transaction
    wb_reg_access_cg.sample(trans.addr, trans.we, trans.data);

    // CG6: FSMR read -> capture mbyte FSM state
    if (!trans.we && trans.addr == FSMR_ADDR)
    begin
      fsmr_state_val = trans.data[7:4];
      byte_fsm_cg.sample();
    end

    // Tracks last DPR write
    if (trans.we && trans.addr == DPR_ADDR)
    begin
      cur_dpr  = trans.data;
      last_dpr = trans.data;
    end

    // Tracks IE bit for IRQ inference; track E bit for core_reset detection
    if (trans.we && trans.addr == CSR_ADDR)
    begin
      if (trans.data[6] == 1'b1) irq_enabled = 1'b1;
      else                        irq_enabled = 1'b0;

      if (trans.data[7] == 1'b0)
      begin
        core_reset_done = 1'b1;
        cmd_seq_cg.sample();

        if (state == COLLECT_WRITE)
        begin
          emit_on_recovery_setbus = 1'b1;
    	  recovery_from_cw        = 1'b1;
    	  recovery_addr           = cur_addr;  // save addr before reset
   	  write_bytes.delete();
   	  read_bytes.delete();
  	  state = IDLE;
        end
        else if (state == GOT_START)
        begin
	  emit_on_recovery_setbus = 1'b1;
          if (start_completed)
    	  begin
            recovery_from_cw        = 1'b0;
          end
	  else
	  begin
	    recovery_from_cw  = 1'b1;         // start_pending: use cur_addr
    	    recovery_addr     = cur_addr;
	  end
          start_completed = 1'b0;
    	  write_bytes.delete();
 	  read_bytes.delete();
   	  state = IDLE;
        end

      end
    end

    // CG2: CMDR writes
    //if (trans.we && trans.addr == CMDR_ADDR)
      //cmdr_cmd_cg.sample(trans.data[2:0]);

    // CG3: CMDR read -> DON, NAK, ERR
    if (!trans.we && trans.addr == CMDR_ADDR)
    begin
      ctrl_don       = trans.data[7];
      ctrl_nak       = trans.data[6];
      ctrl_err       = trans.data[4];
      ctrl_from_cmdr = 1'b1;
      ctrl_from_csr  = 1'b0;
      i2cmb_ctrl_cg.sample();

      if (state == GOT_START && ctrl_don)
    	start_completed = 1'b1;

      // infer IRQ generation
      if (irq_enabled && (ctrl_don || ctrl_nak || ctrl_err))
      begin
        irq_was_generated = 1'b1;
        irq_behavior_cg.sample();
      end
    end

    // CG3: CSR read -> BC, E, IE
    if (!trans.we && trans.addr == CSR_ADDR)
    begin
      ctrl_bc        = trans.data[4];
      ctrl_e         = trans.data[7];
      ctrl_ie        = trans.data[6];
      ctrl_from_cmdr = 1'b0;
      ctrl_from_csr  = 1'b1;
      i2cmb_ctrl_cg.sample();
    end

    // CG4 sequence tracking
    if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_READ_NAK)
    begin
      read_nak_done = 1'b1;
      cmd_seq_cg.sample();
    end

    if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_READ_ACK)
    begin
      read_ack_done = 1'b1;
      cmd_seq_cg.sample();
    end

    // CMD_WAIT
    if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_WAIT)
    begin
      wait_cmd_done = 1'b1;
      cmd_seq_cg.sample();
      if (last_dpr == 8'h00)
      begin
        wait_zero_done = 1'b1;
        cmd_seq_cg.sample();
      end
    end

    if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_SET_BUS &&
    state == IDLE && emit_on_recovery_setbus)
    begin
      i2c_pkg::i2c_transaction recovery_pred;
      int ok;
      recovery_pred      = new("recovery_pred");
      recovery_pred.op   = 1'b0;       // always a write context
      recovery_pred.data = new[0];     // 0 bytes (nothing was ACKed)
      if (recovery_from_cw)
        recovery_pred.addr = recovery_addr;      
      else
        recovery_pred.addr = last_dpr[6:0];      
      ok = expected_mb.try_put(recovery_pred);
      if (!ok) 
      begin
        ncsu_info("i2cmb_predictor", "recovery try_put failed", NCSU_NONE);
        $finish;
      end
      emit_on_recovery_setbus = 1'b0;
      recovery_from_cw        = 1'b0;
    end

    //   IDLE          : no transfer in progress, waiting for a START command
    //   GOT_START     : START signal is encountered, waiting for slave address + R/W bit via DPR then CMDR=WRITE
    //   COLLECT_WRITE : master is writing data bytes, accumulating each byte until STOP
    //   COLLECT_READ  : master is reading data bytes, capturing each DPR readback until STOP

    // =======================================================================
    // Prediction state machine
    // =======================================================================
    case (state)

      // ---------------------------------------------------------------
      // IDLE: waiting for a START command
      // ---------------------------------------------------------------
      IDLE:
      begin
        // A write of CMD_START to CMDR signals the beginning of an I2C transfer
        if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_START)
        begin
	  start_completed = 1'b0;
          state = GOT_START;
	end
      end

      // ---------------------------------------------------------------
      // GOT_START: START seen, waiting for DPR (addr+R/W) then CMD_WRITE
      //   1) DPR write  : captures slave address + R/W bit
      //   2) CMDR=WRITE : signals the DUT to transmit the address byte
      // ---------------------------------------------------------------
      GOT_START:
      begin
        if (trans.we && trans.addr == DPR_ADDR)
          // generator loads the slave address + R/W bit into DPR
          cur_dpr = trans.data;
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_WRITE)
        begin
          // CMDR=WRITE transmits the address byte on the I2C bus
          // Extracting the 7-bit slave address from bits [7:1]
          cur_addr = cur_dpr[7:1];
          // Extracting the operation that it's performing: bit[0] = 0 means write, 1 means read
          cur_op   = cur_dpr[0];
          // Clearing the accumulators 
          write_bytes.delete();
          read_bytes.delete();
          // Branching it based on direction
          state = (cur_op == 1'b0) ? COLLECT_WRITE : COLLECT_READ;
        end
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_START)
          state = GOT_START;
      end

      // ---------------------------------------------------------------
      // COLLECT_WRITE: master is sending data bytes to the slave
      // It gets DPR=data, then CMDR=WRITE
      // ---------------------------------------------------------------
      COLLECT_WRITE:
      begin
        if (trans.we && trans.addr == DPR_ADDR)
          // Generator loads the next data byte into DPR 
          cur_dpr = trans.data;
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_WRITE)
          write_bytes.push_back(cur_dpr);
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_STOP)
        begin
          emit_prediction();
          write_seq_done = 1'b1;
          cmd_seq_cg.sample();
          state = IDLE;
        end
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_START)
        begin
          emit_prediction();
          write_bytes.delete();
          read_bytes.delete();
          state = GOT_START;
        end
      end

      // ---------------------------------------------------------------
      // COLLECT_READ: capturing read bytes from DPR readbacks until STOP
      // ---------------------------------------------------------------
      COLLECT_READ:
      begin
        if (!trans.we && trans.addr == DPR_ADDR)
          read_bytes.push_back(trans.data);
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_STOP)
        begin
          emit_prediction();
          state = IDLE;
        end
        else if (trans.we && trans.addr == CMDR_ADDR && trans.data == CMD_START)
          state = GOT_START;
      end

    endcase
  endfunction

  // It helps in building the predicted transaction and puts it into the shared mailbox
  local function void emit_prediction();
    i2c_pkg::i2c_transaction predicted;
    int ok;

    predicted      = new("predicted_trans");
    predicted.addr = cur_addr;
    predicted.op   = cur_op;

    if (cur_op == 1'b0)
    begin
      predicted.data = new[write_bytes.size()];
      foreach (write_bytes[i]) predicted.data[i] = write_bytes[i];
    end

    else
    begin
      predicted.data = new[read_bytes.size()];
      foreach (read_bytes[i]) predicted.data[i] = read_bytes[i];
    end

    // pushing the prediction into the mailbox
    ok = expected_mb.try_put(predicted);

    if (!ok)
    begin
      ncsu_info("i2cmb_predictor", "mailbox try_put failed unexpectedly", NCSU_NONE);
      $finish;
    end

    begin
      string dbg_str;
      dbg_str = predicted.convert2string();  
    end   

  endfunction

endclass
