package i2cmb_env_pkg;
  // importing the three packages - i2c, ncsu and wb
  import ncsu_pkg::*;
  import wb_pkg::*;
  import i2c_pkg::*;

  // including the files i2cmb_test, i2cmb_generator, i2cmb_env_configuration, i2cmb_environment,
  // i2cmb_predictor, i2cmb_scoreboard, i2cmb_coverage under the i2cmb environment
  `include "src/i2cmb_env_configuration.svh"
  `include "src/i2cmb_predictor.svh"
  `include "src/i2cmb_coverage.svh"
  `include "src/i2cmb_scoreboard.svh"
  `include "src/i2cmb_generator.svh"
  `include "src/i2cmb_environment.svh"
  `include "src/i2cmb_test.svh"

endpackage