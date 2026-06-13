// Transaction represents a single complete I2C transfer (one write or one read)
// Created by the generator for pre-loading responses, and by the monitor when it observes a completed transfer on the bus
class i2c_transaction extends ncsu_pkg::ncsu_transaction;

  bit [6:0] addr; // 7-bit slave address
  bit       op; // 0 = write, 1 = read
  bit [7:0] data []; // dynamic array 

  function new(string name = "i2c_transaction");
    super.new(name);
  endfunction

  // Returns a readable summary of the transaction by converting to string 
  virtual function string convert2string();
    string s;
    s = $sformatf("I2C_TRANS: addr=0x%0h op=%s bytes=%0d", addr, (op ? "READ":"WRITE"), data.size());
    foreach (data[i])
      s = {s, $sformatf(" data[%0d]=0x%0h(%0d)", i, data[i], data[i])};
    return s;
  endfunction

endclass