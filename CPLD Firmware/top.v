module top ( 	stdby_in, stdby1, switch0, switch0_gnd, clock_84_0000, clock_00_0384, clock_00_0096, 
				led0, led1, led2, led3, led4, led5, led6, led7, 
				spi_clk, spi_miso, spi_mosi, spi_csn0, spi_csn1, adc_drdy, adc_clock, adc_data_0,
				rs_232_rx, rs_232_tx );

input		stdby_in;
output		stdby1;

input		switch0;
output		switch0_gnd;
output		led0, led1, led2, led3, led4, led5, led6, led7;

inout		spi_clk, spi_miso, spi_mosi;
output		spi_csn0, spi_csn1;

input       adc_drdy, adc_clock, adc_data_0;

input		rs_232_rx;
output		rs_232_tx;


output		clock_84_0000;
output    	clock_00_0384;
output reg	clock_00_0096;

assign		switch0_gnd = 1'b0;

wire		stby_flag ;
wire		clock_lock;

wire [2:0]  spi_csn;
wire        sd_cs;

assign      spi_csn0 = spi_csn[0];
assign      spi_csn1 = spi_csn[1];

wire [7:0]  rs_232_rx_byte;
wire		rs_232_rx_valid;
wire [7:0]  rs_232_rx_command_valid;

// Internal Oscillator
defparam OSCH_inst.NOM_FREQ = "7";		//  This is the default frequency

OSCH OSCH_inst ( 
					.STDBY(stdby1 ), 		// 0=Enabled, 1=Disabled also Disabled with Bandgap=OFF
					.OSC(osc_clk ),
					.SEDSTDBY());		//  this signal is not required if not using SED - see TN1199 for more details.

pll pll_inst (
					.CLKI(osc_clk ),
					.LOCK(clock_lock),
					.CLKOP(clock_84_0000 ),
					.CLKOS(clock_00_0384 ));
					
pwr_cntrllr pcm1 (	
					.USERSTDBY(stdby_in ),
					.CLRFLAG(stby_flag ),
					.CFGSTDBY(1'b0 ),
					.STDBY(stdby1 ),
					.SFLAG(stby_flag ));


reg  buffer_full_latch;

always@(posedge clock_84_0000 or posedge reset)
	begin
	if(reset)
	    buffer_full_latch <= 1'b0;
	else
	    if(buffer_full == 1'b1)
	        buffer_full_latch <= 1'b1;
	end

wire data_formatter_signal;
wire data_buffer_signal;
wire pseudo_adc_signal;
wire regulator_control_signal;
wire sensor_interface_signal;
wire thermal_controller_signal;

wire adc_init;
wire sd_init;
wire sd_write_error;

//          LEDs 1'b1 = Off, 1'b0 = On
assign led0 = ~rs_232_rx_command_valid[0];
assign led1 = ~rs_232_rx_command_valid[1];
assign led2 = ~rs_232_rx_command_valid[2];
assign led3 = ~rs_232_rx_command_valid[3];

assign led4 = ~adc_init;
assign led5 = ~sd_init;
assign led6 = ~(buffer_half_filled | buffer_full_latch);
assign led7 = ~sd_write_error;                              

reg [1:0] clk_div;

wire reset_c = ~clock_lock;

always@(posedge clock_00_0384 or posedge reset_c)
	begin
	if(reset_c)
		begin
		    clk_div         <= 2'b00;
			clock_00_0096   <= 1'b0;
		end
	else
		begin
		    clk_div         <= clk_div + 2'b01;
			clock_00_0096   <= clk_div[1];
		end
	end	

reg         switch0_db;
reg [4:0]   debounce_counter;

wire rs_232_reset;

wire reset = (~switch0_db) | (~clock_lock) | rs_232_reset; // NAND

always@(posedge clock_00_0096 or posedge reset_c)
    begin
        if(reset_c)
            begin
                switch0_db         <= 1'b0;
                debounce_counter    <= 4'h0;
            end
        else
            begin
                if(debounce_counter == 4'hF)
                    switch0_db     <= switch0;
                if((switch0_db != switch0) && (debounce_counter != 4'hF))
                    debounce_counter <= debounce_counter + 1;
                else
                    debounce_counter <= 4'h0;
            end
    
    end


wire 		wb_cyc;
wire 		wb_stb;
wire 		wb_we;
wire [7:0]	wb_adr; 
wire [7:0]	wb_dat_i;
wire [7:0]	wb_dat_o;
wire 		wb_ack;

efb efb_inst (
					.wb_clk_i(clock_84_0000),
					//.wb_clk_i(osc_clk),
					.wb_rst_i(reset),
					.wb_cyc_i(wb_cyc),
					.wb_stb_i(wb_stb),
					.wb_we_i(wb_we),
					.wb_adr_i(wb_adr), 
					.wb_dat_i(wb_dat_i),
					.wb_dat_o(wb_dat_o),
					.wb_ack_o(wb_ack),
					.spi_clk(spi_clk),
					.spi_miso(spi_miso),
					.spi_mosi(spi_mosi),
					.spi_scsn(1'b1),
					.spi_csn(spi_csn)
					);

wire        adc_sample_start;					
wire [31:0]	adc_data;
wire [31:0]	adc_data_ch1;
wire [31:0]	adc_data_ch2;
wire [31:0]	adc_data_ch3;
wire [31:0]	adc_data_ch4;
wire [31:0]	adc_data_ch5;
wire [31:0]	adc_data_ch6;
wire [31:0]	adc_data_ch7;
wire [31:0]	adc_data_ch8;
wire        adc_data_ready_ch1;
wire        adc_data_ready_ch2;
wire        adc_data_ready_ch3;
wire        adc_data_ready_ch4;
wire        adc_data_ready_ch5;
wire        adc_data_ready_ch6;
wire        adc_data_ready_ch7;
wire        adc_data_ready_ch8;

wire [31:0] buffer_data;
wire        buffer_write_enable;
wire        buffer_read_enable;
wire        buffer_empty;
wire        buffer_full;
wire        buffer_half_filled;
					
spi_controller spi_controller_inst (	
					.clock(clock_84_0000 ),
					.reset(reset ),
					.wb_cyc(wb_cyc),
					.wb_stb(wb_stb),
					.wb_we(wb_we),
					.wb_adr(wb_adr),
					.wb_dat_i(wb_dat_i),
					.wb_dat_o(wb_dat_o),
					.wb_ack(wb_ack),
					.adc_sample_start(adc_sample_start),
					.buffer_read_enable(buffer_read_enable),
					.buffer_data(buffer_data),
					.buffer_half_filled(buffer_half_filled),
					.adc_init(adc_init),
					.sd_init(sd_init),
					.sd_write_error(sd_write_error));
					
adc_serial_interface adc_serial_interface_inst (	
					.clock(clock_84_0000 ),
					.reset(reset ),
					.start(adc_sample_start),
					.adc_data_ready(adc_drdy),
					.adc_clock(adc_clock),
					.adc_data_0(adc_data_0),
					.adc_channel_data(adc_data),
					.adc_channel_data_ch1(adc_data_ch1),
					.adc_channel_data_ch2(adc_data_ch2),
					.adc_channel_data_ch3(adc_data_ch3),
					.adc_channel_data_ch4(adc_data_ch4),
					.adc_channel_data_ch5(adc_data_ch5),
					.adc_channel_data_ch6(adc_data_ch6),
					.adc_channel_data_ch7(adc_data_ch7),
					.adc_channel_data_ch8(adc_data_ch8),
					.adc_channel_data_ready_ch1(adc_data_ready_ch1),
					.adc_channel_data_ready_ch2(adc_data_ready_ch2),
					.adc_channel_data_ready_ch3(adc_data_ready_ch3),
					.adc_channel_data_ready_ch4(adc_data_ready_ch4),
					.adc_channel_data_ready_ch5(adc_data_ready_ch5),
					.adc_channel_data_ready_ch6(adc_data_ready_ch6),
					.adc_channel_data_ready_ch7(adc_data_ready_ch7),
					.adc_channel_data_ready_ch8(adc_data_ready_ch8),
					.buffer_write_enable(buffer_write_enable),
					.buffer_full(buffer_full));					
					
fifo_buffer fifo_buffer_inst (
                    .Data(adc_data), 
                    .WrClock(clock_84_0000), 
                    .RdClock(clock_84_0000), 
                    .WrEn(buffer_write_enable), 
                    .RdEn(buffer_read_enable), 
                    .Reset(reset), 
                    .RPReset(reset), 
                    .Q(buffer_data), 
                    .Empty(buffer_empty), 
                    .Full(buffer_full),
                    .AlmostFull(buffer_half_filled)
                    );
					
data_formatter data_formatter_inst(	
					.clock(clock_84_0000 ),
					.reset(reset ),
					.signal(data_formatter_signal ));
					
data_buffer data_buffer_inst(	
					.clock(osc_clk ),
					.reset(reset ),
					.signal(data_buffer_signal ));
					

parameter MAX_BYTES	= 14;
					
wire [MAX_BYTES*8-1:0]    tx_bytes;
wire [3:0]                tx_num_bytes;
wire                      tx_valid;					
					
rs232_decoder_encoder rs232_decoder_encoder_inst(	
					.clock(clock_00_0096 ),
					.clock_4x(clock_00_0384),
					.reset(reset ),
					.rx(rs_232_rx ),
					.tx(rs_232_tx ),
					.rx_valid(rs_232_rx_valid),
					.rx_byte(rs_232_rx_byte),
					.tx_bytes(tx_bytes),
					.tx_num_bytes(tx_num_bytes),
					.tx_valid(tx_valid));
					
rs232_command_processor rs232_command_processor_inst(	
					.clock(clock_84_0000 ),
					.reset(reset ),
					.rs_232_reset(rs_232_reset),
					.rx_valid(rs_232_rx_valid),
					.rx_byte(rs_232_rx_byte),
					.command_valid(rs_232_rx_command_valid),
					.tx_bytes(tx_bytes),
					.tx_num_bytes(tx_num_bytes),
					.tx_valid(tx_valid),
					.adc_data_ch1(adc_data_ch1),
					.adc_data_ch2(adc_data_ch2),
					.adc_data_ch3(adc_data_ch3),
					.adc_data_ch4(adc_data_ch4),
					.adc_data_ch5(adc_data_ch5),
					.adc_data_ch6(adc_data_ch6),
					.adc_data_ch7(adc_data_ch7),
					.adc_data_ch8(adc_data_ch8),
					.adc_data_ready_ch1(adc_data_ready_ch1),
					.adc_data_ready_ch2(adc_data_ready_ch2),
					.adc_data_ready_ch3(adc_data_ready_ch3),
					.adc_data_ready_ch4(adc_data_ready_ch4),
					.adc_data_ready_ch5(adc_data_ready_ch5),
					.adc_data_ready_ch6(adc_data_ready_ch6),
					.adc_data_ready_ch7(adc_data_ready_ch7),
					.adc_data_ready_ch8(adc_data_ready_ch8));
					
pseudo_adc pseudo_adc_inst(	
					.clock(osc_clk ),
					.reset(reset ),
					.signal(pseudo_adc_signal ));
					
regulator_control regulator_control_inst(	
					.clock(clock_84_0000 ),
					.reset(reset ),
					.signal(regulator_control_signal ));
					
sensor_interface sensor_interface_inst(	
					.clock(osc_clk ),
					.reset(reset ),
					.signal(sensor_interface_signal ));
					
thermal_controller thermal_controller_inst(	
					.clock(osc_clk ),
					.reset(reset ),
					.signal(thermal_controller_signal ));


endmodule
