`timescale 1ns / 10ps

interface i2c_if #(int I2C_ADDR_WIDTH = 7, int I2C_DATA_WIDTH = 8)
  (
    input  tri    scl,
    inout  triand sda
  );

  // ---- open-drain SDA driver ------------------------------------
  logic sda_out;
  initial sda_out = 1'b1;
  assign sda = sda_out ? 1'bz : 1'b0;

  // ===========================================================================
  // send_ack  
  // ===========================================================================
  task send_ack();
    @(negedge scl);
    sda_out = 1'b0;
    @(negedge scl);
    sda_out = 1'b1;
  endtask

  // ===========================================================================
  // sample_addr  
  // ===========================================================================
  task sample_addr(output bit [I2C_ADDR_WIDTH-1:0] addr_out);
    for (int b = I2C_ADDR_WIDTH-1; b >= 0; b--) 
    begin
      @(posedge scl);
      addr_out[b] = sda;
    end
  endtask

  // ===========================================================================
  // Task 1 : wait_for_i2c_transfer
  // ===========================================================================
  task wait_for_i2c_transfer(
    output bit                         op,
    output bit [I2C_DATA_WIDTH-1:0]    write_data [],
    output bit                         repeated_start_detected   
  );
    bit [I2C_ADDR_WIDTH-1:0]  addr_bits;
    bit [I2C_DATA_WIDTH-1:0]  byte_temp_q[$];
    bit [I2C_DATA_WIDTH-1:0]  byte_received;
    bit                       stop_found;

    byte_temp_q.delete();
    repeated_start_detected = 1'b0;

    // ---- wait for the opening START condition --------------------------------
    @(negedge sda iff scl === 1'b1);

    // ---- outer fork: normal processing vs. repeated-start abort -------------
    fork : wfit_outer
      // PART A: normal address + data path
      begin : normal_path
        sample_addr(addr_bits);
        @(posedge scl);
        op = sda;          // R/W bit
        send_ack();        // ACK the address

        if (op == 1'b0) begin   // WRITE transfer: collects bytes until STOP
          stop_found = 1'b0;
          while (!stop_found) begin
            fork : byte_fork
              begin : get_byte
                repeat (I2C_DATA_WIDTH) 
                begin
                  @(posedge scl);
                  byte_received = {byte_received[I2C_DATA_WIDTH-2:0], sda};
                end
                byte_temp_q.push_back(byte_received);
                send_ack();
              end
              begin : check_stop
                // STOP = SDA rises while SCL is high
                @(posedge sda iff scl === 1'b1);
                stop_found = 1'b1;
              end
            join_any
            disable byte_fork;
          end
        end
        // READ transfer falls through immediately so caller can call
        // provide_read_data()
      end

      // PART B: repeated-start watcher -> acts when the SDA is falling while SCL high
      begin : rstart_watcher
        @(negedge sda iff scl === 1'b1);
        repeated_start_detected = 1'b1;
      end
    join_any
    disable wfit_outer;

    // Releases SDA in case send_ack() was killed mid-execution
    sda_out = 1'b1;

    write_data = new[byte_temp_q.size()](byte_temp_q);
  endtask

  // ===========================================================================
  // Task 1b : wait_for_address_phase
  // ===========================================================================
  task wait_for_address_phase(
    output bit                         op,
    output bit [I2C_DATA_WIDTH-1:0]    write_data [],
    output bit                         repeated_start_detected
  );
    bit [I2C_ADDR_WIDTH-1:0]  addr_bits;
    bit [I2C_DATA_WIDTH-1:0]  byte_temp_q[$];
    bit [I2C_DATA_WIDTH-1:0]  byte_received;
    bit                       stop_found;

    byte_temp_q.delete();
    repeated_start_detected = 1'b0;

    // NO start-edge waiting here 
    fork : wfap_outer
      begin : normal_path2
        sample_addr(addr_bits);
        @(posedge scl);
        op = sda;
        send_ack();

        if (op == 1'b0) 
	begin
          stop_found = 1'b0;
          while (!stop_found) 
	  begin
            fork : byte_fork2
              begin : get_byte2
                repeat (I2C_DATA_WIDTH) 
		begin
                  @(posedge scl);
                  byte_received = {byte_received[I2C_DATA_WIDTH-2:0], sda};
                end
                byte_temp_q.push_back(byte_received);
                send_ack();
              end
              begin : check_stop2
                @(posedge sda iff scl === 1'b1);
                stop_found = 1'b1;
              end
            join_any
            disable byte_fork2;
          end
        end
      end

      begin : rstart_watcher2
        @(negedge sda iff scl === 1'b1);
        repeated_start_detected = 1'b1;
      end
    join_any
    disable wfap_outer;

    sda_out = 1'b1;
    write_data = new[byte_temp_q.size()](byte_temp_q);
  endtask

  // ===========================================================================
  // Task 2 : provide_read_data  
  // ===========================================================================
  task provide_read_data(
    input  bit [I2C_DATA_WIDTH-1:0]   read_data [],
    output bit                        transfer_completed
  );
    int  byte_count;
    int  bit_index;
    bit  master_nack;

    transfer_completed = 1'b0;
    byte_count          = 0;

    while (byte_count < read_data.size()) 
    begin
      for (bit_index = 0; bit_index < I2C_DATA_WIDTH; bit_index++) 
      begin
        if (byte_count != 0 || bit_index != 0)
          @(negedge scl);
        sda_out = read_data[byte_count][7 - bit_index];
      end

      @(negedge scl);
      sda_out     = 1'b1;
      @(posedge scl);
      master_nack = (sda === 1'b1);

      byte_count++;

      if (master_nack) 
      begin
        transfer_completed = 1'b1;
        break;
      end
    end

    @(posedge sda iff scl === 1'b1);
    transfer_completed = 1'b1;
  endtask

  // ===========================================================================
  // Task 3 : monitor 
  // ===========================================================================
  task monitor(
    output bit [I2C_ADDR_WIDTH-1:0]   addr,
    output bit                         op,
    output bit [I2C_DATA_WIDTH-1:0]   data [],
    output bit                         repeated_start_detected   
  );
    bit [I2C_DATA_WIDTH-1:0]  observed_temp_q[$];
    bit [I2C_DATA_WIDTH-1:0]  observed_byte;
    bit                       stop_found;

    observed_temp_q.delete();
    repeated_start_detected = 1'b0;

    @(negedge sda iff scl === 1'b1);   // wait for START

    fork : mon_outer
      begin : mon_normal_path
        sample_addr(addr);
        @(posedge scl); op = sda;
        @(posedge scl);   // skip ACK passively

        stop_found = 1'b0;
        while (!stop_found) 
	begin
          fork : mon_byte_fork
            begin : obs_byte_thread
              repeat (I2C_DATA_WIDTH) 
	      begin
                @(posedge scl);
                observed_byte = {observed_byte[I2C_DATA_WIDTH-2:0], sda};
              end
              observed_temp_q.push_back(observed_byte);
              @(posedge scl);   // skipping ACK/NACK passively
            end
            begin : obs_stop_thread
              @(posedge sda iff scl === 1'b1);
              stop_found = 1'b1;
            end
          join_any
          disable mon_byte_fork;
        end
      end

      // Repeated-start watcher for the monitor
      begin : mon_rstart_watcher
        @(negedge sda iff scl === 1'b1);
        repeated_start_detected = 1'b1;
      end
    join_any
    disable mon_outer;

    data = new[observed_temp_q.size()](observed_temp_q);
  endtask

  // ===========================================================================
  // Task 3b : monitor_from_address
  //  Called by i2c_monitor after monitor() returns with repeated_start_detected
  // ===========================================================================
  task monitor_from_address(
    output bit [I2C_ADDR_WIDTH-1:0]   addr,
    output bit                         op,
    output bit [I2C_DATA_WIDTH-1:0]   data [],
    output bit                         repeated_start_detected
  );
    bit [I2C_DATA_WIDTH-1:0]  observed_temp_q[$];
    bit [I2C_DATA_WIDTH-1:0]  observed_byte;
    bit                       stop_found;

    observed_temp_q.delete();
    repeated_start_detected = 1'b0;

    fork : mfa_outer
      begin : mfa_normal_path
        sample_addr(addr);
        @(posedge scl); op = sda;
        @(posedge scl);   // skipping ACK passively

        stop_found = 1'b0;
        while (!stop_found) 
	begin
          fork : mfa_byte_fork
            begin : mfa_obs_byte_thread
              repeat (I2C_DATA_WIDTH) 
	      begin
                @(posedge scl);
                observed_byte = {observed_byte[I2C_DATA_WIDTH-2:0], sda};
              end
              observed_temp_q.push_back(observed_byte);
              @(posedge scl);
            end
            begin : mfa_obs_stop_thread
              @(posedge sda iff scl === 1'b1);
              stop_found = 1'b1;
            end
          join_any
          disable mfa_byte_fork;
        end
      end

      begin : mfa_rstart_watcher
        @(negedge sda iff scl === 1'b1);
        repeated_start_detected = 1'b1;
      end
    join_any
    disable mfa_outer;

    data = new[observed_temp_q.size()](observed_temp_q);
  endtask

endinterface
