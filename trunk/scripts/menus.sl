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

	$s = item($1, "Services", 'v', lambda({ createServiceBrowser($hosts) }, $hosts => $2));

	separator($1);

	$h = menu($1, "Host", 'H');

		$o = menu($h, "Operating System", 'O');
		item($o, "FreeBSD", 'F', setHostValueFunction($2, "os_name", "FreeBSD"));
		item($o, "Linux", 'L', setHostValueFunction($2, "os_name", "Linux"));
		item($o, "NetBSD", 'N', setHostValueFunction($2, "os_name", "NetBSD"));
		item($o, "Mac OS X", 'M', setHostValueFunction($2, "os_name", "Mac OS X"));
		item($o, "Printer", 'P', setHostValueFunction($2, "os_name", "Printer"));
		item($o, "Solaris", 'S', setHostValueFunction($2, "os_name", "Solaris"));
		item($o, "Unknown", 'U', setHostValueFunction($2, "os_name", ""));
		$i = menu($o, "Windows", 'W');
			item($i, '1. 95/98/2000', '1', setHostValueFunction($2, "os_name", "Windows", "os_flavor", "2000"));
			item($i, '2. XP/2003', '2', setHostValueFunction($2, "os_name", "Windows", "os_flavor", "XP"));
			item($i, '3. Vista/7', '3', setHostValueFunction($2, "os_name", "Windows", "os_flavor", "Vista"));

		item($h, "Remove Host", 'R', clearHostFunction($2));
}

sub view_items {
	item($1, 'Console', 'C', &createConsoleTab);
	item($1, 'Targets', 'T', &createTargetTab);
	item($1, 'Credentials', 'r', &createCredentialsTab);
	item($1, 'Jobs', 'J', &createJobsTab);
}

sub armitage_items {
	local('$m');

	item($1, 'Preferences', 'P', &createPreferencesTab);

	separator($1);

	item($1, 'SOCKS Proxy...', 'r', &manage_proxy_server);

	$m = menu($1, 'Listeners', 'S');
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
	$k = menu($1, "Find Attacks", 'A');
		item($k, "by port", 'P', { findAttacks("p", min_rank()); });
		item($k, "by vulnerability", 'V', { findAttacks("x", min_rank()); });

	cmd($client, $console, "show exploits", lambda({
		local('%menus $menu %mm $line $os $type $id $rank $name $k');

		separator($parent);
		%menus["browser"] = menu($parent, "Browser Attacks", "B");
		%menus["email"] = menu($parent, "Email Attacks", "E");
		%menus["fileformat"] = menu($parent, "Evil Files", "F");
		separator($parent);
		%mm = %(browser => %(), email => %(), fileformat => %());
		
		foreach $line (split("\n", $3)) {
			local('@ranks');
			@ranks = @('normal', 'good', 'great', 'excellent');
			while (size(@ranks) > 0 && @ranks[0] ne min_rank()) {
				@ranks = sublist(@ranks, 1);
			}

			if ($line ismatch '\s+(.*?)\/(browser|email|fileformat)\/(.*?)\s+.*?\s+(' . join('|', @ranks) . ')\s+(.*?)') {
				($os, $type, $id, $rank, $name) = matched();

				if ($os !in %mm[$type]) {
					%mm[$type][$os] = menu(%menus[$type], $os, $null);	
				}
				$menu = %mm[$type][$os];

				item($menu, "$id", $null, lambda({
					launch_dialog($id, "exploit", "$os $+ / $+ $type $+ / $+ $id", 1);
				}, \$os, \$type, \$id));
			}
		}	

		item($parent, "Browser Autopwn...", 'B', &manage_browser_autopwn);
		item($parent, "File Autopwn...", 'F', &manage_file_autopwn);

		separator($parent);
		$k = menu($parent, "Hail Mary", 'H');
		item($k, "by port", 'P', { 
			db_autopwn("p", min_rank()); 
		});
		item($k, "by vulnerability", 'V', {
			db_autopwn("x", min_rank()); 
		});
	}, $parent => $1));
}

sub gotoURL {
	return lambda({ 
		[[Desktop getDesktop] browse: $url];
	}, $url => [[new URL: $1] toURI]);
}

sub help_items {
	item($1, "Tutorial", 'T', gotoURL("http://www.fastandeasyhacking.com/manual")); 
	item($1, "Homepage", 'H', gotoURL("http://www.fastandeasyhacking.com/")); 
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
		[$dialog setVisible: 1];
	});
}

sub client_workspace_items {
	local('$s $current $index $workspace');
	$current = call($client, "db.current_workspace")["workspace"];

	item($1, 'Create', 'C', 
		lambda({
			local('$name');

			$name = ask("Workspace name:");
			if ($name is $null) {
				return;
			}

			call($client, "db.add_workspace", $name);
			call($client, "db.set_workspace", $name);

			@workspaces = getWorkspaces();

			[$parent removeAll];
			client_workspace_items($parent);
			refreshTargets();
		}, $parent => $1));

	if ($current ne "default") {
		item($1, 'Delete', 'D', 
			lambda({
				call($client, "db.del_workspace", $current);

				@workspaces = getWorkspaces();

				[$parent removeAll];
				client_workspace_items($parent);
				refreshTargets();
			}, $parent => $1, \$current));
	}

	separator($1);

	foreach $index => $workspace (@workspaces) {
		item($1, iff($workspace eq $current, "$index $+ . $workspace *", "$index $+ . $workspace"), $index, lambda({
			call($client, "db.set_workspace", $ws);
			[$parent removeAll];
			client_workspace_items($parent);
			refreshTargets();
		}, $ws => $workspace, $parent => $1));
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
