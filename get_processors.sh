#!/bin/bash
PATTERN=$(printf 'processor\t:')
PHYS_PROCESSORS=$(grep "${PATTERN}" /proc/cpuinfo | wc -l)
if [[ $PHYS_PROCESSORS -gt 4 ]]
then
	echo 4
else
	echo $PHYS_PROCESSORS
fi
