//  *******************************************************************************************************************
//  Brief: A lightweight round-robin arbiter. 
//  Round robin arbitration: in its basic form, is a simple time slice scheduling, 
//      allowing each requestor an equal share of the time in accessing a memory 
//      or a limited processing resource in a circular order. 
//  RRA are suitable for a small amount of requesters
//  *******************************************************************************************************************

//  *******************************************************************************************************************
//  purpose	: define the entity, the entity's ports, and the port types
//  I/O		
//  Input	: 
//          - reset : arbiter's reset signal
//          - hostCLK : the system's clock --> 80MHz clock (see top and clock_gen)
//          - request: incoming requests for resources
//              + Each user must be assigned an element in this vector.
//              + When the user requires use of the arbitrated resource, it must set its element \c true
//              + The element must remain \c true as long as the resource is in use.
//              + When the element is brought \c false, the resource is released.
//  Outputs	: 
//          - grant : The outgoing resource grants to the users.
//              + Whenever an element of this vector is \c true, the specified user may use the arbitrated resource.
//              + Once the resource is granted, the grant will not be revoked until the user stops requesting it.
//              + Latency from the rising edge of a \ref Request line to the rising edge of the corresponding Grant line ranges from combinational to arbitrarily many cycles.
//              + Latency from the falling edge of a \ref Request line to the falling edge of the corresponding Grant line is always combinational.
//  Parameters : width : The number of users of the arbiter.
//  *******************************************************************************************************************

module Arbiter (
    reset, HostClock, Request, Grant // parametrized module
);
`def FALSE  = 1
`def TRUE   = 0

//==============================//
//        Module Params         //
//==============================//
parameter width = 5; // number of users/requesters
input reset;         // active high synchronous reset
input hostCLK,
input logic [width-1:0] request;    // make a "vector" the size of 'width'
output logic [width-1:0] grant;     // make a "vector" the size of 'width'

//==============================//
//       Other Params           //
//==============================//
logic [width-1] spinner;
logic anyGrant;
integer index;
integer index_g;
integer k = width - 2; // multiplier

always_ff @ (posedge hostCLK) begin : spin
    if (reset) begin
        spinner <= {k{`FALSE},`TRUE}; // assign spinner[width-1:1] = 1 and spinner[0] = 0, vhdl equiv: (0 => true, others => false)
    end else begin
        anyGrant = `FALSE;
        if (index < width) begin
            anyGrant = anyGrant | Grant[index];
            index = index + 1;
        end else begin
            if (!anyGrant) begin
                spinner <= spinner[width-1] & spinner[width-2:0];
            end
        end
    end
end

always_comb begin : grants
    if (index_g < width) begin
        grand[index_g] <= request[index_g] & spinner[index_g];
        index_g = index_g + 1;
    end
end
    
endmodule : Arbiter


