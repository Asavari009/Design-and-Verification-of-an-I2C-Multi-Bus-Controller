// Monitor observes the completed I2C transfers on the bus and then forwards
// them to all registered subscribers

class i2c_monitor extends ncsu_pkg::ncsu_component #(i2c_transaction);

  i2c_configuration cfg;

  ncsu_pkg::ncsu_component #(i2c_transaction) subscribers[$];

  function new(string name = "i2c_monitor", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  function void add_subscriber(ncsu_pkg::ncsu_component #(i2c_transaction) sub);
    subscribers.push_back(sub);
  endfunction

  // ---------------------------------------------------------------------------
  // Package observed signals into a transaction and notify all subscribers
  // ---------------------------------------------------------------------------
  local function void report_transaction(
    input bit [6:0] addr,
    input bit       op,
    input bit [7:0] data []
  );
    i2c_transaction trans;
    trans      = new("i2c_mon_trans");
    trans.addr = addr;
    trans.op   = op;
    trans.data = data;
    foreach (subscribers[i])
      subscribers[i].nb_put(trans);
  endfunction

  // ---------------------------------------------------------------------------
  // run() -> forever loop handling normal and repeated-start transactions
  // ---------------------------------------------------------------------------
  virtual task run();
    bit [6:0] mon_addr;
    bit       mon_op;
    bit [7:0] mon_data[];
    bit       rstart;          // set when Repeated START is detected

    forever 
    begin
      // --- first segment: waiting for opening START ----------------------------
      rstart = 1'b0;
      cfg.i2c_vi.monitor(mon_addr, mon_op, mon_data, rstart);   
      report_transaction(mon_addr, mon_op, mon_data);

      // --- subsequent segments after a Repeated START -----------------------
      while (rstart) 
      begin
        rstart = 1'b0;
        cfg.i2c_vi.monitor_from_address(mon_addr, mon_op, mon_data, rstart);  
        report_transaction(mon_addr, mon_op, mon_data);
      end
    end
  endtask

endclass
