// Monitor helps in observing every completed WB bus transaction and forwards it to the subscriber (predictor) via nb_put()
// Runs forever in background
class wb_monitor extends ncsu_pkg::ncsu_component #(wb_transaction);

  wb_configuration cfg; // virtual interface handle which is set by agent
  ncsu_pkg::ncsu_component #(wb_transaction) subscriber; // predictor which is set by environment
  ncsu_pkg::ncsu_component #(wb_transaction) subscriber2;   // coverage which is set by environment

  // inherits from the ncsu package
  function new(string name = "wb_monitor", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  // Runs forever and it waits for each completed WB transaction
  // packages it into a wb_transaction and then forwards it to the predictor
  virtual task run();
    wb_transaction trans;

    forever 
    begin
      // Creates a fresh transaction object for each observed transfer
      trans = new("wb_mon_trans");

      // Blocking is performed until a WB transaction is completed where it captures addr, data, we
      cfg.wb_vi.master_monitor(trans.addr, trans.data, trans.we);

      // Forwarding it to predictor so it tracks the DUT register writes
      if (subscriber != null)
        subscriber.nb_put(trans);

      // Forwarding it to coverage so it can sample WB transactions
      if (subscriber2 != null) 
	subscriber2.nb_put(trans);
    end

  endtask

endclass