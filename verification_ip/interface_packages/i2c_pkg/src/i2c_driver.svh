// Driver pre-loads with read responses by the generator before the test starts
// It waits for I2C transfers on the bus 
// responds to reads during the simulation

class i2c_driver extends ncsu_pkg::ncsu_component #(i2c_transaction);

  i2c_configuration cfg;
  i2c_transaction   read_queue[$];

  function new(string name = "i2c_driver", ncsu_pkg::ncsu_component_base parent = null);
    super.new(name, parent);
  endfunction

  // Generator calls this to pre-load read responses before test starts
  // Write transactions (op=0) are silently ignored
  virtual task bl_put(input i2c_transaction trans);
    if (trans.op == 1'b1)
      read_queue.push_back(trans);
  endtask

  // ---------------------------------------------------------------------------
  // Handles one I2C segment (address + data) 
  // ---------------------------------------------------------------------------
  local task handle_segment(input bit op, input bit [7:0] write_data[]);
    bit           transfer_complete;
    i2c_transaction resp;

    if (op == 1'b1) 
    begin
      // READ transfer: pop next preloaded response
      if (read_queue.size() == 0)
        $display("I2C_DRIVER ERROR: read request with no queued data!");
      else begin
        resp = read_queue.pop_front();
        cfg.i2c_vi.provide_read_data(resp.data, transfer_complete);
      end
    end
    // WRITE transfer: nothing to drive back to master
  endtask

  // ---------------------------------------------------------------------------
  // run() -> forever loop that handles normal and repeated-start transactions
  // ---------------------------------------------------------------------------
  virtual task run();
    bit           op;
    bit [7:0]     write_data[];
    bit           rstart;        

    forever 
    begin
      // --- first segment: waits for the opening START condition ---------------
      rstart = 1'b0;
      cfg.i2c_vi.wait_for_i2c_transfer(op, write_data, rstart);  
      handle_segment(op, write_data);

      while (rstart) 
      begin
        rstart = 1'b0;
        cfg.i2c_vi.wait_for_address_phase(op, write_data, rstart);  
        handle_segment(op, write_data);
      end
    end
  endtask

endclass
