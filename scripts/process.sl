#
# Process Browser (for Meterpreter)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

global('%processes');
%processes = ohash();

setMissPolicy(%processes, { return [new GenericTableModel: @("PID", "Name", "Arch", "Session", "User", "Path"), "PID", 128]; });

sub parseProcessList {
	if ($0 eq "begin") {
		[%processes[$1] clear: 128];
	}
	else if ($0 eq "end") {
		[%processes[$1] fireListeners];
	}
	else if ($0 eq "update") {
		local('$pid $process $arch $session $user $path');
		$2 = [$2 trim];

		if ($2 ismatch '(\d{1,})\s{2,}(.*?)\s{2,}(.*?)\s{2,}(.*?)\s{2,}(.*?)\s{2,}(.*?)') {
			($pid, $process, $arch, $session, $user, $path) = matched();
			# map({ return [$1 trim]; }, unpack('Z7 Z21 Z6 Z9 Z22 Z*', $2));
			[%processes[$1] addEntry: %(PID => $pid, Name => $process, Arch => $arch, Session => $session, User => $user, Path => $path)]; 
		}
	}
}

%handlers["ps"] = &parseProcessList;
%handlers["migrate"] = { if ($0 eq "begin") { showError("$2"); } };

sub createProcessBrowser {
	local('$table $model $panel $sorter');

	$model = %processes[$1];

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$table = [new JTable: $model];
	$sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
	[$table setRowSorter: $sorter];

	# allow only one row to be selected at a time.

	[$sorter setComparator: 0, {
		return $1 <=> $2;
	}];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	local('$a $b $bb $c');
	$a = [new JButton: "Kill"];
	[$a addActionListener: lambda({ 
		local('$procs $v');
		$procs = [$model getSelectedValues: $table];
		foreach $v ($procs) {
			m_cmd($m, "kill $v"); 
		}	
		sleep(250);
		m_cmd($m, "ps"); 
	}, $m => $1, \$table, \$model)];

	$b = [new JButton: "Migrate"];
	[$b addActionListener: lambda({ 
		local('$v');
		$v = [$model getSelectedValue: $table];
		if ($v !is $null) {
			m_cmd($m, "migrate $v"); 
		}	
	}, $m => $1, \$table, \$model)];

	$bb = [new JButton: "Log Keystrokes"];
	[$bb addActionListener: lambda({
		local('$v');
		$v = [$model getSelectedValue: $table];
		if ($v !is $null) {
			launch_dialog("Log Keystrokes", "post", "windows/capture/keylog_recorder", 1, $null, %(SESSION => $m, MIGRATE => 1, ShowKeystrokes => 1, PID => $v, CAPTURE_TYPE => "pid"));
		}	
	}, $m => $1, \$table, \$model)];

	$c = [new JButton: "Refresh"];
	[$c addActionListener: 
		lambda({ 
			m_cmd($m, "ps"); 
		}, $m => $1)
	];

	[$panel add: center($a, $b, $bb, $c), [BorderLayout SOUTH]];

	[$frame addTab: "Processes $1", $panel, $null];
	m_cmd($1, "ps");
}
