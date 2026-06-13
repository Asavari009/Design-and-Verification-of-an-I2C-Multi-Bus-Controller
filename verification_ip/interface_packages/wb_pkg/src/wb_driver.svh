// Driver helps in executing the WB bus transactions in the place of the generator
// via bl_put() calls it directly where it executes blocking until the transaction completes
class wb_driver extends ncsu_pkg::ncsu_component #(wb_transaction);

  wb_configuration cfg; // virtual interface handle that is set by agent

  // inherits from the ncsu package
  function new(string name = "wb_driver", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  // Receives a wb_transaction from the generator and drives it onto the bus
  // we = 1 is write to DUT register, we = 0 which is read from DUT register
  virtual task bl_put(input wb_transaction trans);
    if (trans.we)
      cfg.wb_vi.master_write(trans.addr, trans.data); // drives addr+data where it waits for ack
    else
      cfg.wb_vi.master_read(trans.addr, trans.data); // drives addr and captures data from DUT
  endtask

endclass