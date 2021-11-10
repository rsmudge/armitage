#
# Armitage Collaboration Feature... make no mistake, I'm extremely excited about this.
#

import msf.*;
import armitage.*;
import console.*;
import ssl.*;

sub createEventLogTab {
	this('$console $client');

	if ($client is $null && $console is $null) {
		$console = [new ActivityConsole: $preferences];
		setupEventStyle($console);
		logCheck($console, "all", "events");

		# define a menu for the eventlog
		[$console setPopupMenu: {
			installMenu($2, "eventlog", @());
		}];

		$client = [$cortana getEventLog: $console];
		[$client setEcho: $null];
		[$console updatePrompt: "> "];
		[new EventLogTabCompletion: $console, $mclient];
	}
	else {
		[$console updateProperties: $preferences];
	}

	[$frame addTab: "Event Log", $console, $null];
}

sub verify_server {
	this('%rejected');
	local('$fingerprints $fingerprint $check');
	$fingerprints = split(', ', [$preferences getProperty: "trusted.servers", ""]);
	foreach $fingerprint ($fingerprints) {
		if ($fingerprint eq $1) {
			return 1;
		}
	}

	if (%rejected[$1] == 1) {
		return $null;
	}

	$check = [javax.swing.JOptionPane showConfirmDialog: $null, "The team server's fingerprint is:\n\n<html><body><b> $+ $1 $+ </b></body></html>\n\nDoes this match the fingerprint shown\nwhen the team server started?", "Verify Fingerprint", [javax.swing.JOptionPane YES_NO_OPTION]];

	if ($check) {
		%rejected[$1] = 1;
		return $null;
	}
	else {
		push($fingerprints, $1);
		[$preferences setProperty: "trusted.servers", join(", ", $fingerprints)];
		savePreferences();
		return 1;
	}
}

sub c_client {
	# run this thing in its own thread to avoid really stupid deadlock situations
	local('$handle $socket');
	$socket = [new SecureSocket: $1, int($2), &verify_server];
	[$socket authenticate: $4];
	$handle = [$socket client];
	push(@CLOSEME, $handle);
	return wait(fork({
		local('$client');
		$client = newInstance(^RpcConnection, lambda({
			local('$ex');
			try {
				writeObject($handle, @_);
				[[$handle getOutputStream] flush];
				return readObject($handle);
			}
			catch $ex {
				[$DNOTIFIER fireDisconnectEvent: "$ex"];
			}
		}, \$handle, \$DNOTIFIER));
		return [new RpcAsync: $client];
	}, \$handle, \$DNOTIFIER));
}

sub userFingerprint {
	return unpack("H*", digest(values(systemProperties(), @("os.name", "user.home", "os.version")), "MD5"))[0];
}

sub setup_collaboration {
	local('$nick %r $mclient');
	
	$nick = ask("What is your nickname?");

	while (["$nick" trim] eq "") {
		$nick = ask("You can't use a blank nickname. What do you want?");
	}

	$mclient = c_client($3, $4, $1, $2);
	%r = call($mclient, "armitage.validate", $1, $2, $nick, "armitage", 140921);
	if (%r["error"] eq "1") {
		showErrorAndQuit(%r["message"]);
		return $null;
	}

	%r = call($client, "armitage.validate", $1, $2, $null, "armitage", 140921);
	$NICK = $nick;
	$DESCRIBE = "$nick $+ @ $+ $3";
	return $mclient;
}

sub uploadFile {
	if ($mclient !is $client) {
		# upload a (potentially) big file
		return [[new ui.UploadFile: $mclient, [new java.io.File: $1], $null] getRemoteFile];
	}
	else {
		return $1;
	}
}

# upload a file if it needs to be uploaded
# uploadBigFile("/path/to/file", &callback);
sub uploadBigFile {
	# do nothing if there is no file
	if ($1 is $null || !-exists $1) {
		return;
	}

	if ($mclient !is $client) {
		# upload a (potentially) big file
		[new ui.UploadFile: $mclient, [new java.io.File: $1], $2];
	}
	else {
		# should always be async of the caller, hence we do it this way
		thread(lambda({
			[$func : $file];
		}, $func => $2, $file => $1));
	}
}

sub downloadFile {
	[lambda({
		local('$file $handle %r');
		call_async_callback($mclient, "armitage.download", $this, $a);
		yield;
		%r = convertAll($1);
		$file = iff($b, $b, getFileName($a));	
		$handle = openf("> $+ $file");
		writeb($handle, %r['data']);
		closef($handle);
		[$c: $file];
	}, $a => $1, $b => $2, $c => $3)];
}

sub getFileContent {
	local('$file $handle %r');
	if ($mclient !is $client) {
		%r = call($mclient, "armitage.download_nodelete", $1);
		return %r['data'];
	}
	else {
		$handle = openf($1);
		$file = readb($handle, -1);
		closef($handle);
		return $file;
	}
}

# returns the folder where files should be downloaded to!
sub downloadDirectory {
	if ($client is $mclient) {
		local('@dirs $start $dir');
		$start = dataDirectory();
		push(@dirs, "downloads");
		addAll(@dirs, @_);
	
		foreach $dir (@dirs) {
			if (isWindows()) {
				$dir = strrep($dir, "/", "\\", ":", "");
			}
			$start = getFileProper($start, $dir);
		}
		return $start;
	}
	else {
		return "downloads/" . join("/", @_);
	}
}
