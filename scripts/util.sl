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
import ui.*;

global('$MY_ADDRESS $RPC_CONSOLE');

# cmd($client, "console", "command here", &callback);
#    invokes a metasploit command... calls the specified callback with the output when the command is complete.
sub cmd {
	#warn("cmd called: " . @_);
	[new CommandClient: $1, "$3 $+ \n", "console.read", "console.write", $2, $4, 0];
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
	if (size(@_) > 2) {
		[$1 execute_async: $2, cast(sublist(@_, 2), ^Object)];
	}
	else {
		[$1 execute_async: $2];
	}
}

# invokes an RPC call: call($console, "function", arg1, arg2, ...)
sub call {
	local('$exception');

	try {
	        if (size(@_) > 2) {
        	        return convertAll([$1 execute: $2, cast(sublist(@_, 2), ^Object)]);
	        }
        	else {
                	return convertAll([$1 execute: $2]);
	        }
	}
	catch $exception {
		#showError("Something went wrong:\nTried:  ". @_ . "\n\nError:\n $+ $exception");
		showError("Something went wrong:\n $+ $2 $+ \n\nError:\n $+ $exception");
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

	[$thread setSessionListener: {
		local('$session $sid');
		$sid = [$1 getActionCommand];
		$session = sessionData($sid);
		if ($session is $null) {
			showError("Session $sid does not exist");
		}
		else if ($session['desc'] eq "Meterpreter") {
			createMeterpreterTab($sid);
		}
		else {
			createShellSessionTab(\$session, \$sid);
		}
	}];

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

	dispatchEvent(lambda({
		[$frame addTab: iff($title is $null, "Console", $title), $console, $thread, $host];
	}, $title => $1, \$console, \$thread, \$host));
	return $thread;
}

sub createDefaultHandler {
	warn("Creating a default reverse handler...");
	# setup a handler for meterpreter
	call_async($client, "core.setg", "LPORT", randomPort());
	call_async($client, "module.execute", "exploit", "multi/handler", %(
		PAYLOAD => "windows/meterpreter/reverse_tcp",
		LHOST => "0.0.0.0",
		ExitOnSession => "false"
	));
}

sub setupHandlers {
	find_job("Exploit: multi/handler", {
		if ($1 == -1) {
			createDefaultHandler();
		}
		else {
			cmd_safe("setg LPORT", {
				if ($3 !ismatch '(?s:LPORT => (.*?)\n.*)') {
					createDefaultHandler();
				}
			});
		}
	});
}

# creates the metasploit console.
sub createConsole {
	local('$r');
	$r = call($1, "console.create");
	if ($r !is $null && $r['id'] !is $null) {
		call($1, "console.read", $r['id'] . "");
		return $r['id'] . "";
	}
	else {
		warn("Create console failed");
	}
}

sub getWorkspaces 
{
	return sorta(filter({ return $1["name"]; }, call($mclient, "db.workspaces")["workspaces"]));
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
	cmd_async($client, $tmp_console, $1, lambda({
		call_async($client, "console.destroy", $tmp_console);
		if ($f) {
			invoke($f, @_);
		}
	}, \$tmp_console, $f => $2));
}

sub createNmapFunction {
	return lambda({
		local('$address');
		$address = ask("Enter scan range (e.g., 192.168.1.0/24):", join(" ", [$targets getSelectedHosts]));
		if ($address eq "") { return; }

		thread(lambda({
			local('$tmp_console $display');
			$tmp_console = createConsole($client);
			$display = createDisplayTab("nmap");
		
			elog("started a scan: nmap $args $address");

			[$display append: "msf > db_nmap $args $address\n\n"];

			cmd_async_display($client, $tmp_console, "db_nmap $args $address", 
				lambda({ 
					call_async($client, "console.destroy", $tmp_console);
					fork({ showError("Scan Complete!\n\nUse Attacks->Find Attacks to suggest\napplicable exploits for your targets."); }, \$frame);
				}, \$tmp_console),
				$display
			);
		}, \$address, \$args));
	}, $args => $1);
}

sub getBindAddress {
	cmd_safe("setg LHOST", {
		local('$text');
		$text = [$3 trim];
		if ($text ismatch 'LHOST => (.*?)') {
			$MY_ADDRESS = matched()[0];
			setupHandlers();
			warn("Used the incumbent: $MY_ADDRESS");
		}
		else {
			cmd($client, $console, "use windows/meterpreter/reverse_tcp", {
				local('$address');
				$address = call($client, "console.tabs", $console, "setg LHOST ")["tabs"];

				$address = split('\\s+', $address[0])[2];
		
				if ($address eq "127.0.0.1") {
					[SwingUtilities invokeLater: {
						local('$address');
						$address = ask("Could not determine attack computer IP\nWhat is it?");
						if ($address ne "") {
							$MY_ADDRESS = $address;
							thread({
								call_async($client, "core.setg", "LHOST", $MY_ADDRESS);
								setupHandlers();
							});
						}
					}];
				}
				else {
					warn("Used the tab method: $address");
					call_async($client, "core.setg", "LHOST", $address);
					setupHandlers();
					$MY_ADDRESS = $address;
				}
			});
		}
	});
}

sub randomPort {
	return int( 1024 + (rand() * 1024 * 30) );
}

sub scanner {
	return lambda({
		launch_dialog("Scan ( $+ $type $+ )", "auxiliary", "scanner/ $+ $type", $host);
	}, $sid => $2, $host => $3, $type => $1);
}

sub startMetasploit {
	local('$exception $user $pass $port');
	($user, $pass, $port) = @_;
	try {
		println("Starting msfrpcd for you.");

		if (isWindows()) {
			local('$handle $data $msfdir');
			$msfdir = [$preferences getProperty: "armitage.metasploit_install.string", ""];
			while (!-exists $msfdir || $msfdir eq "" || !-exists getFileProper($msfdir, "msf3")) {
				$msfdir = chooseFile($title => "Where is Metasploit installed?", $dirsonly => 1);

				if ($msfdir eq "") {
					[System exit: 0];
				}

				if (charAt($msfdir, -1) ne "\\") {
					$msfdir = "$msfdir $+ \\";
				}

				[$preferences setProperty: "armitage.metasploit_install.string", $msfdir];
				savePreferences();
			}

			$handle = [SleepUtils getIOHandle: resource("resources/msfrpcd.bat"), $null];
			$data = join("\r\n", readAll($handle, -1));
			closef($handle);

			$handle = openf(">msfrpcd.bat");
			writeb($handle, strrep($data, '$$USER$$', $1, '$$PASS$$', $2, '$$BASE$$', $msfdir, '$$PORT$$', $port));
			closef($handle);
			deleteOnExit("msfrpcd.bat");

			$msfrpc_handle = exec(@("cmd.exe", "/C", getFileProper("msfrpcd.bat")), convertAll([System getenv]));
		}
		else {
			$msfrpc_handle = exec("msfrpcd -f -a 127.0.0.1 -U $user -P $pass -t Msg -p $port", convertAll([System getenv]));
		}

		# consume bytes so msfrpcd doesn't block when the output buffer is filled
		fork({
			[[Thread currentThread] setPriority: [Thread MIN_PRIORITY]];

			while (!-eof $msfrpc_handle) {
				#
				# check if process is dead...
				#
				try {
					[[$msfrpc_handle getSource] exitValue];
					local('$msg $text');
					$msg = [SleepUtils getIOHandle: resource("resources/error.txt"), $null];
					$text = readb($msg, -1);
					closef($msg);

					if (!askYesNo($text, "Uh oh!")) {
						[gotoURL("http://www.fastandeasyhacking.com/nomsfrpcd")];
					}
					return;
				}
				catch $ex {
					# ignore this...
				}

				#
				# check for data to read...
				#
				if (available($msfrpc_handle) > 0) {
					[[System out] print: readb($msfrpc_handle, available($msfrpc_handle))];
				}
				if (available($msfrpc_error) > 0) {
					[[System err] print: readb($msfrpc_error, available($msfrpc_error))];
				}

				sleep(1024);
			}
			println("msfrpcd is shut down!");
		}, \$msfrpc_handle, $msfrpc_error => [SleepUtils getIOHandle: [[$msfrpc_handle getSource] getErrorStream], $null], \$frame);
	}
	catch $exception {
		showError("Couldn't launch MSF\n" . [$exception getMessage]);
	}
}

sub connectDialog {
	# in case we ended up back here... let's kill this handle
	if ($msfrpc_handle) {
		closef($msfrpc_handle);
		$msfrpc_handle = $null;
	}

	local('$dialog $host $port $ssl $user $pass $button $cancel $start $center $help $helper');
	$dialog = window("Connect...", 0, 0);
	
	# setup our nifty form fields..

	$host = [new ATextField: [$preferences getProperty: "connect.host.string", "127.0.0.1"], 20];
	$port = [new ATextField: [$preferences getProperty: "connect.port.string", "55553"], 10];
	
	$user = [new ATextField: [$preferences getProperty: "connect.user.string", "msf"], 20];
	$pass = [new ATextField: [$preferences getProperty: "connect.pass.string", "test"], 20];

	$button = [new JButton: "Connect"];
	[$button setToolTipText: "<html>Connects to Metasploit.</html>"];

	$help   = [new JButton: "Help"];
	[$help setToolTipText: "<html>Use this button to view the Getting Started Guide on the Armitage homepage</html>"];

	$cancel = [new JButton: "Exit"];

	# lay them out

	$center = [new JPanel];
	[$center setLayout: [new GridLayout: 4, 1]];

	[$center add: label_for("Host", 70, $host)];
	[$center add: label_for("Port", 70, $port)];
	[$center add: label_for("User", 70, $user)];
	[$center add: label_for("Pass", 70, $pass)];

	[$dialog add: $center, [BorderLayout CENTER]];
	[$dialog add: center($button, $help), [BorderLayout SOUTH]];

	[$button addActionListener: lambda({
		[$dialog setVisible: 0];
		connectToMetasploit([$host getText], [$port getText], [$user getText], [$pass getText]);

		if ([$host getText] eq "127.0.0.1") {
			try {
				closef(connect("127.0.0.1", [$port getText], 1000));
			}
			catch $ex {
				if (!askYesNo("A Metasploit RPC server is not running or\nnot accepting connections yet. Would you\nlike me to start Metasploit's RPC server\nfor you?", "Start Metasploit?")) {
					startMetasploit([$user getText], [$pass getText], [$port getText]);
				}
			}
		}
	}, \$dialog, \$host, \$port, \$user, \$pass)];

	[$help addActionListener: gotoURL("http://www.fastandeasyhacking.com/start")];

	[$cancel addActionListener: {
		[System exit: 0];
	}];

	[$dialog pack];
	[$dialog setLocationRelativeTo: $null];
	[$dialog setVisible: 1];
}

sub _elog {
	if ($client !is $mclient) {
		call_async($mclient, "armitage.log", $1, $2);
	}
	else {
		call_async($client, "db.log_event", "$2 $+ //", $1);
	}
}

sub elog {
	local('$2');
	if ($2 is $null) {
		$2 = $MY_ADDRESS;
	}

	_elog($1, $2);
}

sub module_execute {
	if ([$preferences getProperty: "armitage.show_all_commands.boolean", "true"] eq "true") {
		local('$host');

		# for logging purposes, we should figure out the remote host being targeted		

		if ("RHOST" in $3) {
			$host = $3["RHOST"];
		}
		else if ("SESSION" in $3) {
			$host = sessionToHost($3["SESSION"]);
		}
		else {
			$host = "all";
		}

		# okie then, let's create a console and execute all of this stuff...	

		local('$console');
		thread(lambda({
			$console = createConsoleTab("$type", 1, \$host, $file => $type);
			fork({
				local('$key $value');
				[$console sendString: "use $type $+ / $+ $module $+ \n"];

				foreach $key => $value ($options) {
					[$console sendString: "set $key $value $+ \n"];
					sleep(10);
				}

				sleep(100);

				if ($type eq "exploit") {
					[$console sendString: "exploit -j\n"];
				}
				else {
					[$console sendString: "run -j\n"];
				}
			}, \$console, \$options, \$type, \$module);
		}, \$console, $options => $3, $type => $1, $module => $2, \$host));		
	}
	else {
		call_async($client, "module.execute", $1, $2, $3);
	}
}

sub rtime {
	return formatDate($1 * 1000L, 'yyyy-MM-dd HH:mm:ss Z');
}

sub deleteOnExit {
	[[new java.io.File: getFileProper($1)] deleteOnExit];
}

sub listDownloads {
	this('%types');
	local('$files $root $findf $hosts $host');
	$files = @();
	$root = $1;
	$findf = {
		if (-isDir $1) {
			return map($this, ls($1));
		}
		else {
			# determine the file content type
			local('$type $handle $data $path');
			if ($1 in %types) {
				$type = %types[$1];				
			}
			else {
				$handle = openf($1);
				$data = readb($handle, 1024);
				closef($handle);
				if ($data ismatch '\p{ASCII}*') {
					$type = "text/plain";
				}
				else {
					$type = "binary";
				}
				%types[$1] = $type;
			}

                        # figure out the path...
                        $path = strrep(getFileParent($1), $root, '');
                        if (strlen($path) >= 2) {
                                $path = substr($path, 1);
                        }

			# return a description of the file.
			return %(
				host => $host,
				name => getFileName($1),
				size => lof($1),
				updated_at => lastModified($1),
				location => $1,
				path => $path,
				content_type => $type
			);
		}
	};

	$hosts = map({ return getFileName($1); }, ls($root));
	foreach $host ($hosts) {
		addAll($files, flatten(
			map(
				lambda($findf, $root => getFileProper($root, $host), \$host, \%types),
				ls(getFileProper($root, $host))
			)));
	}

	return $files;
}

# parseTextTable("string", @(columns))
sub parseTextTable {
	local('$cols $regex $line @results $template %r $row $col $matches');

	# create the regex to hunt for our table...
	$cols = copy($2);
	map({ $1 = '(' . $1 . '\s+)'; }, $cols);
	$cols[-1] = '(' . $2[-1] . '.*)';
	$regex = join("", $cols);

	# search for stuff
	foreach $line (split("\n", $1)) {
		$line = ["$line" trim];

		if ($line ismatch $regex) {
			# ok... construct a template to parse our fixed width rows.
			$matches = matched();
			map({ $1 = 'Z' . strlen($1); }, $matches);
			$matches[-1] = 'Z*';
			$template = join("", $matches);
		}
		else if ($line eq "" && $template !is $null) {
			# oops, row is empty? we're done then...
			return @results;
		}
		else if ($template !is $null && "---*" !iswm $line) {
			# extract the row from the template and add to our results
			$row = map({ return [$1 trim]; }, unpack($template, $line));
			%r = %();
			foreach $col ($2) {
				%r[$col] = iff(size($row) > 0, shift($row), "");
			}
			push(@results, %r);
		}
	}
	return @results;
}

