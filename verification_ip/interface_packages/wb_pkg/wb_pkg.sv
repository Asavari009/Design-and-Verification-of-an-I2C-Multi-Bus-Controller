package wb_pkg;

  // importing the ncsu package
  import ncsu_pkg::*;

  // including files like wb_configuration, wb_agent, wb_driver, wb_monitor, wb_transaction inside the wishbone package
  `include "src/wb_transaction.svh"
  `include "src/wb_configuration.svh"
  `include "src/wb_driver.svh"
  `include "src/wb_monitor.svh"
  `include "src/wb_agent.svh"

endpackage