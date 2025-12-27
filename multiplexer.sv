// DESIGN

interface intf ( input clk,  input rst);
  logic sel;
  logic [1:0] ip1;
  logic [1:0] ip2;
  logic [3:0] op;
  
  clocking cb @(posedge clk);
    default input #(1) output #(1);
    output sel, ip1, ip2;
    input sel, ip1, ip2,op;
  endclocking
  
  modport DUT(input clk, rst, sel, ip1, ip2, output op);
  modport TB(input clk, rst, op, output sel, ip1, ip2);
  
endinterface

module mux(intf vif);
  always @(*) begin
    if (vif.rst) begin
       vif.op <= 4'b0;
    end
    else begin
       vif.op <= vif.sel? vif.ip2 : vif.ip1;
    end
  end
endmodule 


//TESTBENCH

/* - we have use clocking block to avoid race condition
   - Randamozie the transaction inputs for 10 times 
   - to verify DUT and testbench components I have used verify variable to check the 
   	 DUT and TB functionality. 
 */

/* In generator class we need to create the transaction handle inside the repeat loop
   In driver class we have get the packet in forever loop.*/


class transaction;
  
  rand bit sel;
  rand bit [1:0] ip1;
  rand bit [1:0] ip2;
  bit [3:0] op;
  
endclass

class generator;
  transaction trans;
  
  mailbox #(transaction) gen2driv;
  
  function new(mailbox #(transaction) gen2driv);
    this.gen2driv=gen2driv;
  endfunction
  
  task working ();
    repeat (10) begin
      trans =new();
      void' (trans.randomize());
      $display ("Randomize values are sel=%0b, ip1=%0b, ip2=%0b", trans.sel, trans.ip1, trans.ip2);
      gen2driv.put(trans);
    end
  endtask
  
endclass

class driver;
  transaction trans;
  virtual intf vif;
  mailbox #(transaction) gen2driv;
  
  function new (virtual intf vif, mailbox #(transaction) gen2driv);
    this.vif=vif;
    this.gen2driv=gen2driv;
  endfunction 
  
  task working();
    forever begin 
      gen2driv.get(trans);
      @(vif.cb); // will working on rising edge of clocking block.
      vif.cb.sel <= trans.sel;
      vif.cb.ip1 <= trans.ip1;
      vif.cb.ip2 <= trans.ip2;
    end
  endtask
endclass

class monitor;
  
  transaction trans;
  virtual intf vif;
  mailbox #(transaction) mon2scb;
  
  function new (virtual intf vif, mailbox #(transaction) mon2scb);
    this.vif=vif;
    this.mon2scb=mon2scb;
  endfunction 
  
  task working();
    forever begin 
      trans =new();
      @(vif.cb);
      
      trans.sel = vif.cb.sel;
      trans.ip1 = vif.cb.ip1;
      trans.ip2 =vif.cb.ip2;
      trans.op = vif.cb.op;
      mon2scb.put(trans);
    end
  endtask
endclass

class scoreboard;
  bit [3:0]verify;
  transaction trans;
  mailbox #(transaction) mon2scb;
  
  function new (mailbox #(transaction) mon2scb);
    this.mon2scb=mon2scb;
  endfunction
  
  task working();
    forever begin
      mon2scb.get(trans);
      if (trans.sel)begin
        verify = trans.ip2;
      end
      else begin
        verify = trans.ip1;
      end
      if (trans.op == verify) begin
        $display ("Verified: op = %0b, verify = %0b", trans.op, verify);
      end
      else begin
        $display ("Failed", trans.op, verify);
      end
    end
  endtask
endclass

class environment;
  generator gen;
  driver driv;
  monitor mon;
  scoreboard scb ;
  virtual intf vif;
  
  mailbox #(transaction) gen2driv;
  mailbox #(transaction) mon2scb;
  function new (virtual intf vif);
    this.vif =vif;
    
    gen2driv = new();
    mon2scb = new();
    
    gen = new (gen2driv);
    driv = new (vif, gen2driv);
    mon = new (vif, mon2scb);
    scb = new (mon2scb);
  endfunction
  
  task working();
    fork
      gen.working();
      driv.working();
      mon.working();
      scb.working();
    join_any
  endtask
endclass

class test;
  environment env;
  
  function new (virtual intf vif);
    env= new (vif);
  endfunction 
  
  task working();
    env.working();
  endtask 
endclass

module tb();
  
  bit clk, rst;
  always #5 clk =~clk;
  intf vif (clk ,rst);
  mux dut (vif);
  
  test t1;
  initial begin
    rst =1;
    clk =0;
    #10 rst =0;
    t1=new(vif);
    t1.working();
    #200 $finish;
  end
  
endmodule
