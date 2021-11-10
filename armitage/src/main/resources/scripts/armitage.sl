debug(7 | 34);

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.border.*;
import javax.imageio.*;

import java.awt.*;
import java.awt.event.*;

import msf.*;
import console.*;
import armitage.*;
import graph.*;

import java.awt.image.*;

global('$frame $tabs $menubar $msfrpc_handle $REMOTE $cortana $MY_ADDRESS $DESCRIBE @CLOSEME @POOL $NICK $MSFVERSION $DNOTIFIER');

sub describeHost {
	local('$desc');
	$desc = _describeHost($1);
	return filter_data("host_describe", $desc, $1)[0];
}

sub _describeHost {
	local('$sessions $os @overlay $ver $info');
	($sessions, $os, $ver) = values($1, @('sessions', 'os_name', 'os_flavor'));

	if (size($sessions) == 0) {
		return $1['address'];
	}

	$info = values($sessions)[0]["info"];
	if ("Microsoft Corp." isin $info) {
		return $1['address'] . "\nshell session";
	}
	else if ($info ne "") {
		return $1['address'] . "\n $+ $info";
	}
	else {
		return $1['address'];
	}
}

sub showHost {
	local('$sessions $os @overlay $match $purpose');
	($sessions, $os, $match, $purpose) = values($1, @('sessions', 'os_name', 'os_flavor', 'purpose'));
	$os = normalize($os);

	if ($match eq "") {
		$match = $1['os_match'];
	}

	if ($os eq "Printer" || "*Printer*" iswm $match || "*embedded*" iswm lc($os)) {
		return overlay_images(@('resources/printer.png'));
	}
	else if ($os eq "Windows") {
		if ("*2000*" iswm $match || "*95*" iswm $match || "*98*" iswm $match || "*ME*" iswm $match || "*Me*" iswm $match) {
			push(@overlay, 'resources/windows2000.png');
		}
		else if ("*XP*" iswm $match || "*2003*" iswm $match || "*.NET*" iswm $match) {
			push(@overlay, 'resources/windowsxp.png');
		}
		else if ("*8*" iswm $match && "*2008*" !iswm $match) {
			push(@overlay, 'resources/windows8.png');
		}
		else if ("*2012*" iswm $match) {
			push(@overlay, 'resources/windows8.png');
		}
		else {
			push(@overlay, 'resources/windows7.png');
		}
	}
	else if ($os eq "Apple iOS" || "*AppleTV*" iswm $os) {
		push(@overlay, 'resources/ios.png');
	}
	else if ($os eq "Mac OS X" || "*apple*" iswm lc($os) || "*mac*os*x*" iswm lc($os)) {
		push(@overlay, 'resources/macosx.png');
	}
	else if ("*linux*" iswm lc($os)) {
		push(@overlay, 'resources/linux.png');
	}
	else if ($os eq "IOS" || "*cisco*" iswm lc($os)) {
		push(@overlay, 'resources/cisco.png');
	}
	else if ("*BSD*" iswm $os) {
		push(@overlay, 'resources/bsd.png');
	}
	else if ($os eq "Solaris") {
		push(@overlay, 'resources/solaris.png');
	}
	else if ("*VMware*" iswm $os) {
		push(@overlay, 'resources/vmware.png');
	}
	else if ($os eq "Android") {
		push(@overlay, 'resources/android.png');
	}
	else if ($purpose eq "firewall") {
		return overlay_images(@('resources/firewall.png'));
	}
	else {
		push(@overlay, 'resources/unknown.png');
	}

	if (size($sessions) > 0) {
		push(@overlay, 'resources/hacked.png'); 
	}
	else {
		push(@overlay, 'resources/computer.png');
	}

	return overlay_images(filter_data("host_image", @overlay, $1)[0]);
}

sub connectToMetasploit {
	local('$thread $5');
	$thread = [new Thread: lambda(&_connectToMetasploit, \$1, \$2, \$3, \$4, \$5)];
	[$thread start];
}

sub _connectToMetasploit {
	global('$database $aclient $client $mclient $console @exploits @auxiliary @payloads @post');

	# reset rejected fingerprints
	let(&verify_server, %rejected => %());

	# update preferences

	local('%props $property $value $flag $exception');
	%props['connect.host.string'] = $1;
	%props['connect.port.string'] = $2;
	%props['connect.user.string'] = $3;
	%props['connect.pass.string'] = $4;

	if ($5 is $null) {
		foreach $property => $value (%props) {
			[$preferences setProperty: $property, $value];
		}
	}
	savePreferences();

	# intermediate object to track disconnect notifications
	$DNOTIFIER = [new DisconnectNotifier];
	[$DNOTIFIER addDisconnectListener: {
		# print a helpful(?) message
		print_error("Lost a connection ( $+ $1 $+ ): disconnecting all!");

		# closing all connections should trigger a cascading effect of sorts, to kick in normal disconnect behavior
		map({ closef($1); }, @CLOSEME);
	}];

	# setup progress monitor
	local('$progress');
	$progress = [new ProgressMonitor: $null, "Connecting to $1 $+ : $+ $2", "first try... wish me luck.", 0, 100];

	# keep track of whether we're connected to a local or remote Metasploit instance. This will affect what we expose.
	$REMOTE = iff($1 eq "127.0.0.1" || $1 eq "::1" || $1 eq "localhost", $null, 1);

	$flag = 10;
	while ($flag) {
		try {
			if ([$progress isCanceled]) {
				if ($msfrpc_handle !is $null) {
					try {
						wait(fork({ closef($msfrpc_handle); }, \$msfrpc_handle), 5 * 1024);
						$msfrpc_handle = $null;
					}
					catch $exception {
						[JOptionPane showMessageDialog: $null, "Unable to shutdown MSFRPC programatically\nRestart Armitage and try again"];
						[System exit: 0];
					}
				}
				connectDialog();
				return;
			}

			# connecting locally? go to Metasploit directly...
			if ($REMOTE is $null) {
				$client = [new MsgRpcImpl: $3, $4, $1, long($2), $null, $debug];
				$aclient = [new RpcAsync: $client];
				$mclient = $client;
				push(@POOL, $aclient);
				initConsolePool();
				$DESCRIBE = "localhost";
			}
			# we have a team server... connect and authenticate to it.
			else {
				[$progress setNote: "Connected: logging in"];
				$client = c_client($1, $2, $3, $4);
				$mclient = setup_collaboration($3, $4, $1, $2);
				$aclient = $mclient;

				if ($mclient is $null) {
					[$progress close];
					return;
				}
				else {
					[$progress setNote: "Connected: authenticated"];
				}

				# create six additional connections to team server... for balancing consoles.
				local('$x $cc');
				for ($x = 0; $x < 6; $x++) {
					$cc = c_client($1, $2, $3, $4);
					call($cc, "armitage.validate", $3, $4, $null, "armitage", 140921);
					push(@POOL, $cc);
				}
			}
			$flag = $null;
		}
		catch $exception {
			[$progress setNote: [$exception getMessage]];
			[$progress setProgress: $flag];
			$flag++;
			sleep(2500);
		}
	}

	# first things first, get version information...
	local('$rep $major $minor $update');
	$rep = call($mclient, "core.version");

	if ($rep['version'] ismatch '(\d+)\.(\d+)\.(.*?)') {
		($major, $minor, $update) = matched();
		$MSFVERSION = ($major * 10000) + ($minor * 100) + $update;
		if ($MSFVERSION < 40900) {
			[JOptionPane showMessageDialog: $null, "Metasploit $major $+ . $+ $minor is too old. Get 4.9 or later."];
			if ($msfrpc_handle) { closef($msfrpc_handle); }
			[System exit: 0];
		}
	}

	# now go and do everything else...
	let(&postSetup, \$progress);

	[$progress setNote: "Connected: Getting base directory"];
	[$progress setProgress: 30];

	setupBaseDirectory();

	if (!$REMOTE) {
		[$progress setNote: "Connected: Connecting to database"];
		[$progress setProgress: 40];

		try {
			# create a console to force the database to initialize
			local('$c');
			$c = createConsole($client);
			call_async($client, "console.release", $c);

			# connect to the database plz...
			$database = connectToDatabase();
			[$client setDatabase: $database];

			# setup our reporting stuff (has to happen *after* base directory)
			initReporting();
		}
		catch $exception {
			if ("Kali" isin [$exception getMessage]) {
				[JOptionPane showMessageDialog: $null, [$exception getMessage]];
			}
			else {
				[JOptionPane showMessageDialog: $null, "Could not connect to database.\n\nKali Linux 1.x users, try:\n\nservice postgresql start\nservice metasploit start\nservice metasploit stop\n\nKali Linux 2.x users, try:\n\n/etc/init.d/postgresql start\n\n" . [$exception getMessage]];
			}
			if ($msfrpc_handle) { closef($msfrpc_handle); }
			[System exit: 0];
		}
	}

	# check the module cache...
	local('$sanity');
	$sanity = call($mclient, "module.options", "exploit", "windows/smb/ms08_067_netapi");
	if ($sanity is $null) {
		print_error("detected corrupt module cache... restart Metasploit for fix to take effect (#1)");
		call($mclient, "db.clear_cache");
	}

	# check for comingled module data... and fix it.
	$sanity = call($mclient, "module.post");
	if ("pro/cisco/gather/ios_info" in $sanity['modules']) {
		print_error("detected corrupt module cache... restart Metasploit for fix to take effect (#2)");
		call($mclient, "db.clear_cache");
	}

	# is some other stupidity happening?
	try {
		# this RPC call likes to fail when the module cache is broken too
		[$mclient execute: "session.compatible_modules", cast(@("0"), ^Object)];
	}
	catch $sanity {
		warn($sanity);
		print_error("detected corrupt module cache... restart Metasploit for fix to take effect (#3)");
		call($mclient, "db.clear_cache");
	}

	[$progress setNote: "Connected: Getting local address"];
	[$progress setProgress: 50];

	cmd_safe("setg", lambda({
		# store the current global vars to save several other calls later
		global('%MSF_GLOBAL');
		local('$value');
	
		foreach $value (parseTextTable($3, @("Name", "Value"))) {
			%MSF_GLOBAL[$value['Name']] = $value['Value'];
		}

		# ok, now let's continue on with what we're doing...
		getBindAddress();
		[$progress setNote: "Connected: ..."];
		[$progress setProgress: 60];

		dispatchEvent(&postSetup);
	}, \$progress));
}

sub postSetup {
	thread(lambda({
		[$progress setNote: "Connected: Fetching exploits"];
		[$progress setProgress: 65];

		@exploits  = sorta(call($mclient, "module.exploits")["modules"]);

		[$progress setNote: "Connected: Fetching auxiliary modules"];
		[$progress setProgress: 70];

		@auxiliary = sorta(call($mclient, "module.auxiliary")["modules"]);

		[$progress setNote: "Connected: Fetching payloads"];
		[$progress setProgress: 80];

		@payloads  = sorta(call($mclient, "module.payloads")["modules"]);

		[$progress setNote: "Connected: Fetching post modules"];
		[$progress setProgress: 90];

		@post      = sorta(call($mclient, "module.post")["modules"]);

		[$progress setNote: "Connected: Starting script engine"];
		[$progress setProgress: 95];

		$cortana = [new cortana.Cortana: $client, $mclient, $__events__, $__filters__, $DESCRIBE, $MSFVERSION];
		[$cortana setupCallbackIO];

		[$progress close];

		local('$frame');
		$frame = main();
		[$cortana setupArmitage: $frame, $preferences];

		# export some local functions for use by Cortana...
		[[$cortana getSharedData] put: "&launch_dialog",      &launch_dialog];
		[[$cortana getSharedData] put: "&attack_dialog",      &attack_dialog];
		[[$cortana getSharedData] put: "&savePreferences",    &savePreferences];
		[[$cortana getSharedData] put: "&showModules",        &showModules];
		[[$cortana getSharedData] put: "&show_login_dialog",  &show_login_dialog];
		[[$cortana getSharedData] put: "&show_psexec_dialog", &pass_the_hash];
		[[$cortana getSharedData] put: "&module_execute",     &module_execute];
		[[$cortana getSharedData] put: "&createDashboard",    &createDashboard];
		[[$cortana getSharedData] put: "&launch_msf_scans",   &launch_msf_scans];
		[[$cortana getSharedData] put: "&quickListDialog",    &quickListDialog];
		[[$cortana getSharedData] put: "&setupConsoleStyle",  &setupConsoleStyle];
		[[$cortana getSharedData] put: "&showScriptConsole",  &showScriptConsole];
		[[$cortana getSharedData] put: "&generateArtifacts",  &_generateArtifacts];
		[[$cortana getSharedData] put: "&createFileBrowser",  &createFileBrowser];

		if ($MY_ADDRESS ne "") {
			print_info("Starting Cortana on $MY_ADDRESS");
			[$cortana start: $MY_ADDRESS];
		}

		# this will tell Cortana to start consuming the output from our scripts.
		getCortanaConsole();

		local('$script');
		foreach $script (listScripts()) {
			try {
				if (-exists $script && -canread $script) {
					[$progress setNote: "Connected: Loading $script"];
					[$cortana loadScript: $script];
				}
			}
			catch $exception {
				showError("Could not load $script $+ :\n $+ $exception");
			}
		}

		createDashboard();
	}, \$progress));
}

sub main {
        local('$console $panel $dir $app');

	$frame = [new ArmitageApplication: $__frame__, $DESCRIBE, $mclient];
	[$frame setTitle: $TITLE];
	[$frame setIconImage: [ImageIO read: resource("resources/armitage-icon.gif")]];
	init_menus($frame);
	initLogSystem();

	# this window listener is dead-lock waiting to happen. That's why we're adding it in a
	# separate thread (Sleep threads don't share data/locks).
	fork({
		[$__frame__ addWindowListener: {
			if ($0 eq "windowClosing" && $msfrpc_handle !is $null) {
				closef($msfrpc_handle);
			}
		}];
	}, \$msfrpc_handle, \$__frame__);

	dispatchEvent({
		if ($client !is $mclient) {
			createEventLogTab();
		}
		else {
			createConsoleTab();
		}
	});

	if (-exists "command.txt") {
		deleteFile("command.txt");
	}

	return $frame;
}

sub checkDir {
	# set the directory where everything exciting and fun will happen.
	if (cwd() eq "/Applications" || !-canwrite cwd() || isWindows()) {
		local('$dir');
		$dir = getFileProper(systemProperties()["user.home"], "armitage-tmp");
		if (!-exists $dir) {
			mkdir($dir);
		}
		chdir($dir);
		print_info("I will use $dir as a working directory");
	}
}

checkDir();

if ($CLIENT_CONFIG !is $null && -exists $CLIENT_CONFIG) {
	local('$config');
	$config = [new Properties];
	[$config load: [new java.io.FileInputStream: $CLIENT_CONFIG]];
	connectToMetasploit([$config getProperty: "host", "127.0.0.1"], 
				[$config getProperty: "port", "55553"],
				[$config getProperty: "user", "msf"],
				[$config getProperty: "pass", "test"], 1);
}
else {
	connectDialog();
}
