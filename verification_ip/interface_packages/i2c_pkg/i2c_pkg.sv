package i2c_pkg;

  // importing the ncsu package
  import ncsu_pkg::*;

  // including i2c_configuration, i2c_agent, i2c_driver, i2c_monitor, i2c_transaction files under the i2c package
  `include "src/i2c_transaction.svh"
  `include "src/i2c_configuration.svh"
  `include "src/i2c_driver.svh"
  `include "src/i2c_monitor.svh"
  `include "src/i2c_agent.svh"

endpackage