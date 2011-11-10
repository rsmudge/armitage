import msf.*;
import java.awt.*;
import java.io.*;
import java.net.*;
import javax.swing.*;
import javax.imageio.*;

sub host_selected_items {
	local('$sid $session $i $s $h $o');

	host_attack_items($1, $2);

	if ($2[0] in %hosts && 'sessions' in %hosts[$2[0]]) {
		foreach $sid => $session (%hosts[$2[0]]['sessions']) {
			if ($session["type"] eq "meterpreter") {
				$i = menu($1, "Meterpreter $sid", $sid);
				showMeterpreterMenu($i, \$session, \$sid);
			}
			else if ($session["type"] eq "shell") {
				$i = menu($1, "Shell $sid", $sid);
				showShellMenu($i, \$session, \$sid);
			}
		}
	}

	item($1, "Services", 'v', lambda({ createServiceBrowser($hosts) }, $hosts => $2));
	item($1, "Scan", 'c', lambda({ launch_msf_scans(join(", ", $hosts)); }, $hosts => $2));

	separator($1);

	$h = menu($1, "Host", 'H');

		$o = menu($h, "Operating System", 'O');
		item($o, "Cisco IOS", 'C', setHostValueFunction($2, "os_name", "Cisco IOS"));
		item($o, "FreeBSD", 'F', setHostValueFunction($2, "os_name", "FreeBSD"));
		item($o, "Linux", 'L', setHostValueFunction($2, "os_name", "Linux"));
		item($o, "NetBSD", 'N', setHostValueFunction($2, "os_name", "NetBSD"));
		item($o, "Mac OS X", 'M', setHostValueFunction($2, "os_name", "Apple Mac OS X"));
		item($o, "OpenBSD", 'O', setHostValueFunction($2, "os_name", "OpenBSD"));
		item($o, "Printer", 'P', setHostValueFunction($2, "os_name", "Printer"));
		item($o, "Solaris", 'S', setHostValueFunction($2, "os_name", "Solaris"));
		item($o, "Unknown", 'U', setHostValueFunction($2, "os_name", ""));
		$i = menu($o, "Windows", 'W');
			item($i, '1. 95/98/2000', '1', setHostValueFunction($2, "os_name", "Micosoft Windows", "os_flavor", "2000"));
			item($i, '2. XP/2003', '2', setHostValueFunction($2, "os_name", "Microsoft Windows", "os_flavor", "XP"));
			item($i, '3. Vista/7', '3', setHostValueFunction($2, "os_name", "Microsoft Windows", "os_flavor", "Vista"));

		item($h, "Remove Host", 'R', clearHostFunction($2));
}

sub view_items {
	# make it so we can recreate this menu if necessary...
	setf('&recreate_view_items', lambda({ [$parent removeAll]; view_items($parent); }, $parent => $1));

	item($1, 'Console', 'C', { thread(&createConsoleTab); });
	
	if ($RPC_CONSOLE !is $null) {
		item($1, 'RPC Console', 'P', {
			[$frame addTab: "msfrpcd", $RPC_CONSOLE, {}];
		});
	}

	if ($mclient !is $client && $mclient !is $null) {
		item($1, 'Event Log', 'E', &createEventLogTab);
	}

	separator($1);

	item($1, 'Credentials', 'r', { thread(&createCredentialsTab); });
	item($1, 'Jobs', 'J', { thread(&createJobsTab); });

	if (!$REMOTE || $mclient !is $client) {
		item($1, 'Loot', 'L', { thread(&createLootBrowser) });
	}

	local('$t');
	$t = menu($1, 'Reporting', 'R');

	item($t, 'Activity Logs', 'A', gotoFile([new File: getFileProper(systemProperties()["user.home"], ".armitage")]));
	item($t, 'Export Data', 'E', { 
		thread({ 
			local('$file');
			$file = [new File: generateArtifacts()];
			[gotoFile($file)];
		}); 
	});

	separator($1);

	local('$t');
	$t = menu($1, 'Targets', 'T');
	item($t, 'Graph View', 'G', {
		[$preferences setProperty: "armitage.string.target_view", "graph"];
		createDashboard();
		savePreferences();
	});

	item($t, 'Table View', 'T', {
		[$preferences setProperty: "armitage.string.target_view", "table"];
		createDashboard();
		savePreferences();
	});
}

sub armitage_items {
	local('$m');

	item($1, 'Preferences', 'P', &createPreferencesTab);

	local('$f');
	$f = {
		[$preferences setProperty: "armitage.required_exploit_rank.string", $rank];
		savePreferences();
		showError("Updated minimum exploit rank.");
	};

	$m = menu($1, 'Set Exploit Rank', 'R');
	item($m, "Excellent", 'E', lambda($f, $rank => "excellent"));
	item($m, "Great", 'G', lambda($f, $rank => "great"));
	item($m, "Good", 'o', lambda($f, $rank => "good"));
	item($m, "Normal", 'N', lambda($f, $rank => "normal"));
	item($m, "Poor", 'E', lambda($f, $rank => "poor"));

	separator($1);

	item($1, 'SOCKS Proxy...', 'r', &manage_proxy_server);

	$m = menu($1, 'Listeners', 'L');
		item($m, 'Bind (connect to)', 'B', &connect_for_shellz);
		item($m, 'Reverse (wait for)', 'R', &listen_for_shellz); 

	separator($1);

	item($1, 'Exit', 'x', { 
		if ($msfrpc_handle !is $null) {
			closef($msfrpc_handle);
		}

		[System exit: 0]; 
	});

}

sub main_attack_items {
	local('$k');
	item($1, "Find Attacks", 'A', {
		thread({
			findAttacks("p", min_rank());
		});
	});

	item($1, "Hail Mary", 'H', {
		thread({
			smarter_autopwn("p", min_rank()); 
		});
	});

	separator($1);

	item($1, "Browser Autopwn...", 'B', &manage_browser_autopwn);

	cmd_safe("show exploits", {
		local('$line $os $type $id $rank $name $k $date $exploit');

		foreach $line (split("\n", $3)) {
			local('@ranks');
			@ranks = @('normal', 'good', 'great', 'excellent');
			while (size(@ranks) > 0 && @ranks[0] ne min_rank()) {
				@ranks = sublist(@ranks, 1);
			}

			if ($line ismatch '\s+((.*?)\/.*?\/.*?)\s+(\d\d\d\d-\d\d-\d\d)\s+(' . join('|', @ranks) . ')\s+(.*?)') {
				($exploit, $os, $date, $rank, $name) = matched();
				%exploits[$exploit] = %(
					name => $name,
					os => $os,
					date => parseDate('yyyy-MM-dd', $date),
					rank => $rank,
					rankScore => rankScore($rank)
				);
			}
		}
		warn("Remote Exploits Synced");
	});
}

sub gotoURL {
	return lambda({ 
		[[Desktop getDesktop] browse: $url];
	}, $url => [[new URL: $1] toURI]);
}

sub help_items {
	item($1, "Homepage", 'H', gotoURL("http://www.fastandeasyhacking.com/")); 
	item($1, "Tutorial", 'T', gotoURL("http://www.fastandeasyhacking.com/manual")); 
	item($1, "Issue Tracker", 'I', gotoURL("http://code.google.com/p/armitage/issues/list")); 
	separator($1);
	item($1, "About", 'A', {
		local('$dialog $handle $label');
		$dialog = dialog("About", 320, 200);
		[$dialog setLayout: [new BorderLayout]];
		
		$label = [new JLabel: [new ImageIcon: [ImageIO read: resource("resources/armitage-logo.gif")]]];

		[$label setBackground: [Color black]];
		[$label setForeground: [Color gray]];
		[$label setOpaque: 1];

		$handle = [SleepUtils getIOHandle: resource("resources/about.html"), $null]; 
		[$label setText: readb($handle, -1)];
		closef($handle);
		
		[$dialog add: $label, [BorderLayout CENTER]];
		[$dialog pack];
		[$dialog setLocationRelativeTo: $null];
		[$dialog setVisible: 1];
	});
}


# create_workspace_menus($parent_menu, $active)
# dynamic workspaces... y0.
sub client_workspace_items {
	local('$index $workspace');

	item($1, 'Create', 'C', 
		lambda({
			local('$dialog $name $host $ports $os $button $session');
			$dialog = dialog("New Dynamic Workspace", 640, 480);
			[$dialog setLayout: [new GridLayout: 6, 1]];

			$name  = [new JTextField: 16];
			$host  = [new JTextField: 16];
			$ports = [new JTextField: 16];
			$os    = [new JTextField: 16];
			$session = [new JCheckBox: "Hosts with sessions only"];
			$button = [new JButton: "Add"];

			[$dialog add: label_for("Name:", 60, $name)]; 
			[$dialog add: label_for("Hosts:", 60, $host)]; 
			[$dialog add: label_for("Ports:", 60, $ports)]; 
			[$dialog add: label_for("OS:", 60, $os)]; 
			[$dialog add: $session];

			[$dialog add: center($button)];
			[$dialog pack];
			[$dialog show];

			[$button addActionListener: lambda({
				# yay, we have a dialog...
				local('$n $h $p $o $s');
				$n = [$name getText];
				$h = strrep([$host getText], '*', '%', '?', '_');
				$p = [$ports getText];
				$o = strrep([$os getText], '*', '%', '?', '_');
				$s = [$session isSelected];

				# save the new menu
				local('$menus');
				$menus = [$preferences getProperty: "armitage.workspaces.menus", ""];
				$menus = split('\|', $menus);
				push($menus, join("@@", @($n, $h, $p, $o, $s)));
				[$preferences setProperty: "armitage.workspaces.menus", join("!!", $menus)];
				savePreferences();

				# switch to it!
				thread(lambda({
					call($mclient, "db.filter", %(os => $o, ports => $p, hosts => $h, session => $s));
					refreshTargets();
				}, \$o, \$p, \$h, \$s));

				[$frame setTitle: "Armitage - $n"];

				elog("switched to workspace: $n");

				# add the new menu back...
				[$parent removeAll];
				client_workspace_items($parent);

				[$dialog setVisible: 0];
			}, \$parent, \$dialog, \$host, \$ports, \$os, \$name, \$session)];
		}, $parent => $1));

	item($1, 'Reset', 'R', 
		lambda({
			[$preferences setProperty: "armitage.workspaces.menus", ""];
			savePreferences();
			[$frame setTitle: "Armitage"];
			thread({ 
				call($mclient, "db.filter", %()); 
				refreshTargets();
			});
			[$parent removeAll];
			client_workspace_items($parent);
		}, $parent => $1));

	separator($1);

	item($1, "Show All", "S", {
		[$frame setTitle: "Armitage"];
		thread({
			call($mclient, "db.filter", %());
			refreshTargets();
		});
		elog("removed workspace filter");
	});

	local('$menus $menu $name $host $ports $os $x $session');
	$menus = [$preferences getProperty: "armitage.workspaces.menus", ""];
	$menus = split('!!', $menus);
	foreach $x => $menu (filter({ return iff($1, $1); }, $menus)) {
		($name, $host, $ports, $os, $session) = split('@@', $menu);
		item($1, "$x $+ . $name", $x, lambda({
			thread(lambda({
				call($mclient, "db.filter", %(os => $os, ports => $ports, hosts => $host, session => $session));
				refreshTargets();
			}, \$os, \$ports, \$host, \$session));
			elog("switched to workspace: $name");
			[$frame setTitle: "Armitage - $name"];
		}, \$host, \$ports, \$os, \$name, \$session));
	}
}

sub init_menus {
	local('$top $a $b $c $d $e $f');
	$top = [$1 getJMenuBar];

	$a = menu($top, "Armitage", 'A');
	armitage_items($a);

	$a = menu($top, "View", 'V');
	view_items($a);

	$c = menu($top, 'Hosts', 'o');
	host_items($c);

	$d = menu($top, 'Attacks', 'C');
	main_attack_items($d);

	$e = menu($top, 'Workspaces', 'W');
	client_workspace_items($e);

	$f = menu($top, 'Help', 'H');
	help_items($f);
}
