// Top-level test 
// is the entry point for the entire testbench
// Retrieves virtual interfaces from ncsu_config_db, builds the environment, and launches the test flow
class i2cmb_test extends ncsu_pkg::ncsu_component #(wb_pkg::wb_transaction);

  i2cmb_env_configuration  test_cfg;   // holds wb and i2c virtual interface handles
  i2cmb_environment        env;        // contains all agents and verification components
  i2cmb_generator          generator;  

  function new(string name = "i2cmb_test", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build();
    super.build();

    // Create environment configuration and retrieves the virtual interfaces
    test_cfg = new("i2cmb_env_cfg");
    
    // checking for the condition if ncsu package can't retrive wb_if
    if (!ncsu_pkg::ncsu_config_db #(virtual wb_if #(2,8))::get("wb_vi", test_cfg.wb_config.wb_vi))
    begin
      $display("i2cmb_test: could not get wb_vi from ncsu_config_db");
      $finish;
    end

    // checking for the condition if ncsu package can't retrive i2c_if
    if (!ncsu_pkg::ncsu_config_db #(virtual i2c_if #(7,8))::get("i2c_vi", test_cfg.i2c_config.i2c_vi))
    begin
      $display("i2cmb_test: could not get i2c_vi from ncsu_config_db");
      $finish;
    end

    // It builds the environment and passes the configuration down
    env         = new("i2cmb_environment", this);
    env.env_cfg = test_cfg;
    env.build();

    generator          = new("i2cmb_generator", this);
    generator.wb_drv   = env.wb_agent.driver;
    generator.i2c_drv  = env.i2c_agent.driver;
    generator.build();
    generator.scbd     = env.scoreboard;

  endfunction

  // Environment's run task is executed
  virtual task run();

    // -----------------------------------------------------------------------
    // Calls convert2string()
    // -----------------------------------------------------------------------
    begin
      string dbg_str;
      dbg_str = test_cfg.convert2string();
    end

    env.run();
    generator.run();
    env.scoreboard.report();
  endtask

endclass
