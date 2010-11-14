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
		$dialog = [new JDialog: $frame, "Add Pivots", 0];
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

		$button = [new JButton: "Add Pivot"];
		[$button addActionListener: lambda({
			local('$host $mask $tmp_console');
			$host = [$model getSelectedValueFromColumn: $table, "host"];
			$mask = [$model getSelectedValueFromColumn: $table, "mask"];
	
			if ($host ne "" && $mask ne "") {
				$tmp_console = createConsole($client);
				cmd($client, $tmp_console, "route add $host $mask $sid", lambda({ 
					call($client, "console.destroy", $tmp_console);
					if ($3 ne "") { showError($3); } 
				}, \$tmp_console));
			}
			[$dialog setVisible: 0];
		}, \$table, \$model, \$dialog, \$sid)];

		[$a add: $button];

		[$dialog add: $center, [BorderLayout CENTER]];
		[$dialog add: $a, [BorderLayout SOUTH]];

		[$button requestFocus];
		[$dialog setVisible: 1];
	}
}

sub setupPivotDialog {
	return lambda({
		%handlers["route"] = lambda(&pivot_dialog, \$sid);
		m_cmd($sid, "route");			
	}, $sid => "$1");
}

# killPivots(sid, session data
sub killPivots {
	foreach $route (split(',', $2['routes'])) {
		cmd($client, $console, "route remove ".strrep($route, '/', ' ')." $1", {});
	}
}
