`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================
// PACKAGE
// ============================================================
package dma_pkg;
  `include "uvm_macros.svh"
  import uvm_pkg::*;

  // ----------------------------------------------------------
  // 1. Transaction
  // ----------------------------------------------------------
  class dma_seq_item extends uvm_sequence_item;
    `uvm_object_utils(dma_seq_item)

    rand logic [31:0] src_addr;
    rand logic [31:0] dst_addr;
    rand logic [15:0] transfer_len;
    rand logic [1:0]  burst_size;
    rand logic        direction;
    rand logic        int_enable;

    logic done;
    logic error;
    logic interrupt;

    constraint c_len   { transfer_len inside {1,2,4,8,16}; }
    constraint c_burst { burst_size inside {2'b00,2'b01,2'b10}; }
    constraint c_src   { src_addr[31:8] == 0; src_addr[7:0] inside {[0:200]}; }
    constraint c_dst   { dst_addr[31:8] == 0; dst_addr[7:0] inside {[0:200]}; }
    constraint c_bounds { src_addr[7:0] + transfer_len <= 256;
                          dst_addr[7:0] + transfer_len <= 256; }
    constraint c_noovlp { (src_addr[7:0] + transfer_len <= dst_addr[7:0]) ||
                          (dst_addr[7:0] + transfer_len <= src_addr[7:0]); }

    function new(string name="dma_seq_item");
      super.new(name);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 2. Sequences
  // ----------------------------------------------------------
  class dma_base_seq extends uvm_sequence #(dma_seq_item);
    `uvm_object_utils(dma_base_seq)
    function new(string name="dma_base_seq"); super.new(name); endfunction
  endclass

  // Random transfers
  class dma_rand_seq extends dma_base_seq;
    `uvm_object_utils(dma_rand_seq)
    int unsigned num_txns = 20;
    function new(string name="dma_rand_seq"); super.new(name); endfunction
    task body();
      dma_seq_item txn;
      repeat(num_txns) begin
        txn = dma_seq_item::type_id::create("txn");
        start_item(txn);
        if (!txn.randomize()) `uvm_fatal("RAND","Randomization failed")
        finish_item(txn);
      end
    endtask
  endclass

  // Burst transfer sequence
  class dma_burst_seq extends dma_base_seq;
    `uvm_object_utils(dma_burst_seq)
    function new(string name="dma_burst_seq"); super.new(name); endfunction
    task body();
      dma_seq_item txn;
      int burst_vals[4] = '{1,4,8,16};
      foreach(burst_vals[i]) begin
        txn = dma_seq_item::type_id::create($sformatf("burst_txn_%0d",i));
        start_item(txn);
        if (!txn.randomize() with {
              transfer_len == burst_vals[i];
              int_enable   == 1;
              src_addr     == 32'h00000000;
              dst_addr     == 32'h00000040;
            }) `uvm_fatal("RAND","burst rand failed")
        finish_item(txn);
      end
    endtask
  endclass

  // Interrupt sequence
  class dma_interrupt_seq extends dma_base_seq;
    `uvm_object_utils(dma_interrupt_seq)
    function new(string name="dma_interrupt_seq"); super.new(name); endfunction
    task body();
      dma_seq_item txn;
      // IRQ enabled
      txn = dma_seq_item::type_id::create("irq_on");
      start_item(txn);
      if (!txn.randomize() with {
            int_enable==1; transfer_len==4;
            src_addr==32'h10; dst_addr==32'h60;
          }) `uvm_fatal("RAND","irq_on rand failed")
      finish_item(txn);
      // IRQ disabled
      txn = dma_seq_item::type_id::create("irq_off");
      start_item(txn);
      if (!txn.randomize() with {
            int_enable==0; transfer_len==4;
            src_addr==32'h20; dst_addr==32'h70;
          }) `uvm_fatal("RAND","irq_off rand failed")
      finish_item(txn);
    endtask
  endclass

  // Boundary overflow injection
  class dma_boundary_seq extends dma_base_seq;
    `uvm_object_utils(dma_boundary_seq)
    function new(string name="dma_boundary_seq"); super.new(name); endfunction
    task body();
      dma_seq_item txn;
      txn = dma_seq_item::type_id::create("overflow_txn");
      start_item(txn);
      void'(txn.randomize());
      // Override to force boundary violation
      txn.src_addr     = 32'h000000F0; // 240 + 32 = 272 > 256
      txn.dst_addr     = 32'h00000000;
      txn.transfer_len = 16'd32;
      txn.int_enable   = 1;
      finish_item(txn);
    endtask
  endclass

  // Concurrent back-to-back transfers
  class dma_concurrent_seq extends dma_base_seq;
    `uvm_object_utils(dma_concurrent_seq)
    function new(string name="dma_concurrent_seq"); super.new(name); endfunction
    task body();
      dma_seq_item txn;
      repeat(4) begin
        txn = dma_seq_item::type_id::create("conc_txn");
        start_item(txn);
        if (!txn.randomize() with {
              transfer_len inside {1,2,4};
              int_enable == 1;
            }) `uvm_fatal("RAND","conc rand failed")
        finish_item(txn);
      end
    endtask
  endclass

  // ----------------------------------------------------------
  // 3. Driver
  // ----------------------------------------------------------
  class dma_driver extends uvm_driver #(dma_seq_item);
    `uvm_component_utils(dma_driver)
    virtual dma_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual dma_if)::get(this, "", "vif", vif))
        `uvm_fatal("CFG","DMA Driver: No VIF")
    endfunction

    task run_phase(uvm_phase phase);
      dma_seq_item txn;
      vif.start      <= 0;
      vif.src_addr   <= 0;
      vif.dst_addr   <= 0;
      vif.transfer_len <= 0;
      vif.burst_size <= 0;
      vif.direction  <= 0;
      vif.int_enable <= 0;
      @(posedge vif.clk);
      while (!vif.rst_n) @(posedge vif.clk);
      forever begin
        seq_item_port.get_next_item(txn);
        drive_transfer(txn);
        seq_item_port.item_done();
      end
    endtask

    task drive_transfer(dma_seq_item txn);
      int timeout;
      // Wait for idle
      timeout = 0;
      while (vif.busy) begin
        @(posedge vif.clk);
        timeout++;
        if (timeout > 500) `uvm_fatal("DRV","DMA busy timeout")
      end
      // Program registers
      @(posedge vif.clk);
      vif.src_addr     <= txn.src_addr;
      vif.dst_addr     <= txn.dst_addr;
      vif.transfer_len <= txn.transfer_len;
      vif.burst_size   <= txn.burst_size;
      vif.direction    <= txn.direction;
      vif.int_enable   <= txn.int_enable;
      @(posedge vif.clk);
      // Pulse start
      vif.start <= 1;
      @(posedge vif.clk);
      vif.start <= 0;
      // Wait for done
      timeout = 0;
      while (!vif.done) begin
        @(posedge vif.clk);
        timeout++;
        if (timeout > 1000) `uvm_fatal("DRV","DMA done timeout")
      end
      txn.done      = vif.done;
      txn.error     = vif.error;
      txn.interrupt = vif.interrupt;
      @(posedge vif.clk);
    endtask
  endclass

  // ----------------------------------------------------------
  // 4. Monitor
  // ----------------------------------------------------------
  class dma_monitor extends uvm_monitor;
    `uvm_component_utils(dma_monitor)
    virtual dma_if vif;
    uvm_analysis_port #(dma_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(virtual dma_if)::get(this, "", "vif", vif))
        `uvm_fatal("CFG","DMA Monitor: No VIF")
    endfunction

    task run_phase(uvm_phase phase);
      dma_seq_item txn;
      forever begin
        @(posedge vif.clk iff vif.start);
        txn = dma_seq_item::type_id::create("mon_txn");
        txn.src_addr     = vif.src_addr;
        txn.dst_addr     = vif.dst_addr;
        txn.transfer_len = vif.transfer_len;
        txn.burst_size   = vif.burst_size;
        txn.direction    = vif.direction;
        txn.int_enable   = vif.int_enable;
        @(posedge vif.clk iff vif.done);
        txn.done      = vif.done;
        txn.error     = vif.error;
        txn.interrupt = vif.interrupt;
        ap.write(txn);
      end
    endtask
  endclass

  // ----------------------------------------------------------
  // 5. Functional Coverage
  // ----------------------------------------------------------
  class dma_coverage extends uvm_subscriber #(dma_seq_item);
    `uvm_component_utils(dma_coverage)

    dma_seq_item item;

    covergroup dma_cg with function sample(dma_seq_item t);
      cp_len: coverpoint t.transfer_len {
        bins len_single = {1};
        bins len_small  = {2,4};
        bins len_burst  = {8,16};
      }
      cp_burst: coverpoint t.burst_size {
        bins bsize_1 = {2'b00};
        bins bsize_4 = {2'b01};
        bins bsize_8 = {2'b10};
      }
      cp_dir: coverpoint t.direction {
        bins dir_m2m = {1'b0};
        bins dir_m2p = {1'b1};
      }
      cp_irq: coverpoint t.int_enable {
        bins irq_off = {1'b0};
        bins irq_on  = {1'b1};
      }
      cp_err: coverpoint t.error {
        bins no_err  = {1'b0};
        bins has_err = {1'b1};
      }
      cp_irq_fired: coverpoint t.interrupt {
        bins irq_no  = {1'b0};
        bins irq_yes = {1'b1};
      }
      cx_len_dir:   cross cp_len,  cp_dir;
      cx_irq_err:   cross cp_irq,  cp_err;
      cx_len_burst: cross cp_len,  cp_burst;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      dma_cg = new();
    endfunction

    function void write(dma_seq_item t);
      item = t;
      dma_cg.sample(t);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 6. Scoreboard
  // ----------------------------------------------------------
  class dma_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(dma_scoreboard)
    uvm_analysis_imp #(dma_seq_item, dma_scoreboard) analysis_export;

    int pass_cnt, fail_cnt, error_cnt, irq_cnt;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      analysis_export = new("analysis_export", this);
    endfunction

    function void write(dma_seq_item txn);
      if (!txn.done) begin
        fail_cnt++;
        `uvm_error("SB",$sformatf(
          "FAIL: done never asserted | src=0x%0h dst=0x%0h len=%0d",
          txn.src_addr, txn.dst_addr, txn.transfer_len))
        return;
      end
      // Boundary violation check
      if ((txn.src_addr[7:0] + txn.transfer_len > 256) ||
          (txn.dst_addr[7:0] + txn.transfer_len > 256)) begin
        if (txn.error) begin
          pass_cnt++; error_cnt++;
          `uvm_info("SB",$sformatf(
            "BOUNDARY ERR OK: src=0x%0h len=%0d errored as expected",
            txn.src_addr, txn.transfer_len), UVM_MEDIUM)
        end else begin
          fail_cnt++;
          `uvm_error("SB",$sformatf(
            "BOUNDARY MISS: src=0x%0h len=%0d should have errored",
            txn.src_addr, txn.transfer_len))
        end
        return;
      end
      // Normal transfer checks
      if (txn.error) begin
        fail_cnt++;
        `uvm_error("SB",$sformatf(
          "UNEXPECTED ERR: src=0x%0h dst=0x%0h len=%0d",
          txn.src_addr, txn.dst_addr, txn.transfer_len))
        return;
      end
      if (txn.int_enable && !txn.interrupt) begin
        fail_cnt++;
        `uvm_error("SB",$sformatf(
          "IRQ MISS: int_enable=1 but interrupt=0 | src=0x%0h",
          txn.src_addr))
        return;
      end
      if (!txn.int_enable && txn.interrupt) begin
        fail_cnt++;
        `uvm_error("SB",$sformatf(
          "SPURIOUS IRQ: int_enable=0 but interrupt=1 | src=0x%0h",
          txn.src_addr))
        return;
      end
      if (txn.interrupt) irq_cnt++;
      pass_cnt++;
      `uvm_info("SB",$sformatf(
        "PASS: src=0x%0h dst=0x%0h len=%0d irq=%0b err=%0b",
        txn.src_addr, txn.dst_addr, txn.transfer_len,
        txn.interrupt, txn.error), UVM_MEDIUM)
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SB",$sformatf(
        "=== DMA Scoreboard Report === PASS:%0d FAIL:%0d ERR_CAUGHT:%0d IRQ_FIRED:%0d",
        pass_cnt, fail_cnt, error_cnt, irq_cnt), UVM_NONE)
    endfunction
  endclass

  // ----------------------------------------------------------
  // 7. Agent
  // ----------------------------------------------------------
  class dma_agent extends uvm_agent;
    `uvm_component_utils(dma_agent)
    dma_driver  drv;
    dma_monitor mon;
    uvm_sequencer #(dma_seq_item) seqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv  = dma_driver::type_id::create("drv", this);
      mon  = dma_monitor::type_id::create("mon", this);
      seqr = uvm_sequencer #(dma_seq_item)::type_id::create("seqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 8. Virtual Sequencer
  // ----------------------------------------------------------
  class dma_virtual_seqr extends uvm_sequencer;
    `uvm_component_utils(dma_virtual_seqr)
    uvm_sequencer #(dma_seq_item) agent_seqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 9. Environment
  // ----------------------------------------------------------
  class dma_env extends uvm_env;
    `uvm_component_utils(dma_env)
    dma_agent        agent;
    dma_scoreboard   sb;
    dma_coverage     cov;
    dma_virtual_seqr vseqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = dma_agent::type_id::create("agent", this);
      sb    = dma_scoreboard::type_id::create("sb", this);
      cov   = dma_coverage::type_id::create("cov", this);
      vseqr = dma_virtual_seqr::type_id::create("vseqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap.connect(sb.analysis_export);
      agent.mon.ap.connect(cov.analysis_export);
      vseqr.agent_seqr = agent.seqr;
    endfunction
  endclass

  // ----------------------------------------------------------
  // 10. Tests
  // ----------------------------------------------------------
  class dma_base_test extends uvm_test;
    `uvm_component_utils(dma_base_test)
    dma_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = dma_env::type_id::create("env", this);
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
      `uvm_info("TEST","=== DMA Topology ===", UVM_NONE)
      uvm_top.print_topology();
    endfunction

    function void report_phase(uvm_phase phase);
      uvm_report_server svr = uvm_report_server::get_server();
      if (svr.get_severity_count(UVM_FATAL) +
          svr.get_severity_count(UVM_ERROR) == 0)
        `uvm_info("TEST","*** TEST PASSED ***", UVM_NONE)
      else
        `uvm_info("TEST","*** TEST FAILED ***", UVM_NONE)
    endfunction
  endclass

  class dma_regression_test extends dma_base_test;
    `uvm_component_utils(dma_regression_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      dma_rand_seq       rand_seq;
      dma_burst_seq      burst_seq;
      dma_interrupt_seq  irq_seq;
      dma_boundary_seq   bound_seq;
      dma_concurrent_seq conc_seq;

      phase.raise_objection(this);

      `uvm_info("TEST","--- Running: Random Transfers ---", UVM_NONE)
      rand_seq = dma_rand_seq::type_id::create("rand_seq");
      rand_seq.num_txns = 20;
      rand_seq.start(env.agent.seqr);

      `uvm_info("TEST","--- Running: Burst Transfers ---", UVM_NONE)
      burst_seq = dma_burst_seq::type_id::create("burst_seq");
      burst_seq.start(env.agent.seqr);

      `uvm_info("TEST","--- Running: Interrupt Tests ---", UVM_NONE)
      irq_seq = dma_interrupt_seq::type_id::create("irq_seq");
      irq_seq.start(env.agent.seqr);

      `uvm_info("TEST","--- Running: Boundary/Overflow ---", UVM_NONE)
      bound_seq = dma_boundary_seq::type_id::create("bound_seq");
      bound_seq.start(env.agent.seqr);

      `uvm_info("TEST","--- Running: Concurrent Transfers ---", UVM_NONE)
      conc_seq = dma_concurrent_seq::type_id::create("conc_seq");
      conc_seq.start(env.agent.seqr);

      #200;
      phase.drop_objection(this);
    endtask
  endclass

endpackage

// ============================================================
// TOP MODULE
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"
import dma_pkg::*;

module top;
  logic clk, rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
  end

  dma_if dif (.clk(clk), .rst_n(rst_n));
  dma_controller dut (.dif(dif));

  initial #2000000 $finish;

  initial begin
    uvm_config_db #(virtual dma_if)::set(
      null, "uvm_test_top.*", "vif", dif);
    run_test();
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
  end
endmodule
