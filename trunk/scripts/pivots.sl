#
# Code to create the various attack menus based on db_autopwn
#
import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

import msf.*;
import table.*;

import graph.*;

sub maskToCIDR {
	local ('$x');
	$x = strlen(strrep(formatNumber([Route ipToLong: $1], 10, 2), "0", ""));
	return $x;
}

sub arp_scan_function  {
	local('$host $mask $tmp_console');
	$host = [$model getSelectedValueFromColumn: $table, "host"];
	$mask = [$model getSelectedValueFromColumn: $table, "mask"];
	
	if ($host ne "" && $mask ne "") {
		elog("added pivot: $host $mask $sid");
		warn(call($client, "module.execute", "post", "windows/gather/arp_scanner", %(SESSION => $sid, RHOSTS => "$host $+ /" . maskToCIDR($mask))));
	}
	[$dialog setVisible: 0];
}

sub add_pivot_function  {
	local('$host $mask $tmp_console');
	$host = [$model getSelectedValueFromColumn: $table, "host"];
	$mask = [$model getSelectedValueFromColumn: $table, "mask"];
	
	if ($host ne "" && $mask ne "") {
		$tmp_console = createConsole($client);
		elog("added pivot: $host $mask $sid");
		cmd($client, $tmp_console, "route add $host $mask $sid", lambda({ 
			call($client, "console.destroy", $tmp_console);
			if ($3 ne "") { showError($3); } 
		}, \$tmp_console));
	}
	[$dialog setVisible: 0];
}

#
# pop up a dialog to start our attack with... fun fun fun
#

# pivot_dialog($sid, $network output?))
sub pivot_dialog {
	this('@routes');

	if ($0 eq "update") {
		local('$ip_pattern $host $mask $gateway');
		$ip_pattern = "(\\d+\\.\\d+.\\d+.\\d+)";

		if ($2 ismatch "\\s+ $+ $ip_pattern $+ \\s+ $+ $ip_pattern $+ \\s+ $+ $ip_pattern") {
			($host, $mask, $gateway) = matched();

			if ($host ne "127.0.0.0" && $host ne "224.0.0.0" && $host ne "0.0.0.0" && $mask ne "255.255.255.255") {
				push(@routes, %(host => $host, mask => $mask, gateway => $gateway));
			}
		}
	}
	else if ($0 eq "end") {
		$handler = $null;
		%handlers["route"] = $null;

		local('$dialog $model $table $sorter $center $a $route $button');
		$dialog = [new JDialog: $frame, $title, 0];
		[$dialog setSize: 320, 240];
		[$dialog setLayout: [new BorderLayout]];
		[$dialog setLocationRelativeTo: $frame];

		[$dialog setLayout: [new BorderLayout]];
	
		$model = [new GenericTableModel: @("host", "mask"), "Option", 8];
		foreach $route (@routes) {
			[$model _addEntry: $route];
		}

		$table = [new JTable: $model];
	        [[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];
		$sorter = [new TableRowSorter: $model];
		[$table setRowSorter: $sorter];

		$center = [new JScrollPane: $table];
	
		$a = [new JPanel];
		[$a setLayout: [new FlowLayout: [FlowLayout CENTER]]];

		$button = [new JButton: $label];
		[$button addActionListener: lambda($function, \$table, \$model, \$dialog, \$sid)];

		[$a add: $button];

		[$dialog add: $center, [BorderLayout CENTER]];
		[$dialog add: $a, [BorderLayout SOUTH]];

		[$button requestFocus];
		[$dialog setVisible: 1];
	}
}

sub setupPivotDialog {
	return lambda({
		%handlers["route"] = lambda(&pivot_dialog, \$sid, $title => "Add Pivots", $label => "Add Pivot", $function => &add_pivot_function);
		m_cmd($sid, "route");
	}, $sid => "$1");
}

sub setupArpScanDialog {
	return lambda({
		%handlers["route"] = lambda(&pivot_dialog, \$sid, $title => "ARP Scan", $label => "ARP Scan", $function => &arp_scan_function);
		m_cmd($sid, "route");
	}, $sid => "$1");
}

# killPivots(sid, session data
sub killPivots {
	local('$route');
	foreach $route (split(',', $2['routes'])) {
		cmd_safe("route remove " . strrep($route, '/', ' ') . " $1");
	}

	elog("removed pivot: " . $2['routes']);
}
