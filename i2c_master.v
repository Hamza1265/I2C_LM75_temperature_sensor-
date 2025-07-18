// Issues: glitchy stop bit clock in post-synthesis simulation

`timescale 1ns / 1ps

module i2c_master(
                   input wire clk125mhz,
                
                
                    inout wire i2c_sda,
                   output wire i2c_scl
                  );

    // basic connection establishment states
	localparam IDLE            = 0;
	localparam START           = 1;
	localparam ADDRESS_SLV     = 2;        
	localparam READ_WRITE_BIT  = 3;
	localparam ACK_ADDR_SLV    = 4;
	
	// register address for write/read transaction (compulsory)
	localparam ADDRESS_REG_MSB = 5;
	localparam ACK_ADDR_REG    = 6;
	localparam ADDRESS_REG_LSB = 7;
	
	// write data to the selected register 
	localparam DATA_WRITE_MSB  = 8;
	localparam ACK_DATA_WRITE  = 9;
	localparam DATA_WRITE_LSB  = 10;
	
	// read data from the selected register
	localparam RESTART         = 11;
	localparam DATA_READ_MSB   = 12;
	localparam ACK_DATA_READ   = 13;
	localparam DATA_READ_LSB   = 14;
	
	// end of transactions
	localparam NACK            = 15;
    localparam STOP            = 16;
	
	// 
	localparam DIVIDE_BY = 1000;

    	reg [7:0] state;
    	reg [15:0] data_out;
	reg [6:0] slv_address;
	reg [15:0] reg_address;
	reg [15:0] saved_data;
	reg [7:0] counter;
	reg [15:0] counter2 = 0;
	reg write_enable;
	reg sda_out;
	reg i2c_scl_enable = 0;
	reg i2c_clk        = 1;
	reg repeated_start = 0;
	reg rw_in;
	reg msb;
	reg wr_done = 0;
	reg [7:0] rp_counter = 0;
	reg [7:0] nk_counter = 0;
	reg [7:0] previous_i2c_state = 0;
    wire      i2c_stop_to_idle_detect;

	assign ready   = ((rst_n == 1) && (state == IDLE)) ? 1 : 0;
    assign i2c_scl = (((state == 8'd11) && rp_counter == 0) || (state == 8'd0) || (i2c_stop_to_idle_detect)) ? 1'b1 : (i2c_scl_enable == 0) ? 1 : i2c_clk;
	assign i2c_sda = (write_enable == 1) ? sda_out : 'bz;
	assign i2c_stop_to_idle_detect = ((previous_i2c_state == 16) && (state == 0));
	assign i2c_clk_out = i2c_clk;
//	assign i2c_sda_t = (write_enable == 1)? 1'b0: 1'b1;
	
	 i2c_clk instance_name
   (
    // Clock out ports
    .clk_out1(clk),     // output clk_out1
   // Clock in ports
    .clk_in1(clk125mhz));      // input clk_in1
    
    vio_0 your_instance_name (
  .clk(clk),                // input wire clk
  .probe_out0(rst_n),  // output wire [0 : 0] probe_out0
  .probe_out1(enable)  // output wire [0 : 0] probe_out1
);
    
	// ========================================= Clock prescale =========================================
	always @ (posedge clk) 
	begin
		if (counter2 == (DIVIDE_BY/2) - 1) 
		begin
			i2c_clk  <= ~i2c_clk;
			counter2 <= 0;
		end
		else 
		    counter2 <= counter2 + 1;
	end 

    // ====================================== i2c posedge FSM ====================================== 
    always @(posedge i2c_clk, negedge rst_n)
    begin
        if(!rst_n)
        begin
            previous_i2c_state <= 8'd0;
        end
        else
        begin
            previous_i2c_state <= state;  
        end
    end
    
    // ====================================== i2c posedge FSM ====================================== 
    always @(posedge i2c_clk, negedge rst_n) 
    begin
        if(!rst_n)
        begin
            state <= IDLE;
            saved_data <= 16'h0000;
            repeated_start <= 0;
            msb <= 0;
            data_out <= 16'h0000;
            rp_counter <= 8'h00;
            nk_counter <= 8'h00;
            counter <= 8'h00;
            slv_address <= 7'h00;
            reg_address <= 16'h0000;
            rw_in <= 0;
            wr_done <= 0;
        end
        else
        begin
            case(state)
            // =============== state 0 (common state)
            IDLE:
            begin
                if(enable)
                begin
                    state       <=    START;
                    slv_address <= 7'b1001000;
                    reg_address <= 8'b00000000;
                    saved_data  <=  16'h0A1B;
                    rw_in       <=       1'b0;
                end
                else
                    state <= IDLE;
            end
            
            // =============== state 1 (common state) 
            START:
            begin
                counter <=       8'h06;
                state   <= ADDRESS_SLV;
            end
            
            // =============== state 2 (common state)           
            ADDRESS_SLV:
            begin
                if(counter == 0)
                begin
                    state <= READ_WRITE_BIT;
                end
                else 
                    counter <= counter - 1;
            end
            
            // =============== state 3 (common state)     
            READ_WRITE_BIT:
            begin                        
                state <= ACK_ADDR_SLV;
            end
                  
            // =============== state 4 (common state)   
            ACK_ADDR_SLV:
            begin
//                if(i2c_sda == 0)      // uncomment
                if(1)
                begin
                    if(repeated_start)
                    begin
                        repeated_start <= 0;
                        counter <= 8'd7;
                        wr_done <= 0;
                        state   <= DATA_READ_MSB;
                    end
                    else
                    begin
                        counter <= 8'd15;
                        state   <= ADDRESS_REG_MSB;
                    end
                end
                else
                    state <= STOP;
            end
                    
            // =============== state 5 (common state)     
            ADDRESS_REG_MSB:
            begin
                if(counter == 8)
                begin
                    msb   <= 1;
                    state <= ACK_ADDR_REG;
                end
                else 
                    counter <= counter - 1;
            end   
            
            // =============== state 6 (common state)           
            ACK_ADDR_REG:
            begin            
//                if(i2c_sda == 0)       // uncomment
                if(1)
                begin
                    if(msb) 
                    begin
                        state   <= ADDRESS_REG_LSB;
                        counter <= 8'h07;
                    end
                    else
                    begin
                        if(rw_in)    // if read operation requested
                        begin
                            state <= RESTART;
                            rp_counter <= 8'h01;
                        end
                        else         // if write operation requested
                        begin
                            state   <= DATA_WRITE_MSB;
                            counter <= 8'd7;
                        end
                    end                        
                end
                else
                    state <= STOP;                
            end  
                        
            // =============== state 7 (common state)           
            ADDRESS_REG_LSB:
            begin
                if(counter == 0)
                begin
                    msb   <= 0;
                    state <= ACK_ADDR_REG;
                end
                else 
                    counter <= counter - 1;                
            end  
                        
            // =============== state 8 (write transaction)
            DATA_WRITE_MSB:
            begin
                if(counter == 0)
                begin
//                    msb   <= 1;
                    state <= ACK_DATA_WRITE;
                end
                else 
                    counter <= counter - 1;            
            end  
            
            // =============== state 9 (write transaction)
            ACK_DATA_WRITE:
            begin  
//                if(i2c_sda == 0)       // uncomment
                if(1)
                begin
//                    if(msb) 
//                    begin
                        state   <= STOP;//DATA_WRITE_LSB;
//                        counter <= 8'h07;
//                    end
//                    else
//                    begin
//                        state   <= STOP;
//                    end 
                end
//                else
//                    state <= STOP;                 
            end  
            
            // =============== state 10 (write transaction)           
            DATA_WRITE_LSB:
            begin
                if(counter == 0)
                begin
                    msb   <= 0;
                    state <= ACK_DATA_WRITE;
                end
                else 
                    counter <= counter - 1;             
            end  
            
            // =============== state 11 (read transaction)          
            RESTART:
            begin
                if(rp_counter == 0)
                begin
                    counter <= 8'h06;
                    repeated_start <= 1;
                    state <= ADDRESS_SLV;
                    wr_done <= 1;
                end
                else
                begin
                    rp_counter <= rp_counter - 1;
                    //i2c_scl_enable <= 0;    
                end
            end
            
            // =============== state 12 (read transaction)
            DATA_READ_MSB:
            begin
                data_out[counter] <= i2c_sda;
                if(counter == 0)
                begin
                    state <= NACK;//ACK_DATA_READ;
                    nk_counter <= 8'h01;//added here
                end        
                else
                    counter <= counter - 1;
            end
            
            // =============== state 13 (read transaction)
            ACK_DATA_READ:
            begin

                    state <= DATA_READ_LSB;
                    counter <= 8'h07;
            end
            
            // =============== state 14 (read transaction)                                         
            DATA_READ_LSB:
            begin
                data_out[counter] <= i2c_sda;
                if(counter == 0)
                begin
                    nk_counter <= 8'h01;
                    state <= NACK;
                end        
                else
                    counter <= counter - 1;    
            end 
            
            // =============== state 15 (read transaction)                                         
            NACK:
            begin
                if(nk_counter == 0)
                    state <= IDLE; // is this right?? gotta check
                else 
                    nk_counter <= nk_counter - 1;
            end 
            
            // =============== state 16 (common state)                                         
            STOP:
            begin
                state <= IDLE;     
            end 
            
            endcase
        end
    end
    
    // ====================================== i2c negedge FSM ====================================== 
    always @(negedge i2c_clk, negedge rst_n) 
    begin
        if(!rst_n)
        begin
            write_enable   <= 1;
            sda_out        <= 1;
            i2c_scl_enable <= 0;
        end
        else 
        begin
            case(state)
            // =============== state 0
            IDLE:
            begin
                i2c_scl_enable <= 0;
                sda_out <= 1;
            end
            // =============== state 1            
            START:           
            begin
                write_enable <= 1;
                sda_out      <= 0;
                i2c_scl_enable <= 0;
            end
            
            // =============== state 2
            ADDRESS_SLV:             
            begin
                sda_out <= slv_address[counter];
                i2c_scl_enable <= 1;
            end
            
            // =============== state 3
            READ_WRITE_BIT:  
            begin
                if(!rw_in)
                    sda_out <= rw_in;
                else if(wr_done)
                begin
                    sda_out <= rw_in;
                end
                else 
                    sda_out <= 0;
                i2c_scl_enable <= 1;
            end
            
            // =============== state 4
            ACK_ADDR_SLV:    
            begin
                write_enable <= 0;
                i2c_scl_enable <= 1;
            end
            
            // =============== state 5            
            ADDRESS_REG_MSB: 
            begin
                write_enable <= 1;
                sda_out      <= reg_address[counter];
                i2c_scl_enable <= 1;
            end
            
            // =============== state 6            
            ACK_ADDR_REG:
            begin
                write_enable <= 0;
                i2c_scl_enable <= 1;
            end
            
            // =============== state 7                
            ADDRESS_REG_LSB: 
            begin
                write_enable <= 1;
                sda_out      <= reg_address[counter];                
                i2c_scl_enable <= 1;
            end
            
            // =============== state 8
            DATA_WRITE_MSB:  
            begin
                write_enable <= 1;
                sda_out <= saved_data[counter];
                i2c_scl_enable <= 1;
            end
            
            // =============== state 9
            ACK_DATA_WRITE:  
            begin
                write_enable <= 0;
                i2c_scl_enable <= 1;
            end
            
            // =============== state 10
            DATA_WRITE_LSB:  
            begin
                write_enable <= 1;
                sda_out <= saved_data[counter];
                i2c_scl_enable <= 1;
            end
            
            // =============== state 11
            RESTART:         
            begin
                if(rp_counter == 1)
                begin
                    write_enable <= 1;
                    sda_out <= 1;                
                end
                else if(rp_counter == 0)
                begin   
                    write_enable <= 1;
                    sda_out <= 0;
                    i2c_scl_enable <= 0;
                end                
            end
            
            // =============== state 12
            DATA_READ_MSB:   
            begin
                write_enable <= 0;
                i2c_scl_enable <= 1;
            end
            
            // =============== state 13
            ACK_DATA_READ:   
            begin
                write_enable <= 1;
                i2c_scl_enable <= 1;
                sda_out <= 0;
            end
            
            // =============== state 14
            DATA_READ_LSB:   
            begin
                write_enable <= 0;
                i2c_scl_enable <= 1;
            end
            
            // =============== state 15
            NACK:                
            begin
                write_enable <= 1;
                i2c_scl_enable <= 1;
                if(nk_counter)
                    sda_out <= 1;
                else
                    sda_out <= 0;
            end
            
            // =============== state 16
            STOP:
            begin
                write_enable <= 1;
                sda_out <= 0;
            end
            endcase
        end
    end

endmodule