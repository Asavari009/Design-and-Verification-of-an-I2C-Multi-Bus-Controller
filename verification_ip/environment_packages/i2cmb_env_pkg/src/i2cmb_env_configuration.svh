// Top-level configuration holds both wb and i2c configuration objects
// Created in i2cmb_test and passed down to the environment
class i2cmb_env_configuration extends ncsu_pkg::ncsu_configuration;

  wb_pkg::wb_configuration   wb_config; // holds wb_if virtual interface handle
  i2c_pkg::i2c_configuration i2c_config; // holds i2c_if virtual interface handle

  // implementing the configuration for wb and i2c
  function new(string name = "i2cmb_env_configuration");
    super.new(name);
    wb_config  = new("wb_config");
    i2c_config = new("i2c_config");
  endfunction

  // Returns a readable summary
  virtual function string convert2string();
    return $sformatf("i2cmb_env_configuration: %s", name);
  endfunction

endclass
