// ============================================================
// DMA Controller Interface
// ============================================================
interface dma_if (input logic clk, rst_n);
  logic [31:0] src_addr;
  logic [31:0] dst_addr;
  logic [15:0] transfer_len;
  logic [1:0]  burst_size;
  logic        start;
  logic        direction;
  logic        int_enable;

  logic        done;
  logic        busy;
  logic        error;
  logic        interrupt;

  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [31:0] mem_rdata;
  logic        mem_wen;
  logic        mem_ren;
  logic        mem_ack;

  // SVA Assertions
  property done_after_busy;
    @(posedge clk) disable iff (!rst_n)
    $rose(done) |-> $past(busy, 1);
  endproperty
  assert property (done_after_busy)
    else $error("DONE asserted without prior BUSY");

  property busy_clears_after_done;
    @(posedge clk) disable iff (!rst_n)
    done |=> !busy;
  endproperty
  assert property (busy_clears_after_done)
    else $error("BUSY did not clear after DONE");

  property irq_gated;
    @(posedge clk) disable iff (!rst_n)
    interrupt |-> int_enable;
  endproperty
  assert property (irq_gated)
    else $error("Interrupt fired without int_enable");
endinterface

// ============================================================
// DMA Controller DUT
// ============================================================
module dma_controller (dma_if dif);

  logic [31:0] mem [0:255];

  typedef enum logic [2:0] {
    IDLE  = 3'd0,
    FETCH = 3'd1,
    WRITE = 3'd2,
    DONE  = 3'd3,
    ERR   = 3'd4
  } dma_state_t;

  dma_state_t  state;
  logic [31:0] src_ptr;
  logic [31:0] dst_ptr;
  logic [15:0] beat_cnt;
  logic [15:0] total_beats;
  logic [31:0] fetch_data;

  always_ff @(posedge dif.clk or negedge dif.rst_n) begin
    if (!dif.rst_n) begin
      state         <= IDLE;
      dif.done      <= 0;
      dif.busy      <= 0;
      dif.error     <= 0;
      dif.interrupt <= 0;
      dif.mem_wen   <= 0;
      dif.mem_ren   <= 0;
      dif.mem_addr  <= 0;
      dif.mem_wdata <= 0;
      dif.mem_ack   <= 0;
      src_ptr       <= 0;
      dst_ptr       <= 0;
      beat_cnt      <= 0;
      total_beats   <= 0;
      fetch_data    <= 0;
      for (int j = 0; j < 256; j++)
        mem[j] <= j * 32'h01010101;
    end else begin
      dif.done      <= 0;
      dif.interrupt <= 0;
      dif.mem_ack   <= 0;
      dif.mem_wen   <= 0;
      dif.mem_ren   <= 0;

      case (state)
        IDLE: begin
          dif.busy  <= 0;
          dif.error <= 0;
          if (dif.start) begin
            if ((dif.src_addr[7:0] + dif.transfer_len > 256) ||
                (dif.dst_addr[7:0] + dif.transfer_len > 256)) begin
              state    <= ERR;
              dif.busy <= 1;
            end else begin
              src_ptr     <= dif.src_addr;
              dst_ptr     <= dif.dst_addr;
              total_beats <= dif.transfer_len;
              beat_cnt    <= 0;
              dif.busy    <= 1;
              state       <= FETCH;
            end
          end
        end

        FETCH: begin
          dif.mem_ren  <= 1;
          dif.mem_addr <= src_ptr + beat_cnt;
          fetch_data   <= mem[(src_ptr[7:0] + beat_cnt) % 256];
          dif.mem_ack  <= 1;
          state        <= WRITE;
        end

        WRITE: begin
          dif.mem_wen   <= 1;
          dif.mem_addr  <= dst_ptr + beat_cnt;
          dif.mem_wdata <= fetch_data;
          mem[(dst_ptr[7:0] + beat_cnt) % 256] <= fetch_data;
          dif.mem_ack   <= 1;
          beat_cnt      <= beat_cnt + 1;
          if (beat_cnt + 1 >= total_beats)
            state <= DONE;
          else
            state <= FETCH;
        end

        DONE: begin
          dif.done  <= 1;
          dif.busy  <= 0;
          if (dif.int_enable)
            dif.interrupt <= 1;
          state <= IDLE;
        end

        ERR: begin
          dif.error <= 1;
          dif.busy  <= 0;
          dif.done  <= 1;
          if (dif.int_enable)
            dif.interrupt <= 1;
          state <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign dif.mem_rdata = mem[dif.mem_addr[7:0]];

endmodule
