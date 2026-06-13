// Agent owns the wb_driver and wb_monitor
// Shared configuration is passed to both files during build operation
// Only the monitor runs in the background 
// the driver is called directly by the generator via bl_put() 
class wb_agent extends ncsu_pkg::ncsu_component #(wb_transaction);

  wb_configuration cfg; // virtual interface handle which is set by environment
  wb_driver        driver; // drives WB register reads and writes
  wb_monitor       monitor; // observes all WB bus transactions

  // inherits from the ncsu package
  function new(string name = "wb_agent", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  // This function helps in constructs driver and monitor
  // then wires shared config to both
  virtual function void build();
    super.build();
    driver        = new("wb_driver",  this);
    monitor       = new("wb_monitor", this);
    driver.cfg    = cfg;
    monitor.cfg   = cfg;
    // building both driver and monitor for the environment
    driver.build();    
    monitor.build();
  endfunction

  // Only the monitor task runs continuously 
  virtual task run();
    monitor.run();
  endtask

endclass