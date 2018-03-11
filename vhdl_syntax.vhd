--****************************************
--          VHDL syntax                   
--****************************************

--  Entity Defition
---------------------------
entity entity_name is
    -- declare ports of the entity I(I/O list)
	port( 
        port_name_def : signal_type;
    );
end entity entity_name;
        
-- Architecture Definition
---------------------------
architecture block_name of module_Name is
    -- signal declations
    signal signal_name : signal_type;

begin -- begins a process

-- Port Definition
---------------------------
port (
    signal_name : signal_type;
)

-- Port Mapping
---------------------------
port map (
		port_name => signal_name
);

-- Generic Mapping
---------------------------
-- generic mapping passes information to the entity, in this case divide values are defined
-- usually used to assign values to attributes
generic map (
		port_name => value,
) -- don't need a semicolon for generic maps


