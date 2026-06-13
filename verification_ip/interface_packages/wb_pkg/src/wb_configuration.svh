// Configuration helps in holding the virtual interface handle for the wb_if
// It's created in i2cmb_env_configuration and is passed down to wb_driver and wb_monitor
class wb_configuration extends ncsu_pkg::ncsu_configuration;

  // Virtual interface handle that is connected to the wb_if in top.sv
  virtual wb_if #(.ADDR_WIDTH(2), .DATA_WIDTH(8)) wb_vi;

  function new(string name = "wb_configuration");
    super.new(name);
  endfunction

endclass