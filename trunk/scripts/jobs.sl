#
# code to manage some jobs ;)
#

import msf.*;
import armitage.*;
import console.*;
import table.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

import java.awt.*;
import java.awt.event.*;

sub manage_file_autopwn {
	manage_job("Auxiliary: server/file_autopwn", 
		# start server function
		{
			launch_dialog("File AutoPWN", "auxiliary", "server/file_autopwn", 1);
		},
		# description of job (for job kill function)
		{
			local('$host $port $uripath');
			($host, $port) = values($2["info"]["datastore"], @("SRVHOST", "SRVPORT"));
			$uripath = $2["info"]["uripath"];
			return "File Autopwn is at http:// $+ $host $+ : $+ $port $+ $uripath $+ \nWould you like to stop it?";
		}
	);

}

sub manage_browser_autopwn {
	manage_job("Auxiliary: server/browser_autopwn", 
		# start server function
		{
			launch_dialog("Browser AutoPWN", "auxiliary", "server/browser_autopwn", 1);
		},
		# description of job (for job kill function)
		{
			local('$host $port $uripath');
			($host, $port) = values($2["info"]["datastore"], @("SRVHOST", "SRVPORT"));
			$uripath = $2["info"]["uripath"];
			return "Browser Autopwn is at http:// $+ $host $+ : $+ $port $+ $uripath $+ \nWould you like to stop it?";
		}
	);

}

sub manage_proxy_server {
	manage_job("Auxiliary: server/socks4a", 
		# start server function
		{
			launch_dialog("SOCKS Proxy", "auxiliary", "server/socks4a", $null);
		},
		# description of job (for job kill function)
		{
			local('$host $port');
			($host, $port) = values($2["info"]["datastore"], @("SRVHOST", "SRVPORT"));
			return "SOCKS proxy is running on $host $+ : $+ $port $+ .\nWould you like to stop it?";
		}
	);

}

sub report_url {
	find_job($name, {
		if ($1 == -1) {
			showError("Server not found");
		}
		else {
			local('$job $host $port $uripath');
			$job = call($client, "job.info", $1);

			($host, $port) = values($job["info"]["datastore"], @("SRVHOST", "SRVPORT"));
			$uripath = $job["info"]["uripath"];

			local('$dialog $text $ok');
			$dialog = dialog("Output", 320, 240);
			$text = [new JTextArea];
			[$text setText: "http:// $+ $host $+ : $+ $port $+ $uripath"];

			$button = [new JButton: "Ok"];
 			[$button addActionListener: lambda({ [$dialog setVisible: 0]; }, \$dialog)];

			[$dialog add: [new JScrollPane: $text], [BorderLayout CENTER]];
			[$dialog add: center($button), [BorderLayout SOUTH]];

			[$dialog setVisible: 1];
		}
	});
}

sub find_job {
	#
	# convoluted? yes, but jobs.info kept locking up on some of my requests...
	#
	local('$tmp_console');
	$tmp_console = createConsole($client);
	cmd($client, $console, "jobs", lambda({
		call($client, "console.destroy", $tmp_console);

		local('$temp $jid $jname $confirm');

		foreach $temp (split("\n", $3)) {
			if ([$temp trim] ismatch '.*?(\d+)\s+(.*?)') {
				($jid, $jname) = matched();	

				if ($jname eq $name) {
					[$function: $jid];
					return;
				}
			}
		}
		[$function: -1];
	}, $name => $1, $function => $2, \$tmp_console));
}

# manage_job(job name, { start job function }, { job dialog info })
sub manage_job {
	local('$name $startf $stopf');
	($name, $startf, $stopf) = @_;

	find_job($name, lambda({
		if ($1 == -1) {
			[$startf];
		}
		else {
			local('$job $confirm $foo');
			$job = call($client, "job.info", $1);

			$foo = lambda({
				local('$confirm');
				$confirm = askYesNo([$stopf : $jid, $job], "Stop Job");
				if ($confirm eq "0") {
					cmd($client, $console, "jobs -k $jid", { if ($3 ne "") { showError($3); } }); 
				}
			}, \$stopf, \$job, $jid => $1);

			if ([SwingUtilities isEventDispatchThread]) {
				[$foo];				
			}
			else {
				[SwingUtilities invokeLater: $foo];
			}
		}		
	}, \$startf, \$stopf));
}

sub launch_service {
	local('$c $key $value');
	$c = createConsoleTab("$1", 1);

	sleep(500);

	[$c sendString: "use $2\n"];	

	foreach $key => $value ($3) {
		[$c sendString: "set $key $value $+ \n"];		
	}
	
	if ($4 eq "exploit") {
		[$c sendString: "exploit -j\n"];
	}
	else if ($4 eq "payload") {
		local('$file');
		$file = saveFile2();
		if ($file !is $null) {
			[$c sendString: "generate -t $format -f $file $+ \n"];
		}
	}
	else {
		[$c sendString: "run\n"];
	}
}

#
# pop up a dialog to start our attack with... fun fun fun
#

# launch_dialog("title", "type", "name", "visible", "hosts...")
sub launch_dialog {
	local('$dialog $north $center $center $label $textarea $scroll $model $table $default $combo $key $sorter $value $col $button');

	local('$info $options');
	$info = call($client, "module.info", $2, $3);
	$options = call($client, "module.options", $2, $3);

	$dialog = dialog($1, 520, 360);

	$north = [new JPanel];
	[$north setLayout: [new BorderLayout]];
	
	$label = [new JLabel: $info["name"]];
	[$label setBorder: [BorderFactory createEmptyBorder: 5, 5, 5, 5]];

	[$north add: $label, [BorderLayout NORTH]];

	$textarea = [new JTextArea: [join(" ", split('[\\n\\s]+', $info["description"])) trim]];
	[$textarea setEditable: 0];
	[$textarea setOpaque: 0];
	[$textarea setLineWrap: 1];
	[$textarea setWrapStyleWord: 1];
	[$textarea setBorder: [BorderFactory createEmptyBorder: 3, 3, 3, 3]];
	$scroll = [new JScrollPane: $textarea];
	[$scroll setPreferredSize: [new Dimension: 480, 48]];
	[$scroll setBorder: [BorderFactory createEmptyBorder: 3, 3, 3, 3]];

	[$north add: $scroll, [BorderLayout CENTER]];

	$model = [new GenericTableModel: @("Option", "Value"), "Option", 128];
	[$model setCellEditable: 1];
	foreach $key => $value ($options) {	
		if ($key eq "THREADS") {
			$default = "24";
		}
		else if ($key eq "LHOST") {
			$default = $MY_ADDRESS;
		}
		else if ($key eq "RHOSTS") {
			$default = join(", ", $5);
		}
		else if ($key eq "RHOST" && size($5) > 0) {
			$default = $5[0];
		}
		else {
			$default = $value["default"];
		}

		if ($key ne "DisablePayloadHandler") {
			[$model _addEntry: %(Option => $key, Value => $default, Tooltip => $value["desc"], Hide => iff($value["advanced"] eq '0' && $value["evasion"] eq '0', '0', '1'))]; 
		}
	}

	$table = [new JTable: $model];
	$sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
	[$table setRowSorter: $sorter];
	addFileListener($table, $model);

	foreach $col (@("Option", "Value")) {
		[[$table getColumn: $col] setCellRenderer: lambda({
			local('$render $v');
			$render = [$table getDefaultRenderer: ^String];
			$v = [$render getTableCellRendererComponent: $1, $2, $3, $4, $5, $6];
			[$v setToolTipText: [$model getValueAtColumn: $table, $5, "Tooltip"]];
			return $v;
		}, \$table, \$model)];
	}

	$center = [new JScrollPane: $table];
	$combo = select(sorta(split(',', "raw,ruby,rb,perl,pl,c,js_be,js_le,java,dll,exe,exe-small,elf,macho,vba,vbs,loop-vbs,asp,war")), "exe");
	$button = [new JButton: "Launch"];

	[$button addActionListener: lambda({
		local('$options $table $host $x');
		$options = %(PAYLOAD => "windows/meterpreter/reverse_tcp", DisablePayloadHandler => "1");

		for ($x = 0; $x < [$model getRowCount]; $x++) {
			if ([$model getValueAt: $x, 1] ne "") { 
				$options[ [$model getValueAt: $x, 0] ] = [$model getValueAt: $x, 1];
			}
		}

		[$dialog setVisible: 0];

		if ($visible) {
			launch_service($title, "$type $+ / $+ $command", $options, $type, $format => [$combo getSelectedItem]);
		}
		else {
			showError(call($client, "module.execute", $type, $command, $options)["result"]);
		}
	}, \$dialog, \$model, $title => $1, $type => $2, $command => $3, $visible => $4, \$combo)];

	local('$advanced');
	$advanced = addAdvanced(\$model);

	local('$panel');
	$panel = [new JPanel];
	[$panel setLayout: [new BoxLayout: $panel, [BoxLayout Y_AXIS]]];

	if ($2 eq "payload") {
		[$panel add: left([new JLabel: "Output: "], $combo)];
	}

	[$panel add: left($advanced)];
	[$panel add: center($button)];
	[$dialog add: $panel, [BorderLayout SOUTH]];

	[$dialog add: $north, [BorderLayout NORTH]];
	[$dialog add: $center, [BorderLayout CENTER]];

	[$button requestFocus];

	[$dialog setVisible: 1];
}

sub updateJobsTable {
	local('$tmp_console');
	$tmp_console = createConsole($client);
	cmd($client, $tmp_console, "jobs -l -v", lambda({
		local('$temp $d $jid $jname $payload $lport $date $url');

		[$model clear: 16];

		foreach $temp (split("\n", $3)) {
			$d = sublist(split('\s{2,}', $temp), 1);
			if (size($d) == 5) {
				($jid, $jname, $payload, $lport, $date, $url) = $d;
			}
			else if (size($d) == 4) {
				($jid, $jname, $lport, $date, $payload, $url) = $d;
			}
			else {
				($jid, $jname, $payload, $lport, $url, $date) = $d;
			}
			
			if (-isnumber $jid) {
				[$model addEntry: %(Id => $jid, Name => $jname, Payload => $payload, Port => $lport, Start => $date, URL => $url)];
			}
		}

		[$model fireListeners];
		call($client, "console.destroy", $tmp_console);
	}, \$model, \$tmp_console));
}

sub createJobsTab {	
	local('$table $model $refresh $kill $panel $jobsf $sorter');
	
	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$model = [new GenericTableModel: @("Id", "Name", "Payload", "Port", "URL", "Start"), "Id", 8];

	$table = [new JTable: $model];
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];
	[[$table getColumn: "Id"] setPreferredWidth: 125];
	[[$table getColumn: "Port"] setPreferredWidth: 200];
	[[$table getColumn: "Name"] setPreferredWidth: 1024];
	[[$table getColumn: "Payload"] setPreferredWidth: 1024];
	[[$table getColumn: "URL"] setPreferredWidth: 1024];
	[[$table getColumn: "Start"] setPreferredWidth: 1024];

        $sorter = [new TableRowSorter: $model];
        [$sorter toggleSortOrder: 0];
        [$table setRowSorter: $sorter];
        [$sorter setComparator: 0, { return $1 <=> $2; }];
        [$sorter setComparator: 3, { return $1 <=> $2; }];

	$jobsf = lambda(&updateJobsTable, \$model);
	[$jobsf];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];
	
	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: $jobsf];

	$kill = [new JButton: "Kill"];
	[$kill addActionListener: lambda({ 
		cmd($client, $console, "jobs -k " . [$model getSelectedValue: $table], lambda({ 
			showError($3); 
			[$jobsf];
		}, \$jobsf));
	}, \$table, \$model, \$jobsf)];

	[$panel add: center($refresh, $kill), [BorderLayout SOUTH]];

	[$frame addTab: "Jobs", $panel, $null];
}		
