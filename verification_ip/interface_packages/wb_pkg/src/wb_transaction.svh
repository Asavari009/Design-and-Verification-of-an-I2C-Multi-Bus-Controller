// Transaction represents a single completed WB bus transfer (one read or one write)
// generator creates it when driving the DUT
// and by the monitor when it observes a completed transfer on the WB bus
class wb_transaction extends ncsu_pkg::ncsu_transaction;

  bit [1:0] addr; // 2-bit register address (CSR=0, DPR=1, CMDR=2)
  bit [7:0] data; // 8-bit data 
  bit       we; // write enable: 1 = write, 0 = read

  function new(string name = "wb_transaction");
    super.new(name);
  endfunction

  // Returns a readable summary of the transaction by converting it to string
  virtual function string convert2string();
    return $sformatf("WB_TRANS: addr=0x%0h data=0x%0h we=%0b", addr, data, we);
  endfunction

endclass