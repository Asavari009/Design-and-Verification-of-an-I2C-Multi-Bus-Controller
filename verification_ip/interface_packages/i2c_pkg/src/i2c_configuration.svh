// Configuration holds the virtual interface handle for the i2c_if
// Created within the i2cmb_env_configuration and passed down to driver and monitor
class i2c_configuration extends ncsu_pkg::ncsu_configuration;

  // Virtual interface handle is connected to the i2c_if in top.sv
  virtual i2c_if #(.I2C_ADDR_WIDTH(7), .I2C_DATA_WIDTH(8)) i2c_vi;

  function new(string name = "i2c_configuration");
    super.new(name);
  endfunction

endclass