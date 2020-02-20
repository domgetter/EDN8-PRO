
`include "../base/defs.v"


module map_004
(map_out, bus, sys_cfg, ss_ctrl);

	`include "../base/bus_in.v"
	`include "../base/map_out.v"
	`include "../base/sys_cfg_in.v"
	`include "../base/ss_ctrl_in.v"
	
	output [`BW_MAP_OUT-1:0]map_out;
	input [`BW_SYS_CFG-1:0]sys_cfg;
	
	
	assign sync_m2 = 1;
	assign mir_4sc = 1;//enable support for 4-screen mirroring. for activation should be enabled in sys_cfg also
	assign srm_addr[12:0] = cpu_addr[12:0];
	assign prg_oe = cpu_rw;
	assign chr_oe = !ppu_oe;
	wire cfg_mmc3a = map_sub == 4;
	//*************************************************************  save state setup
	assign ss_rdat[7:0] = 
	ss_addr[7:3] == 0   ? bank_dat[ss_addr[2:0]]:
	ss_addr[7:0] == 8   ? bank_sel : 
	ss_addr[7:0] == 9   ? mmc_ctrl[0] : 
	ss_addr[7:0] == 10  ? mmc_ctrl[1] : 
	ss_addr[7:3] == 2   ? irq_ss_dat : //addr 16-23 for irq
	ss_addr[7:0] == 127 ? map_idx : 8'hff;
	//*************************************************************
	assign ram_ce = {cpu_addr[15:13], 13'd0} == 16'h6000 & ram_ce_on;
	assign ram_we = !cpu_rw & ram_ce & !ram_we_off;
	assign rom_ce = cpu_addr[15];
	assign chr_ce = ciram_ce;
	assign chr_we = cfg_chr_ram & !ppu_we;
	
	//A10-Vmir, A11-Hmir
	assign ciram_a10 = !mir_mod ? ppu_addr[10] : ppu_addr[11];
	assign ciram_ce = !ppu_addr[13];
	
	// pass the bottom 13 CPU address lines through to the current prg address
	assign prg_addr[12:0] = cpu_addr[12:0];
	// the next 6 address lines are informed by the prg mode and the bank_dat saved bits
	//   this helps facilitate the modular fixed bank for PRG in MMC3
	assign prg_addr[18:13] =
	cpu_addr[14:13] == 0 ? (prg_mod == 0 ? bank_dat[6][5:0] : 6'b111110) :
	cpu_addr[14:13] == 1 ? bank_dat[7][5:0] : 
	cpu_addr[14:13] == 2 ? (prg_mod == 1 ? bank_dat[6][5:0] : 6'b111110) : 
	6'b111111;
	
	// pass the PPU address lines through to the current chr address
	assign chr_addr[9:0] = ppu_addr[9:0];
	// the next 8 address lines are informed by the bank_dat saved bits.
	//   the exact values are dependent on which character mode we're in.
	// The 18 total bits of chr_addr constitute the 256k max CHR capacity for MMC3
	// To modify MMC3 to address more CHR ROM, you would need to have a way to fill up more bits
	//   and then use them when presenting graphics to the PPU address bus.
	assign chr_addr[17:10] = cfg_chr_ram ? chr[4:0] : chr[7:0];//ines 2.0 reuired to support 32k ram
	
	// Determine the upper bits of the full chr address. Effectively an 18-bit address where the
	//   bottom 10 bits are supplied directly by the PPU and the other 8 bits are either
	//   retrieved from the stored bank_dat bits (written to $8001) or deduced based
	//   on the character mode (i.e. which pattern table uses 2k chunks).
	// In the simple case, we just use the bank_dat bits, but when loading from
	//   a pattern table (when A12 is high), we have to check the character mode
	//   to do the 1k/2k stuff.
	wire [7:0]chr = 
	ppu_addr[12:11] == {chr_mod, 1'b0} ? {bank_dat[0][7:1], ppu_addr[10]} :
	ppu_addr[12:11] == {chr_mod, 1'b1} ? {bank_dat[1][7:1], ppu_addr[10]} : 
	ppu_addr[11:10] == 0 ? bank_dat[2][7:0] : 
	ppu_addr[11:10] == 1 ? bank_dat[3][7:0] : 
	ppu_addr[11:10] == 2 ? bank_dat[4][7:0] : 
   bank_dat[5][7:0];
	
	// current register address. MMC3 doesn't decode fully, so we only pay attention
	//   to xxx. .... .... ...x This gives us the ability to distinguish
	//   8000, 8001, A000, A001, C000, C001, E000, and E001
	wire [15:0]reg_addr = {cpu_addr[15:13], 12'd0,  cpu_addr[0]};
	
	// The current PRG mode. 1 for split fixed bank
	wire prg_mod = bank_sel[6];
	
	// The current CHR mode. 0 for 2k banks in first pattern table.
	wire chr_mod = bank_sel[7];
	
	// The current mirror mode. 0 for vertical, 1 for horizontal.  ignored in 4-screen mode
	wire mir_mod = mmc_ctrl[0][0];
	
	// PRG RAM settings.  6th bit controls read-only. 7th bit enables/disables RAM.
	wire ram_we_off = mmc_ctrl[1][6];
	wire ram_ce_on = mmc_ctrl[1][7];
	
	// register for current bank slot.  Set by writes to $8000
	reg [7:0]bank_sel;
	
	// register for all current bank numbers.  individual banks set by writes to $8001
	reg [7:0]bank_dat[8];
	
	// register for other mmc3 state. Used to set mirroring (ignored in 4-screen mode) and PRG RAM settings.
	reg [7:0]mmc_ctrl[2];
	
	always @(negedge m2)
	if(ss_act)
	begin
		if(ss_we & ss_addr[7:3] == 0)bank_dat[ss_addr[2:0]] <= cpu_dat;
		if(ss_we & ss_addr[7:0] == 8)bank_sel <= cpu_dat;
		if(ss_we & ss_addr[7:0] == 9)mmc_ctrl[0] <= cpu_dat;
		if(ss_we & ss_addr[7:0] == 10)mmc_ctrl[1] <= cpu_dat;
	end
		else
	if(map_rst)
	begin
		bank_sel[7:0] <= 0;
		
		mmc_ctrl[0][0] <= !cfg_mir_v;
		mmc_ctrl[1][7:0] <= 0;
	
		bank_dat[0][7:0] <= 0;
		bank_dat[1][7:0] <= 2;
		bank_dat[2][7:0] <= 4;
		bank_dat[3][7:0] <= 5;
		bank_dat[4][7:0] <= 6;
		bank_dat[5][7:0] <= 7;
		bank_dat[6][7:0] <= 0;
		bank_dat[7][7:0] <= 1;
	end
		else
	if(!cpu_rw)
	case(reg_addr[15:0])
	
		// Writes to $8000 set the "bank select" byte (top 3 bits set bank configuration)
		16'h8000:bank_sel[7:0] <= cpu_dat[7:0];
		
		// Writes to $8001 save the bank number
		//   We do a "lookup" here to make sure we write to the correct bank slot
		16'h8001:bank_dat[bank_sel[2:0]][7:0] <= cpu_dat[7:0];
		
		// Writes to $A000 set the mirroring (ignored in 4-screen mode)
		16'hA000:mmc_ctrl[0][7:0] <= cpu_dat[7:0];
		
		// Writes to $A001 set PRG RAM configuration and settings. Top bit enables, 6th bit sets read-only.
		16'hA001:mmc_ctrl[1][7:0] <= cpu_dat[7:0];
	endcase

//***************************************************************************** IRQ	
	
	wire [7:0]irq_ss_dat;
	irq_mmc3 irq_inst(
		.bus(bus), 
		.ss_ctrl(ss_ctrl),
		.mmc3a(cfg_mmc3a),
		.irq(irq),
		.ss_dout(irq_ss_dat)
	);

	
endmodule



module irq_mmc3
(bus, ss_ctrl, mmc3a, irq, ss_dout);
	
	`include "../base/bus_in.v"
	`include "../base/ss_ctrl_in.v"
	input mmc3a;
	output irq;
	output [7:0]ss_dout;
	
	assign ss_dout[7:0] = 
	ss_addr[7:0] == 16 ? irq_latch : 
	ss_addr[7:0] == 17 ? irq_on : //irq_on should be saved befor irq_pend
	ss_addr[7:0] == 18 ? irq_ctr : 
	ss_addr[7:0] == 19 ? irq_pend : 
	8'hff;
	
	assign irq = irq_pend;
	
	wire ss_we_ctr = ss_act & ss_we & ss_addr[7:0] == 18 & m3;
	wire ss_we_pnd = ss_act & ss_we & ss_addr[7:0] == 19 & m3;
	
	wire [15:0]reg_addr = {cpu_addr[15:13], 12'd0,  cpu_addr[0]};
	
	reg [7:0]irq_latch;
	reg [7:0]irq_ctr;
	reg irq_on, irq_pend, irq_reload_req;

	// This "runs" on every clock cycle when the clock goes from high to low
	always @(negedge m2)
	if(ss_act)
	begin
		if(ss_we & ss_addr[7:0] == 16)irq_latch <= cpu_dat;
		if(ss_we & ss_addr[7:0] == 17)irq_on <= cpu_dat[0];
	end
		else
	if(map_rst)irq_on <= 0;
		else
	if(!cpu_rw)
	case(reg_addr[15:0])
		16'hC000:irq_latch[7:0] <= cpu_dat[7:0];
		//16'hC001:ctr_reload <= 1;
		16'hE000:irq_on <= 0;
		16'hE001:irq_on <= 1;
	endcase
		
	wire ctr_reload = reg_addr[15:0] == 16'hC001 & !cpu_rw & m2;
	wire [7:0]ctr_next = irq_ctr == 0 ? irq_latch : irq_ctr - 1;
	wire irq_trigger = mmc3a ? ctr_next == 0 & (irq_ctr != 0 | irq_reload_req) : ctr_next == 0;
	
	wire a12d;
	deglitcher dg_inst(ppu_addr[12], a12d, clk);
	
	/*
	always @(posedge ppu_addr[12], negedge irq_on, posedge ss_we_pnd)
	if(ss_we_pnd)irq_pend <= cpu_dat;
		else*/
	always @(posedge a12d, negedge irq_on)
	if(!irq_on)
	begin
		if(!ss_act)irq_pend <= 0;
	end
		else
	if(a12_stb & !ss_act)
	begin
		if(irq_trigger)irq_pend <= 1;
	end
	
	 

	always @(posedge a12d, posedge ctr_reload, posedge ss_we_ctr)
	if(ss_we_ctr)irq_ctr <= cpu_dat;
		else
	if(ctr_reload)
	begin
		irq_reload_req <= 1;
		irq_ctr[7:0] <= 0;
	end
		else
	if(a12_stb & !ss_act)
	begin
		irq_reload_req <= 0;
		irq_ctr <= ctr_next;
	end
	
	
	reg [3:0]irq_a12_st;
	wire a12_stb = irq_a12_st[3:1] == 0;
	always @(negedge m2)
	begin
		irq_a12_st[3:0] <= {irq_a12_st[2:0], a12d};
	end

	
endmodule


module deglitcher
(in, out, clk);
	input in, clk;
	output reg out;

	reg [1:0]st;

	always @(negedge clk)
	begin
		st[1:0] <= {st[0], in};
		if(st[1:0] == 2'b11)out <= 1;
		if(st[1:0] == 2'b00)out <= 0;
	end
	
endmodule

