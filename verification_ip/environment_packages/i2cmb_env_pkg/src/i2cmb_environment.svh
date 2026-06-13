// Environment helps in instantiating and wiring up all verification components
// Environment contains wb_agent, i2c_agent, i2cmb coverage, i2cmb_predictor and i2cmb_scoreboard

class i2cmb_environment extends ncsu_pkg::ncsu_component #(wb_pkg::wb_transaction);

  // creating the objects for environment configuration, wb_agent and i2c_agent
  i2cmb_env_configuration  env_cfg;

  wb_pkg::wb_agent         wb_agent;

  i2c_pkg::i2c_agent       i2c_agent;

  // creating objects for i2cmb predictor, scoreboard and coverage
  i2cmb_predictor          predictor;
  i2cmb_scoreboard         scoreboard;
  i2cmb_coverage           coverage;

  // Shared mailbox: predictor put()s predictions, scoreboard get()s them
  mailbox #(i2c_pkg::i2c_transaction) expected_mb;

  function new(string name = "i2cmb_environment", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build();
    super.build();

    // Created a shared mailbox 
    expected_mb = new();

    // Building the agents
    wb_agent  = new("wb_agent",  this);
    i2c_agent = new("i2c_agent", this);
    wb_agent.cfg  = env_cfg.wb_config;
    i2c_agent.cfg = env_cfg.i2c_config;
    wb_agent.build();
    i2c_agent.build();

    // Building the environment-level components
    predictor  = new("i2cmb_predictor",  this);
    scoreboard = new("i2cmb_scoreboard", this);
    coverage   = new("i2cmb_coverage",   this);
    predictor.build();
    scoreboard.build();
    coverage.build();

    // Wiring wb_monitor -> predictor
    wb_agent.monitor.subscriber = predictor;

    // Scoreboard and coverage both receive every i2c_transaction
    i2c_agent.monitor.add_subscriber(coverage);
    i2c_agent.monitor.add_subscriber(scoreboard);

    // Giving the predictor and scoreboard the shared mailbox
    // Predictor puts() into it, scoreboard gets() from it
    predictor.expected_mb  = expected_mb;
    scoreboard.expected_mb = expected_mb;
  endfunction

  // executing the run tasks
  virtual task run();
    fork
      i2c_agent.run();
      wb_agent.run();
    join_none
  endtask

endclass
