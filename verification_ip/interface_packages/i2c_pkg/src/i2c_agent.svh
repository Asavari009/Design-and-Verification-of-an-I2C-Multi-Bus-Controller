// Agent owns the i2c_driver and i2c_monitor
// Passes shared configuration to both 
// takes the responsibility to run each concurrently
class i2c_agent extends ncsu_pkg::ncsu_component #(i2c_transaction);

  i2c_configuration cfg; // virtual interface handle which is set by environment
  i2c_driver        driver; // drives read responses onto i2c_if
  i2c_monitor       monitor; // observes completed i2c transfers

  // inheriting from the ncsu package which acts like the parent class
  function new(string name = "i2c_agent", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  // Helps in constructing driver and monitor
  // then wires shared config to both
  virtual function void build();
    super.build();
    driver       = new("i2c_driver",  this);
    monitor      = new("i2c_monitor", this);
    driver.cfg   = cfg;
    monitor.cfg  = cfg;
    // building both the driver and monitor for the environment
    driver.build();    
    monitor.build();
  endfunction

  // Driver and monitor runs in parallel 
  virtual task run();
    fork
      driver.run();
      monitor.run();
    join_none
  endtask

endclass