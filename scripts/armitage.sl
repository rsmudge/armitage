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

global('$frame $tabs $menubar $msfrpc_handle');

sub describeHost {
	local('$sessions $os @overlay $ver');
	($sessions, $os, $ver) = values($1, @('sessions', 'os_name', 'os_flavor'));

	if (size($sessions) == 0) {
		return $1['address'];
	}
	return $1['address'] . "\n" . values($sessions)[0]["info"];
}

sub showHost {
	local('$sessions $os @overlay $match');
	($sessions, $os, $match) = values($1, @('sessions', 'os_name', 'os_flavor'));

	if ($os eq "Printer" || "*Printer*" iswm $match || $os eq "embedded") {
		return overlay_images(@('resources/printer.png'));
	}
	else if ($os eq "Windows") {
		if ("*2000*" iswm $match || "*95*" iswm $match || "*98*" iswm $match || "*ME*" iswm $match) {
			push(@overlay, 'resources/windows2000.png');
		}
		else if ("*XP*" iswm $match || "*2003*" iswm $match) {
			push(@overlay, 'resources/windowsxp.png');
		}
		else {
			push(@overlay, 'resources/windows7.png');
		}
	}
	else if ($os eq "Mac OS X") {
		push(@overlay, 'resources/macosx.png');
	}
	else if ($os eq "Linux") {
		push(@overlay, 'resources/linux.png');
	}
	else if ($os eq "IOS") {
		# this needs to be tested with a Cisco device
		#push(@overlay, 'resources/cisco.png');
		push(@overlay, 'resources/unknown.png');
	}
	else if ("*BSD*" iswm $os) {
		push(@overlay, 'resources/bsd.png');
	}
	else if ($os eq "Solaris") {
		push(@overlay, 'resources/solaris.png');
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

	return overlay_images(@overlay);
}

sub connectToMetasploit {
	local('$thread');
	$thread = [new Thread: lambda(&_connectToMetasploit, \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8)];
	[$thread start];
}

sub _connectToMetasploit {
	global('$client $console @exploits @auxiliary @payloads @workspaces $flag $exception');

	local('%props $property $value');

	# \$host, \$port, \$ssl, \$user, \$pass, \$driver, \$connect, $save?
	if ($8) {
		%props['connect.host.string'] = $1;
		%props['connect.port.string'] = $2;
		%props['connect.ssl.boolean'] = iff($3, "true", "");
		%props['connect.user.string'] = $4;
		%props['connect.pass.string'] = $5;
		%props['connect.db_driver.string'] = $6;
		%props['connect.db_connect.string'] = $7;

		foreach $property => $value (%props) {
			[$preferences setProperty: $property, $value];
		}
		savePreferences();
	}

	local('$progress');
	$progress = [new ProgressMonitor: $null, "Connecting to $1 $+ : $+ $2", "first try... wish me luck.", 0, 100];

	$flag = 1;
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

		        $client = [new RpcConnection: $4, $5, $1, long($2), $3, $debug];
			$flag = $null;
			[$progress close];
		}
		catch $exception {
			[$progress setNote: [$exception getMessage]];
			[$progress setProgress: $flag];
			$flag++;
			sleep(1000);
		}
	}	
	$console = createConsole($client);

	@exploits = sorta(call($client, "module.exploits")["modules"]);
	@auxiliary = sorta(call($client, "module.auxiliary")["modules"]);
	@payloads = sorta(call($client, "module.payloads")["modules"]);

	requireDatabase($client, $6, $7, {
		@workspaces = getWorkspaces();
		getBindAddress();
		main();
	}, &connectDialog);
}

sub main {
        local('$console $panel');

	$frame = [new ArmitageApplication];
        [$frame setSize: 800, 600];

	init_menus($frame);

	[$frame setIconImage: [ImageIO read: resource("resources/armitage-icon.gif")]];
        [$frame show];
	[$frame setExtendedState: [JFrame MAXIMIZED_BOTH]];

	# this window listener is dead-lock waiting to happen. That's why we're adding it in a
	# separate thread (Sleep threads don't share data/locks).
	fork({
		[$frame addWindowListener: {
			if ($0 eq "windowClosing" && $msfrpc_handle !is $null) {
				closef($msfrpc_handle);
			}
		}];
	}, \$msfrpc_handle, \$frame);

	createDashboard();
	createConsoleTab();

	if (-exists "command.txt") {
		deleteFile("command.txt");
	}
}

setLookAndFeel();
connectDialog();


