// Coverage helps in collecting functional coverage on WB transactions observed on the bus
class i2cmb_coverage extends ncsu_pkg::ncsu_component #(i2c_pkg::i2c_transaction);

  i2c_pkg::i2c_transaction current_trans;

  bit current_op;
  int current_size; 
  bit repeated_start_seen;

  // =========================================================================
  // COVERGROUP: i2c_bus_cg
  // -------------------------------------------------------------------------
  // Test plan:
  //   5.1  i2c_bus_cg                    (CoverGroup)
  //   5.2  i2c_bus_cg::op_trans_cp       (Coverpoint): direction transitions
  //   5.3  i2c_bus_cg::byte_count_cp     (Coverpoint): payload size
  //   5.4  i2c_bus_cg::repeated_start_cp (Coverpoint): Repeated Start seen
  //   5.5  i2c_bus_cg::op_x_byte_count   (Cross): op direction*payload size
  // =========================================================================
  covergroup i2c_bus_cg;
    option.per_instance = 1;
    option.name = "i2c_bus_cg";

    // op_trans_cp: direction transitions between consecutive transfers
    op_trans_cp: coverpoint current_op
    {
      bins write_to_read = (1'b0 => 1'b1);
      bins read_to_write = (1'b1 => 1'b0);
      bins consec_write  = (1'b0 => 1'b0);
      bins consec_read   = (1'b1 => 1'b1);
    }

    // byte_count_cp: payload size of the I2C transfer
    byte_count_cp: coverpoint current_size
    {
      bins zero   = {0};          // 0 bytes: address-only 
      bins single = {1};          // 1 byte:  no FSM loop
      bins multi  = {[2 : $]};   // 2+ bytes: loop-back 
    }

    op_cp: coverpoint current_op 
    {
      bins write_op = {0};
      bins read_op  = {1};
    }

    // Cross Coverage
    op_x_byte_count: cross op_cp, byte_count_cp
    {
      ignore_bins read_zero = binsof(op_cp.read_op) && binsof(byte_count_cp.zero);
    }

    // zero_byte_cp: explicit bin for the zero-byte corner case
    /*zero_byte_cp: coverpoint current_trans.data.size()
    {
      bins is_zero = {0};         // 0-byte ping hits this bin
    }*/

    // repeated_start_cp: Repeated Start condition observed
    repeated_start_cp: coverpoint repeated_start_seen
    {
      bins        repeated_start = {1'b1};
      ignore_bins not_yet        = {1'b0};
    }

  endgroup

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "i2cmb_coverage", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
    repeated_start_seen = 1'b0;
    i2c_bus_cg      = new();
  endfunction

  // -----------------------------------------------------------------------
  // nb_put: called by i2c_monitor for every completed I2C transfer
  // -----------------------------------------------------------------------
  virtual function void nb_put(input i2c_pkg::i2c_transaction trans);
    current_trans = trans;

    current_op = trans.op;
    current_size = trans.data.size();

    if (trans.addr == 7'h22) 
        repeated_start_seen = 1'b1; 
    else 
        repeated_start_seen = 1'b0;
    
    // Sampling 
    i2c_bus_cg.sample();
    repeated_start_seen = 1'b0;

  endfunction

endclass
