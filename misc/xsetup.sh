#!/bin/bash
#
# Extra setup of things for the RAFT cluster
#

echo "Extra setup massage, assuming ./work_dir/ncs-run{1,2,3} exist!!"

#
# Use: netconf-console-tcp --create-subscription=ncs-alarms
# 
echo "Enable TCP transport for NETCONF northbound on all nodes..."
for i in 1 2 3; do
    ncs_conf_tool -R '  <enabled>true</enabled>'  ncs-config netconf-north-bound transport tcp enabled < work_dir/ncs-run${i}/ncs.conf > tmp.conf && mv tmp.conf work_dir/ncs-run${i}/ncs.conf;
done


echo "Setup SNMP event streaming on all nodes..."
for i in 1 2 3; do
    ncs_conf_tool -a '
       <stream>
         <name>snmp</name>
         <description>SNMP notifications</description>
         <replay-support>false</replay-support>
          <builtin-replay-store>
            <enabled>false</enabled>
            <dir>./state</dir>
            <max-size>S10M</max-size>
            <max-files>50</max-files>
          </builtin-replay-store>
       </stream>
      '  ncs-config notifications event-streams < work_dir/ncs-run${i}/ncs.conf > tmp.conf && mv tmp.conf work_dir/ncs-run${i}/ncs.conf;
done

echo "Copy SNMP stuff to all nodes..."
echo "Maybe load SNMP config as: ncs_load -lm snmp_init.xml"
echo "Run trap receiver as: ./trap-snmp.sh"

for i in 1 2 3; do
    cp snmp/snmp_init.xml work_dir/ncs-run${i}/.
    cp snmp/snmptrapd.conf work_dir/ncs-run${i}/.
    cp snmp/trap-snmp.sh work_dir/ncs-run${i}/.
done

