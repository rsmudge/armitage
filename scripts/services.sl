#
# Process Browser (for Meterpreter)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

import ui.*;

sub updateServiceModel {
	local('$port $row $host');
	[$model clear: 256];
	foreach $host ($hosts) {
		if ($host in %hosts && 'services' in %hosts[$host]) {
			foreach $port => $row (%hosts[$host]['services']) {	
				[$model addEntry: $row];	
			}
		}
	}
	[$model fireListeners];
}

sub createServiceBrowser {
	local('$table $model $panel $refresh $sorter $host $copy $info $remove');

	$model = [new GenericTableModel: @("host", "name", "port", "proto", "info"), "host", 16];

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$table = [new ATable: $model];
	$sorter = [new TableRowSorter: $model];
        [$sorter toggleSortOrder: 2];
	[$table setRowSorter: $sorter];

	$info = lambda({
		[lambda({
			local('$info $val');
			$info = [$model getSelectedValueFromColumn: $table, "info"];
			ask_async("Set info to", $info, $this);
			yield;

			# updating service info
			foreach $val ([$model getSelectedValuesFromColumns: $table, @("id")]) {
				call_async($mclient, "db.report_service", %(id => $val['id'], info => $1));
			}

			local('$services');
			call_async_callback($mclient, "db.services", $this);
			yield;
			$services = convertAll($1);
			if ('services' in $services) {
				_refreshServices($services['services']);
				updateServiceModel(\$hosts, \$model);
			}
		}, \$model, \$table, \$hosts)];
	}, \$model, \$table, $hosts => $1);

	$remove = lambda({
		local('$val');

		# delete services
		foreach $val ([$model getSelectedValuesFromColumns: $table, @("id")]) {
			call_async($mclient, "db.remove_service", %(id => $val['id']));
		}

		# refresh our table
		local('$services');
		call_async_callback($mclient, "db.services", $this);
		yield;
		$services = convertAll($1);
		if ('services' in $services) {
			_refreshServices($services['services']);
			updateServiceModel(\$hosts, \$model);
		}
	}, \$model, \$table, $hosts => $1);

	addMouseListener($table, lambda({
		if ([$1 isPopupTrigger]) {
			local('$popup $hosts %r $val $m');
			$popup = [new JPopupMenu];

			%r = %();
			foreach $val ([$model getSelectedValues: $table]) {
				%r[$val] = 1;
			}
			$hosts = keys(%r);
			
			if (size($hosts) > 0) {
				host_selected_items($popup, $hosts);
				[$popup addSeparator];
				#$m = menu($popup, "Service", 'S');
					item($popup, "Service Info", 'I', $info); 
					#item($m, "Remove", 'R', $remove);
				[$popup show: [$1 getSource], [$1 getX], [$1 getY]];
			}
		}
	}, \$table, \$model, \$info, \$remove));
	
	[[$table getColumn: "info"] setPreferredWidth: 300];
	[[$table getColumn: "host"] setPreferredWidth: 125];
	[$sorter setComparator: 2, { return $1 <=> $2; }];
	[$sorter setComparator: 0, &compareHosts];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		[lambda({
			local('$services');
			call_async_callback($mclient, "db.services", $this);
			yield;
			$services = convertAll($1);
			if ('services' in $services) {
				_refreshServices($services['services']);
				updateServiceModel(\$hosts, \$model);
			}
		}, \$hosts, \$model)];
	}, \$model, $hosts => $1)];

	$copy = [new JButton: "Copy"];
	[$copy addActionListener: lambda({
		local('%r $val $hosts');
		%r = %();
		foreach $val ([$model getSelectedValues: $table]) {
			%r[$val] = 1;
		}
		$hosts = keys(%r);
		setClipboard(join(", ", $hosts));
		showError("Copied selected hosts to clipboard");
	}, \$model, \$table)];

	updateServiceModel($hosts => $1, \$model); 		

	[$panel add: center($refresh, $copy), [BorderLayout SOUTH]];
	[$frame addTab: "Services", $panel, $null];
}
