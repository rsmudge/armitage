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

sub call_async {
	if (size(@_) > 2) {
		[$1 execute_async: $2, cast(sublist(@_, 2), ^Object)];
	}
	else {
		[$1 execute_async: $2];
	}
}

sub call_async_callback {
	if (size(@_) > 3) {
		[$1 execute_async: $2, cast(sublist(@_, 3), ^Object), $3];
	}
	else {
		[$1 execute_async: $2, $null, $3];
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
	return [cortana.core.FilterManager convertAll: $1];
}

# cleans the prompt text from an MSF RPC call
sub cleanText {
        return tr($1, "\x01\x02", "");
}

sub setupConsoleStyle {
	this('$style');
	if ($style is $null) {
		local('$handle');
		$handle = [SleepUtils getIOHandle: resource("resources/msfconsole.style"), $null];
		$style = join("\n", readAll($handle));
		closef($handle);
	}
	
	[$1 setStyle: filter_data("console_style", $style)[0]];
}

sub setupEventStyle {
	this('$style');
	if ($style is $null) {
		local('$handle');
		$handle = [SleepUtils getIOHandle: resource("resources/eventlog.style"), $null];
		$style = strrep(join("\n", readAll($handle)), '$ME$', $NICK);
		closef($handle);
	}

	[$1 setStyle: filter_data("event_style", $style)[0]];
}

sub createDisplayTab {
	local('$console $host $queue $file');
	$queue = [new ConsoleQueue: rand(@POOL)];
	if ($1 eq "Log Keystrokes") {
		$console = [new ActivityConsole: $preferences];
	}
	else {
		$console = [new Console: $preferences];
	}
	setupConsoleStyle($console);
	[$queue setDisplay: $console];
	[new QueueTabCompletion: $console, $queue];
	logCheck($console, iff($host, $host, "all"), iff($file, $file, strrep($1, " ", "_")));
	[$frame addTab: $1, $console, lambda({ [$queue destroy]; }, \$queue)];
	return $queue;
}

# creates a new metasploit console (with all the trimmings)
sub createConsolePanel {
	local('$console $thread $1');
	$console = [new Console: $preferences];
	setupConsoleStyle($console);

	$thread = [new ConsoleClient: $console, rand(@POOL), "console.read", "console.write", "console.destroy", $result['id'], $1];
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

	[$console setPopupMenu: {
		# eliminate parens and brackets
		if ("(*)" iswm $1 || "[*]" iswm $1) {
			$1 = substr($1, 1, -1);
		}

		# user right-clicked a host
		if ($1 in %hosts) {
			targetPopup(@($1), $2);
		}
	}];

	[$console addWordClickListener: lambda({
		local('$word $type $path');
		$word = [$1 getActionCommand];

		if ($word ismatch '(auxiliary|post|exploit|payload)/(.*)') {
			($type, $path) = matched();
			moduleAction($type, $path, @());
		}
		else if ($word in @auxiliary) {
			moduleAction("auxiliary", $word, @());
		}
		else if ($word in @exploits) {
			moduleAction("exploit", $word, @());
		}
		else if ($word in @payloads) {
			moduleAction("payload", $word, @());
		}
		else if ($word in @post) {
			moduleAction("post", $word, @());
		}
	}, \$thread)];

	return @($result['id'], $console, $thread);
}

sub createConsoleTab {
	local('$1 $2');
	[lambda(&_createConsoleTab): $1, $2];
}

sub _createConsoleTab {
	local('$id $console $thread $title $banner $result');
	($title, $banner) = @_;

	call_async_callback($client, "console.create", $this);
	yield;
	$result = convertAll($1);

	($id, $console, $thread) = createConsolePanel(
		iff([$preferences getProperty: "armitage.no_msf_banner.boolean", "false"] eq "true", 1, $banner),
		\$result
	);

	logCheck($console, "all", "console");
	[$frame addTab: iff($title is $null, "Console", $title), $console, $thread, $null];
}

sub setg {
	# update team server's understanding of LHOST
	if ($1 eq "LHOST") {
		call_async($client, "armitage.set_ip", $2);
	}

	%MSF_GLOBAL[$1] = $2;
	local('$c');
	$c = createConsole($client);
	call_async($client, "console.write", $c, "setg $1 $2 $+ \n");
	call_async($client, "console.release", $c);
}

sub createDefaultHandler {
	# setup a handler for meterpreter
	local('$port');
	$port = randomPort();
	setg("LPORT", $port);
	print_info("Creating a default reverse handler... 0.0.0.0: $+ $port");
	call_async($client, "module.execute", "exploit", "multi/handler", %(
		PAYLOAD => "windows/meterpreter/reverse_tcp",
		LHOST => "0.0.0.0",
		LPORT => $port,
		ExitOnSession => "false",
		EnableStageEncoding => "true",
		StageEncoder => "x86/call4_dword_xor"
	));
}

sub setupHandlers {
	find_job("Exploit: multi/handler", {
		if ($cortana !is $null) {
			print_info("Starting Cortana on $MY_ADDRESS");
			[$cortana start: $MY_ADDRESS];
		}

		if ($1 == -1) {
			createDefaultHandler();
		}
		else if ('LPORT' !in %MSF_GLOBAL) {
			createDefaultHandler();
		}
	});
}

# creates the metasploit console.
sub createConsole {
	local('$r');
	$r = call($1, "console.allocate");
	return $r['id'];
}

# creates a new console and execs a cmd in it.
# cmd_safe("command to execute");
sub cmd_safe {
	local('$queue $2');
	$queue = [new ConsoleQueue: $client];
	if ($2 !is $null) {
		[$queue addListener: $2];
	}
	[$queue start];
	[$queue addCommand: "x", $1];
	[$queue stop];
}

sub createNmapFunction {
	return lambda({
		ask_async("Enter scan range (e.g., 192.168.1.0/24):", join(" ", [$targets getSelectedHosts]), $this);
		yield;
		if ($1 eq "") { return; }

		local('$queue');
		$queue = createDisplayTab("nmap");
		elog("started a scan: nmap $args $1");

		[$queue addCommand: "x", "db_nmap $args $1"];
		[$queue addListener: {
			showError("Scan Complete!\n\nUse Attacks->Find Attacks to suggest\napplicable exploits for your targets.");
		}];
		[$queue start];
	}, $args => $1);
}

sub getBindAddress {
	local('$queue');
	if ('LHOST' in %MSF_GLOBAL) {
		$MY_ADDRESS = %MSF_GLOBAL['LHOST'];
		print_info("Used the incumbent: $MY_ADDRESS");
		setupHandlers();
	}
	else {
		$queue = [new ConsoleQueue: $client];
		[$queue addCommand: "x", "use windows/meterpreter/reverse_tcp"];
		[$queue addListener: lambda({
			local('$address');
			$address = convertAll([$queue tabComplete: "setg LHOST "]);
			$address = split('\\s+', $address[0])[2];
	
			if ($address eq "127.0.0.1") {
				[lambda({
					ask_async("Could not determine attack computer IP\nWhat is it?", "", $this);
					yield;
					if ($1 ne "") {
						$MY_ADDRESS = $1;
						thread({
							setg("LHOST", $MY_ADDRESS);
							setupHandlers();
						});
					}
					else {
						[$this];
					}
				})];
			}
			else {
				print_info("Used the tab method: $address");
				setg("LHOST", $address);
				$MY_ADDRESS = $address;
				setupHandlers();
			}
		}, \$queue)];
		[$queue start];
		[$queue stop];
	}
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
		print_info("Starting msfrpcd for you.");

		if (isWindows()) {
			warn("Metasploit on Windows is not supported by this tool");
		}
		else {
			$msfrpc_handle = exec("msfrpcd -f -a 127.0.0.1 -U $user -P $pass -S -p $port", convertAll([System getenv]));
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

					askYesNo($text, "Uh oh!", {
						[gotoURL("http://www.fastandeasyhacking.com/nomsfrpcd")];
					});
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
			print_error("msfrpcd is shut down!");
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

	local('$dialog $host $port $ssl $user $pass $button $start $center $help $helper');
	$dialog = window("Connect...", 0, 0);
	
	# setup our nifty form fields..

	$host = [new ATextField: [$preferences getProperty: "connect.host.string", "127.0.0.1"], 20];
	$port = [new ATextField: [$preferences getProperty: "connect.port.string", "55553"], 10];
	
	$user = [new ATextField: [$preferences getProperty: "connect.user.string", "msf"], 20];
	$pass = [new APasswordField: [$preferences getProperty: "connect.pass.string", "test"], 20];

	$button = [new JButton: "Connect"];
	[$button setToolTipText: "<html>Connects to Metasploit.</html>"];

	$help   = [new JButton: "Help"];
	[$help setToolTipText: "<html>Use this button to view the Getting Started Guide on the Armitage homepage</html>"];

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
		local('$h $p $u $s @o');

		# clean up the user options...
		@o = @([$host getText], [$port getText], [$user getText], [$pass getPass]);
		@o = map({ return ["$1" trim]; }, @o);
		($h, $p, $u, $s) = @o;

		[$dialog setVisible: 0];

		if ($h eq "127.0.0.1" || $h eq "::1" || $h eq "localhost") {
			if ($__frame__ && [$__frame__ checkLocal]) {
				showError("You can't connect to localhost twice");
				[$dialog setVisible: 1];
				return;
			}

			try {
				closef(connect("127.0.0.1", $p, 1000));
			}
			catch $ex {
				if (isWindows()) {
					showError("You must connect to a team server hosted on Linux.\nConnecting to a Metasploit RPC server on Windows is\nnot supported.");
					[$dialog setVisible: 1];
				}
				else {
					askYesNo("A Metasploit RPC server is not running or\nnot accepting connections yet. Would you\nlike me to start Metasploit's RPC server\nfor you?", "Start Metasploit?", lambda({
						startMetasploit($u, $s, $p);

						# this is the only path to connect to a local metasploit
						connectToMetasploit($h, $p, $u, $s);
					}, \$u, \$s, \$p, \$h));
				}
				return;
			}
		}

		connectToMetasploit($h, $p, $u, $s);
	}, \$dialog, \$host, \$port, \$user, \$pass)];

	[$help addActionListener: gotoURL("http://www.fastandeasyhacking.com/start")];

	[$dialog pack];
	[$dialog setLocationRelativeTo: $null];
	[$dialog setVisible: 1];
}

sub elog {
	local('$2');
	if ($client !is $mclient) {
		# $2 can be NULL here. team server will populate it...
		call_async($mclient, "armitage.log", $1, $2);
	}
	else {
		# since we're not on a team server, no one else will have
		# overwritten LHOST, so we can trust $MY_ADDRESS to be current
		if ($2 is $null) {
			$2 = $MY_ADDRESS;
		}
		call_async($client, "db.log_event", "$2 $+ //", $1);
	}
}

sub module_execute {
	return invoke(&_module_execute, filter_data_array("user_launch", @_));
}

sub _module_execute {
	local('$host $title $4');
	if ($4 >= 4) {
		# if we're applying this function against a lot of hosts ($4); then we don't want a new window
		# for each run.
		call_async($client, "module.execute", $1, $2, $3);
	}
	else if ([$preferences getProperty: "armitage.show_all_commands.boolean", "true"] eq "true" || $title) {

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

		# fix SMBPass and PASSWORD options if necessary...
		if ("PASSWORD" in $3) {
			$3['PASSWORD'] = fixPass($3['PASSWORD']);
		}

		if ("SMBPass" in $3) {
			$3['SMBPass'] = fixPass($3['SMBPass']);
		}

		# okie then, let's create a console and execute all of this stuff...	

		local('$queue $key $value');

		$queue = createDisplayTab(iff($title, $title, $1), \$host);

		[$queue addCommand: $null, "use $1 $+ / $+ $2"];
		[$queue setOptions: $3];
	
		if ($1 eq "exploit") {
			[$queue addCommand: $null, "exploit -j"];
		}
		else {
			[$queue addCommand: $null, "run -j"];
		}

		[$queue start];
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

sub initConsolePool {
	local('$pool');
	$pool = [new ConsolePool: $client];
	[$client addHook: "console.allocate", $pool];
	[$client addHook: "console.release", $pool];
	[$client addHook: "console.release_and_destroy", $pool];
}

sub fixPass {
	return replace(strrep($1, '\\', '\\\\'), '(\p{Punct})', '\\\\$1');
}

if (systemProperties()["java.specification.version"] eq "1.6") {
	print_error("Java 1.6 is not supported with this tool. Please upgrade to Java 1.7");
}
